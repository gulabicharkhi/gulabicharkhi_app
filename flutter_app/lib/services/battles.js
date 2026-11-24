const express = require('express');
const mongoose = require('mongoose');
const Battle = require('../models/Battle');
const Team = require('../models/Team');
const User = require('../models/User');
const Notification = require('../models/Notification');
const { protect } = require('../middleware/authMiddleware');

const router = express.Router();

// ==================== Helpers ====================

const fail = (res, status, message, extra = {}) =>
  res.status(status).json({ success: false, message, ...extra });

const wrap = (label, fn) => async (req, res) => {
  try {
    await fn(req, res);
  } catch (error) {
    console.error(`${label} error:`, error);
    if (!res.headersSent) fail(res, 500, 'Something went wrong. Try again.');
  }
};

const sid = (v) => String(v && v._id ? v._id : v);

// Battle ka summary object (list card ke liye)
const battleCard = (b, myTeamId) => {
  const myTeam = sid(b.challengerTeam) === sid(myTeamId) ? 'challenger' : 'opponent';
  return {
    id: b._id,
    status: b.status,
    venue: b.venue || '',
    area: b.area || '',
    challengerTeam: {
      id: b.challengerTeam._id || b.challengerTeam,
      name: b.challengerTeam.name || '',
      tag:  b.challengerTeam.tag  || '',
      logo: b.challengerTeam.logo || null,
    },
    opponentTeam: {
      id: b.opponentTeam._id || b.opponentTeam,
      name: b.opponentTeam.name || '',
      tag:  b.opponentTeam.tag  || '',
      logo: b.opponentTeam.logo || null,
    },
    challengerCuts: b.challengerCuts,
    opponentCuts:   b.opponentCuts,
    winner: b.winner,
    myRole: myTeam,
    challengedAt: b.challengedAt,
    startedAt:    b.startedAt,
    endedAt:      b.endedAt,
  };
};

// Battle ka detailed object (Battle screen ke liye)
const battleDetail = (b, userId) => {
  const isChallenger = sid(b.challengerCaptain) === sid(userId) || sid(b.challengerTeam?._id || b.challengerTeam) === String(userId);
  const myRole = isChallenger ? 'challenger' : 'opponent';
  return {
    ...battleCard(b, isChallenger ? b.challengerTeam : b.opponentTeam),
    myRole,
    challengerCaptain: b.challengerCaptain,
    opponentCaptain:   b.opponentCaptain,
    challengerReady:   b.challengerReady,
    opponentReady:     b.opponentReady,
    cutEvents: (b.cutEvents || []).map((c) => ({
      id: c._id,
      claimedBy:     c.claimedBy,
      claimedByTeam: c.claimedByTeam,
      cutPlayer:     c.cutPlayer || null,
      status:        c.status,
      rejectionReason: c.rejectionReason || '',
      createdAt:     c.createdAt,
      resolvedAt:    c.resolvedAt || null,
    })),
    startedAt:    b.startedAt,
    endedAt:      b.endedAt,
    challengedAt: b.challengedAt,
    acceptedAt:   b.acceptedAt,
  };
};

// User apni team ka captain hai?
const isCaptainOfTeam = (team, userId) => sid(team.captain) === sid(userId);

// User is battle ka participant (captain side se) hai?
const getBattleRole = (battle, userId) => {
  const uid = sid(userId);
  if (sid(battle.challengerCaptain) === uid) return 'challenger';
  if (sid(battle.opponentCaptain) === uid) return 'opponent';
  return null;
};

// ==================== @POST /api/battles/challenge ====================
// Captain kisi team ko battle ke liye challenge karta hai
// body: { opponentTeamId, venue?, area?, lat?, lng? }
router.post('/challenge', protect, wrap('Challenge', async (req, res) => {
  const { opponentTeamId, venue, area, lat, lng } = req.body;

  if (!opponentTeamId || !mongoose.isValidObjectId(opponentTeamId)) {
    return fail(res, 400, 'Invalid opponent team id');
  }

  // Meri team find karo
  const me = await User.findById(req.user._id).select('team');
  if (!me.team) return fail(res, 400, 'You must be in a team to challenge.');

  const myTeam = await Team.findById(me.team).select('captain name tag logo');
  if (!myTeam) return fail(res, 404, 'Your team not found.');
  if (!isCaptainOfTeam(myTeam, req.user._id)) {
    return fail(res, 403, 'Only the captain can send a challenge.');
  }

  if (sid(myTeam._id) === sid(opponentTeamId)) {
    return fail(res, 400, 'You cannot challenge your own team.');
  }

  const opponentTeam = await Team.findById(opponentTeamId).select('captain name tag logo members');
  if (!opponentTeam) return fail(res, 404, 'Opponent team not found.');

  // Existing pending/accepted/live challenge already hai?
  const existing = await Battle.findOne({
    $or: [
      { challengerTeam: myTeam._id, opponentTeam: opponentTeamId, status: { $in: ['pending', 'accepted', 'live'] } },
      { challengerTeam: opponentTeamId, opponentTeam: myTeam._id, status: { $in: ['pending', 'accepted', 'live'] } },
    ],
  });
  if (existing) {
    return fail(res, 409, 'A challenge between these teams is already active.');
  }

  const coords = (lat && lng) ? [parseFloat(lng), parseFloat(lat)] : [0, 0];

  const battle = await Battle.create({
    challengerTeam:    myTeam._id,
    opponentTeam:      opponentTeamId,
    challengerCaptain: req.user._id,
    venue: (venue || '').trim(),
    area:  (area  || '').trim(),
    location: { type: 'Point', coordinates: coords },
  });

  // Opponent captain ko notification
  await Notification.send(
    opponentTeam.captain,
    'battle_challenge',
    `${myTeam.name} challenged you!`,
    `${myTeam.name} has sent a kite battle challenge. Accept to start!`,
    'Battle',
    battle._id
  );

  res.status(201).json({
    success: true,
    message: `Challenge sent to ${opponentTeam.name}!`,
    battle: battleDetail(battle, req.user._id),
  });
}));

// ==================== @GET /api/battles/arena ====================
// Battle Arena screen - incoming challenges, outgoing challenges, ready opponents
// Captain hi dekh sakta hai
router.get('/arena', protect, wrap('Arena', async (req, res) => {
  const me = await User.findById(req.user._id).select('team');
  if (!me.team) {
    return res.status(200).json({ success: true, hasTeam: false, incoming: [], outgoing: [], readyOpponents: [] });
  }

  const myTeam = await Team.findById(me.team).select('captain name tag logo');
  if (!myTeam || !isCaptainOfTeam(myTeam, req.user._id)) {
    return res.status(200).json({ success: true, hasTeam: true, isCaptain: false, incoming: [], outgoing: [], readyOpponents: [] });
  }

  // Incoming = pending challenges where my team is opponent
  const incoming = await Battle.find({
    opponentTeam: myTeam._id,
    status: 'pending',
  }).populate('challengerTeam', 'name tag logo region members maxMembers')
    .populate('opponentTeam',   'name tag logo')
    .sort({ challengedAt: -1 });

  // Outgoing = pending challenges where my team is challenger
  const outgoing = await Battle.find({
    challengerTeam: myTeam._id,
    status: 'pending',
  }).populate('challengerTeam', 'name tag logo')
    .populate('opponentTeam',   'name tag logo region members maxMembers')
    .sort({ challengedAt: -1 });

  // Ready opponents = other public teams (excluding mine, excluding already challenged)
  const activeBattleTeamIds = [...incoming, ...outgoing].flatMap((b) => [
    sid(b.challengerTeam), sid(b.opponentTeam),
  ]);
  const readyOpponents = await Team.find({
    _id: { $ne: myTeam._id, $nin: activeBattleTeamIds },
    isPublic: true,
  }).select('name tag logo region city members maxMembers').limit(50);

  res.status(200).json({
    success: true,
    hasTeam: true,
    isCaptain: true,
    myTeam: { id: myTeam._id, name: myTeam.name, tag: myTeam.tag },
    incoming: incoming.map((b) => battleCard(b, myTeam._id)),
    outgoing: outgoing.map((b) => battleCard(b, myTeam._id)),
    readyOpponents: readyOpponents.map((t) => ({
      id: t._id,
      name: t.name,
      tag:  t.tag  || '',
      logo: t.logo || null,
      region: t.region || t.city || '',
      memberCount: t.members.length,
      maxMembers:  t.maxMembers || 10,
      status: 'ready',
    })),
  });
}));

// ==================== @GET /api/battles/my ====================
// Meri team ke sare battles (team page > Matches tab)
router.get('/my', protect, wrap('My battles', async (req, res) => {
  const me = await User.findById(req.user._id).select('team');
  if (!me.team) return res.status(200).json({ success: true, battles: [] });

  const q = String(req.query.status || '').trim();
  const filter = {
    $or: [{ challengerTeam: me.team }, { opponentTeam: me.team }],
  };
  if (q && ['pending','accepted','live','final','cancelled'].includes(q)) filter.status = q;

  const battles = await Battle.find(filter)
    .populate('challengerTeam', 'name tag logo')
    .populate('opponentTeam',   'name tag logo')
    .sort({ createdAt: -1 })
    .limit(50);

  res.status(200).json({
    success: true,
    battles: battles.map((b) => battleCard(b, me.team)),
  });
}));

// ==================== @GET /api/battles/nearby ====================
// Home "Matches near you" + Matches tab.
// ?city=Jaipur   -> area/venue mein city aaye (GPS na ho tab)
// ?lat=&lng=&radius=25000  -> GPS se (optional, distanceKm bhi milta hai)
// ?status=live|upcoming|final|all  ?q=search  ?page=1&limit=20
// Response mein counts {live, upcoming} bhi aate hain (same city/q filter par).
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const toRad = (d) => (d * Math.PI) / 180;
const haversineKm = (lat1, lng1, lat2, lng2) => {
  const a =
    Math.sin(toRad(lat2 - lat1) / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(toRad(lng2 - lng1) / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
};

router.get('/nearby', protect, wrap('Nearby battles', async (req, res) => {
  const lat    = parseFloat(req.query.lat);
  const lng    = parseFloat(req.query.lng);
  const hasGeo = Number.isFinite(lat) && Number.isFinite(lng);
  const radius = Math.min(50000, Math.max(1000, parseFloat(req.query.radius) || 25000)); // meters
  const status = String(req.query.status || 'all').trim();
  const page   = Math.max(1, parseInt(req.query.page, 10) || 1);
  const limit  = Math.min(30, Math.max(1, parseInt(req.query.limit, 10) || 20));
  const q      = String(req.query.q || '').trim().slice(0, 50);
  const city   = String(req.query.city || '').split(',')[0].trim().slice(0, 50);

  // Common filters (status ko chhodkar) - counts bhi inhi par
  const and = [];
  if (city) {
    const re = new RegExp(escapeRe(city), 'i');
    and.push({ $or: [{ area: re }, { venue: re }] });
  }
  if (q) {
    const re = new RegExp(escapeRe(q), 'i');
    const ids = (await Team.find({ $or: [{ name: re }, { tag: re }] }).select('_id').limit(50).lean()).map((t) => t._id);
    and.push({ $or: [{ venue: re }, { area: re }, { challengerTeam: { $in: ids } }, { opponentTeam: { $in: ids } }] });
  }
  if (hasGeo) {
    // $near countDocuments mein error deta hai, isliye $geoWithin
    and.push({ location: { $geoWithin: { $centerSphere: [[lng, lat], radius / 6378100] } } });
  }
  const base = and.length ? { $and: and } : {};

  let statusFilter;
  if (status === 'live')          statusFilter = 'live';
  else if (status === 'upcoming') statusFilter = { $in: ['pending', 'accepted'] };
  else if (status === 'final')    statusFilter = 'final';
  else                            statusFilter = { $in: ['live', 'pending', 'accepted', 'final'] };
  const filter = { ...base, status: statusFilter };

  const [battles, total, live, upcoming] = await Promise.all([
    Battle.find(filter)
      .populate('challengerTeam', 'name tag')
      .populate('opponentTeam',   'name tag')
      .sort({ challengedAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit),
    Battle.countDocuments(filter),
    Battle.countDocuments({ ...base, status: 'live' }),
    Battle.countDocuments({ ...base, status: { $in: ['pending', 'accepted'] } }),
  ]);

  const myTeamId = req.user.team || null;
  const rank = { live: 0, accepted: 1, pending: 2, final: 3 };

  const cards = battles
    .map((b) => {
      const c = b.location?.coordinates || [0, 0];
      const hasLoc = !(c[0] === 0 && c[1] === 0);
      return {
        ...battleCard(b, myTeamId),
        distanceKm: hasGeo && hasLoc ? Math.round(haversineKm(lat, lng, c[1], c[0]) * 10) / 10 : null,
      };
    })
    // Live pehle, phir upcoming, phir final (page ke andar)
    .sort((x, y) => (rank[x.status] ?? 9) - (rank[y.status] ?? 9));

  res.status(200).json({
    success: true,
    page,
    total,
    hasMore: page * limit < total,
    counts: { live, upcoming },
    battles: cards,
  });
}));

// ==================== @GET /api/battles/:id ====================
router.get('/:id', protect, wrap('Battle detail', async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return fail(res, 400, 'Invalid battle id');

  const battle = await Battle.findById(req.params.id)
    .populate('challengerTeam', 'name tag logo captain members')
    .populate('opponentTeam',   'name tag logo captain members')
    .populate('challengerCaptain', 'name')
    .populate('opponentCaptain',   'name')
    .populate('cutEvents.claimedBy', 'name')
    .populate('cutEvents.cutPlayer', 'name');

  if (!battle) return fail(res, 404, 'Battle not found.');

  res.status(200).json({ success: true, battle: battleDetail(battle, req.user._id) });
}));

// ==================== @POST /api/battles/:id/accept ====================
// Opponent captain challenge accept karta hai
router.post('/:id/accept', protect, wrap('Accept challenge', async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return fail(res, 400, 'Invalid battle id');

  const battle = await Battle.findById(req.params.id)
    .populate('opponentTeam', 'captain name')
    .populate('challengerTeam', 'name');

  if (!battle) return fail(res, 404, 'Battle not found.');
  if (battle.status !== 'pending') return fail(res, 400, 'This challenge is no longer pending.');

  const myTeam = battle.opponentTeam;
  if (!myTeam || !isCaptainOfTeam(myTeam, req.user._id)) {
    return fail(res, 403, 'Only the opponent captain can accept this challenge.');
  }

  battle.opponentCaptain = req.user._id;
  battle.status = 'accepted';
  battle.acceptedAt = new Date();
  await battle.save();

  // Challenger captain ko notification
  await Notification.send(
    battle.challengerCaptain,
    'battle_accepted',
    `${myTeam.name} accepted your challenge!`,
    `Both captains must now confirm to start the battle.`,
    'Battle',
    battle._id
  );

  res.status(200).json({
    success: true,
    message: 'Challenge accepted! Both captains must now start the battle.',
    battle: battleDetail(battle, req.user._id),
  });
}));

// ==================== @POST /api/battles/:id/cancel ====================
// Pending/accepted challenge cancel karo (challenger ya opponent captain)
router.post('/:id/cancel', protect, wrap('Cancel battle', async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return fail(res, 400, 'Invalid battle id');

  const battle = await Battle.findById(req.params.id)
    .populate('challengerTeam', 'captain name')
    .populate('opponentTeam',   'captain name');
  if (!battle) return fail(res, 404, 'Battle not found.');

  const uid = sid(req.user._id);
  const isChallCaptain = sid(battle.challengerCaptain) === uid;
  const isOppCaptain   = sid(battle.opponentCaptain)   === uid ||
                         (battle.status === 'pending' && isCaptainOfTeam(battle.opponentTeam, uid));

  if (!isChallCaptain && !isOppCaptain) {
    return fail(res, 403, 'Only a captain involved in this battle can cancel it.');
  }
  if (!['pending', 'accepted'].includes(battle.status)) {
    return fail(res, 400, 'Only pending or accepted battles can be cancelled.');
  }

  battle.status = 'cancelled';
  await battle.save();

  res.status(200).json({ success: true, message: 'Battle cancelled.' });
}));

// ==================== @POST /api/battles/:id/ready ====================
// Captain "Accept & start battle" dabata hai (dono ready = live)
// Pehle challenger, fir opponent (ya ulta) - dono ready hone par status = live
router.post('/:id/ready', protect, wrap('Ready/Start battle', async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return fail(res, 400, 'Invalid battle id');

  const battle = await Battle.findById(req.params.id)
    .populate('challengerTeam', 'captain name members')
    .populate('opponentTeam',   'captain name members');
  if (!battle) return fail(res, 404, 'Battle not found.');
  if (battle.status !== 'accepted') {
    return fail(res, 400, 'Battle must be accepted before starting.');
  }

  const role = getBattleRole(battle, req.user._id);
  if (!role) return fail(res, 403, 'Only a battle captain can start the battle.');

  if (role === 'challenger') battle.challengerReady = true;
  else                        battle.opponentReady   = true;

  // Dono ready hone par live
  if (battle.challengerReady && battle.opponentReady) {
    battle.status    = 'live';
    battle.startedAt = new Date();

    // Dono teams ke sare members ko notification
    const allMemberIds = [
      ...(battle.challengerTeam.members || []),
      ...(battle.opponentTeam.members   || []),
    ].map((m) => sid(m));

    await Notification.broadcast(
      allMemberIds,
      'battle_started',
      'Battle is LIVE! 🪁',
      `${battle.challengerTeam.name} vs ${battle.opponentTeam.name} has started!`,
      'Battle',
      battle._id
    );
  }

  await battle.save();

  const bothReady = battle.challengerReady && battle.opponentReady;
  res.status(200).json({
    success: true,
    message: bothReady ? 'Battle is now LIVE!' : 'You are ready. Waiting for the other captain.',
    isLive: battle.status === 'live',
    battle: battleDetail(battle, req.user._id),
  });
}));

// ==================== @POST /api/battles/:id/claim-cut ====================
// Captain apni team ki kite cut claim karta hai (+100 score request)
// body: { cutPlayerId? } - optional: konse player ne kiya
router.post('/:id/claim-cut', protect, wrap('Claim cut', async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return fail(res, 400, 'Invalid battle id');

  const battle = await Battle.findById(req.params.id);
  if (!battle) return fail(res, 404, 'Battle not found.');
  if (battle.status !== 'live') return fail(res, 400, 'Battle is not live.');

  const role = getBattleRole(battle, req.user._id);
  if (!role) return fail(res, 403, 'Only a battle captain can claim a cut.');

  const myTeamId = role === 'challenger' ? battle.challengerTeam : battle.opponentTeam;
  const { cutPlayerId } = req.body;

  const cutEvent = {
    claimedBy:     req.user._id,
    claimedByTeam: myTeamId,
    cutPlayer:     (cutPlayerId && mongoose.isValidObjectId(cutPlayerId)) ? cutPlayerId : null,
    status:        'pending',
  };

  battle.cutEvents.push(cutEvent);
  await battle.save();

  const newCut = battle.cutEvents[battle.cutEvents.length - 1];

  // Opponent captain ko notification
  const oppCaptainId = role === 'challenger' ? battle.opponentCaptain : battle.challengerCaptain;
  if (oppCaptainId) {
    await Notification.send(
      oppCaptainId,
      'cut_claimed',
      'Kite Cut Claimed! ✂️',
      'Opponent claims a kite cut. Approve or reject it.',
      'Battle',
      battle._id
    );
  }

  res.status(201).json({
    success: true,
    message: 'Cut claimed! Waiting for opponent captain to approve.',
    cut: {
      id:            newCut._id,
      claimedByTeam: myTeamId,
      status:        'pending',
      createdAt:     newCut.createdAt,
    },
  });
}));

// ==================== @POST /api/battles/:id/cuts/:cutId/respond ====================
// Opponent captain cut approve ya reject karta hai
// body: { action: 'approve' | 'reject', reason?: string }
router.post('/:id/cuts/:cutId/respond', protect, wrap('Respond cut', async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id))    return fail(res, 400, 'Invalid battle id');
  if (!mongoose.isValidObjectId(req.params.cutId)) return fail(res, 400, 'Invalid cut id');

  const { action, reason } = req.body;
  if (!['approve', 'reject'].includes(action)) {
    return fail(res, 400, 'Action must be "approve" or "reject"');
  }

  const battle = await Battle.findById(req.params.id);
  if (!battle) return fail(res, 404, 'Battle not found.');
  if (battle.status !== 'live') return fail(res, 400, 'Battle is not live.');

  const cut = battle.cutEvents.id(req.params.cutId);
  if (!cut) return fail(res, 404, 'Cut event not found.');
  if (cut.status !== 'pending') return fail(res, 400, 'This cut has already been resolved.');

  // Sirf opponent ki side ka captain respond kar sakta hai
  const claimerRole = sid(cut.claimedByTeam) === sid(battle.challengerTeam) ? 'challenger' : 'opponent';
  const responderRole = claimerRole === 'challenger' ? 'opponent' : 'challenger';
  const myRole = getBattleRole(battle, req.user._id);
  if (myRole !== responderRole) {
    return fail(res, 403, 'Only the opposing captain can respond to this cut.');
  }

  cut.status      = action === 'approve' ? 'approved' : 'rejected';
  cut.resolvedAt  = new Date();
  cut.rejectionReason = action === 'reject' ? (reason || '').trim() : '';

  // Score update on approve
  if (action === 'approve') {
    if (claimerRole === 'challenger') battle.challengerCuts += 1;
    else                               battle.opponentCuts   += 1;
  }

  await battle.save();

  // Claimant captain ko notification
  const claimantCaptainId = claimerRole === 'challenger' ? battle.challengerCaptain : battle.opponentCaptain;
  const notifType = action === 'approve' ? 'cut_approved' : 'cut_rejected';
  await Notification.send(
    claimantCaptainId,
    notifType,
    action === 'approve' ? 'Cut Approved! +100 ✅' : 'Cut Rejected ❌',
    action === 'approve' ? 'Your kite cut was approved!' : `Cut rejected: ${cut.rejectionReason || 'No reason given'}`,
    'Battle',
    battle._id
  );

  res.status(200).json({
    success: true,
    message: action === 'approve' ? 'Cut approved! Score updated.' : 'Cut rejected.',
    challengerCuts: battle.challengerCuts,
    opponentCuts:   battle.opponentCuts,
    cut: { id: cut._id, status: cut.status, rejectionReason: cut.rejectionReason },
  });
}));

// ==================== @POST /api/battles/:id/end ====================
// Captain battle end karta hai
// Winner auto-decide: jis side ke cuts zyada us ka win, equal = tie
router.post('/:id/end', protect, wrap('End battle', async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return fail(res, 400, 'Invalid battle id');

  const battle = await Battle.findById(req.params.id)
    .populate('challengerTeam', 'name')
    .populate('opponentTeam',   'name');
  if (!battle) return fail(res, 404, 'Battle not found.');
  if (battle.status !== 'live') return fail(res, 400, 'Battle is not live.');

  const role = getBattleRole(battle, req.user._id);
  if (!role) return fail(res, 403, 'Only a battle captain can end the battle.');

  // Winner decide karo
  let winner = 'tie';
  if (battle.challengerCuts > battle.opponentCuts) winner = 'challenger';
  else if (battle.opponentCuts > battle.challengerCuts) winner = 'opponent';

  battle.status  = 'final';
  battle.winner  = winner;
  battle.endedAt = new Date();
  await battle.save();

  // Team stats update karo
  const challResult = winner === 'challenger' ? 'W' : winner === 'tie' ? 'T' : 'L';
  const oppResult   = winner === 'opponent'   ? 'W' : winner === 'tie' ? 'T' : 'L';

  // playerCuts object banao (pending cuts ignore, sirf approved)
  const approvedCuts = battle.cutEvents.filter((c) => c.status === 'approved');
  const challPlayerCuts = {};
  const oppPlayerCuts   = {};
  for (const c of approvedCuts) {
    if (sid(c.claimedByTeam) === sid(battle.challengerTeam._id)) {
      if (c.cutPlayer) {
        challPlayerCuts[sid(c.cutPlayer)] = (challPlayerCuts[sid(c.cutPlayer)] || 0) + 1;
      }
    } else {
      if (c.cutPlayer) {
        oppPlayerCuts[sid(c.cutPlayer)] = (oppPlayerCuts[sid(c.cutPlayer)] || 0) + 1;
      }
    }
  }

  await Promise.all([
    Team.recordResult(battle.challengerTeam._id, {
      result: challResult,
      cutsScored:    battle.challengerCuts,
      cutsConceded:  battle.opponentCuts,
      playerCuts:    challPlayerCuts,
    }),
    Team.recordResult(battle.opponentTeam._id, {
      result: oppResult,
      cutsScored:    battle.opponentCuts,
      cutsConceded:  battle.challengerCuts,
      playerCuts:    oppPlayerCuts,
    }),
  ]);

  // User stats update (matches + wins)
  const challCaptainUpdate = { $inc: { 'stats.matches': 1 } };
  const oppCaptainUpdate   = { $inc: { 'stats.matches': 1 } };
  if (challResult === 'W') challCaptainUpdate['$inc']['stats.wins'] = 1;
  if (oppResult   === 'W') oppCaptainUpdate['$inc']['stats.wins']   = 1;

  await Promise.all([
    User.updateMany({ team: battle.challengerTeam._id }, { $inc: { 'stats.matches': 1, ...(challResult === 'W' ? { 'stats.wins': 1 } : {}) } }),
    User.updateMany({ team: battle.opponentTeam._id   }, { $inc: { 'stats.matches': 1, ...(oppResult   === 'W' ? { 'stats.wins': 1 } : {}) } }),
  ]);

  // Dono teams ke members ko notification
  const [challTeamFull, oppTeamFull] = await Promise.all([
    Team.findById(battle.challengerTeam._id).select('members'),
    Team.findById(battle.opponentTeam._id).select('members'),
  ]);
  const allMemberIds = [
    ...(challTeamFull?.members || []),
    ...(oppTeamFull?.members   || []),
  ].map(sid);

  const winnerName = winner === 'challenger' ? battle.challengerTeam.name
                   : winner === 'opponent'   ? battle.opponentTeam.name
                   : null;
  const notifBody = winner === 'tie'
    ? `${battle.challengerTeam.name} vs ${battle.opponentTeam.name} ended in a TIE!`
    : `${winnerName} won the battle! 🪁`;

  await Notification.broadcast(allMemberIds, 'battle_ended', 'Battle Ended!', notifBody, 'Battle', battle._id);

  res.status(200).json({
    success: true,
    message: winner === 'tie' ? "It's a tie!" : `${winnerName} wins!`,
    winner,
    challengerCuts: battle.challengerCuts,
    opponentCuts:   battle.opponentCuts,
  });
}));

module.exports = router;
