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

// Minimum number of players required in each team to start a match.
// Currently 1 for testing. Once every team has 5 people, set MIN_PLAYERS_TO_START=5 in the Render env.
const MIN_PLAYERS = Math.max(1, parseInt(process.env.MIN_PLAYERS_TO_START || '1', 10) || 1);

const person = (u) => ({ id: sid(u), name: u && u.name ? u.name : '' });

// Team members (only when populated, with names)
const rosterOf = (t) =>
  ((t && t.members) || [])
    .filter((m) => m && typeof m === 'object' && m.name)
    .map((m) => ({ id: m._id, name: m.name }));

// W-L of every player from approved bouts (live player board)
const playerBoardOf = (b) => {
  const board = {};
  const touch = (u, team) => {
    const k = sid(u);
    if (!board[k]) board[k] = { id: k, name: (u && u.name) || '', team, wins: 0, losses: 0 };
    return board[k];
  };
  for (const c of b.cutEvents || []) {
    if (c.status !== 'approved') continue;
    const winTeam  = sid(c.claimedByTeam) === sid(b.challengerTeam) ? 'challenger' : 'opponent';
    const loseTeam = winTeam === 'challenger' ? 'opponent' : 'challenger';
    (c.winners || []).forEach((u) => { touch(u, winTeam).wins += 1; });
    (c.losers  || []).forEach((u) => { touch(u, loseTeam).losses += 1; });
  }
  return Object.values(board).sort((a, z) => z.wins - a.wins || a.losses - z.losses);
};

// Battle summary object (for the list card)
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
    scheduledAt:  b.scheduledAt || null,
    // Convenience: best time to display (scheduled > ended > started > challenged)
    when: b.scheduledAt || b.endedAt || b.startedAt || b.challengedAt,
  };
};

// Battle detailed object (for the Battle screen)
const battleDetail = (b, userId) => {
  const uid = sid(userId);
  const challTeam = b.challengerTeam || {};
  const oppTeam   = b.opponentTeam   || {};
  // Captain role: only captains can perform battle actions (accept/ready/cut/end).
  // opponentCaptain is set after accepting; until then the captain of the opponent team is the opponent.
  let myCaptainRole = null;
  if (sid(b.challengerCaptain) === uid) myCaptainRole = 'challenger';
  else if (sid(b.opponentCaptain) === uid || (oppTeam.captain && sid(oppTeam.captain) === uid)) myCaptainRole = 'opponent';
  const isChallenger = myCaptainRole === 'challenger';
  const myRole = myCaptainRole || 'viewer';
  return {
    ...battleCard(b, isChallenger ? b.challengerTeam : b.opponentTeam),
    myRole,
    myCaptainRole,
    canAccept: b.status === 'pending' && myCaptainRole === 'opponent',
    canCancel: ['pending', 'accepted'].includes(b.status) && !!myCaptainRole,
    iAmReady:  myCaptainRole === 'challenger' ? !!b.challengerReady : myCaptainRole === 'opponent' ? !!b.opponentReady : false,
    challengerCaptain: b.challengerCaptain,
    opponentCaptain:   b.opponentCaptain,
    challengerReady:   b.challengerReady,
    opponentReady:     b.opponentReady,
    cutEvents: (b.cutEvents || []).map((c) => ({
      id: c._id,
      claimedBy:     c.claimedBy,
      claimedByTeam: c.claimedByTeam,
      cutPlayer:     c.cutPlayer || null,
      winners:       (c.winners || []).map(person),
      losers:        (c.losers  || []).map(person),
      status:        c.status,
      rejectionReason: c.rejectionReason || '',
      createdAt:     c.createdAt,
      resolvedAt:    c.resolvedAt || null,
    })),
    rosters: { challenger: rosterOf(challTeam), opponent: rosterOf(oppTeam) },
    playerBoard: playerBoardOf(b),
    minPlayers: MIN_PLAYERS,
    startedAt:    b.startedAt,
    endedAt:      b.endedAt,
    challengedAt: b.challengedAt,
    acceptedAt:   b.acceptedAt,
  };
};

// Is the user the captain of their team?
const isCaptainOfTeam = (team, userId) => sid(team.captain) === sid(userId);

// Is the user a participant of this battle (from the captain side)?
const getBattleRole = (battle, userId) => {
  const uid = sid(userId);
  if (sid(battle.challengerCaptain) === uid) return 'challenger';
  if (sid(battle.opponentCaptain) === uid) return 'opponent';
  return null;
};

// ==================== @POST /api/battles/challenge ====================
// A captain challenges a team to a battle
// body: { opponentTeamId, venue?, area?, lat?, lng? }
router.post('/challenge', protect, wrap('Challenge', async (req, res) => {
  const { opponentTeamId, venue, area, lat, lng, scheduledAt } = req.body;

  if (!opponentTeamId || !mongoose.isValidObjectId(opponentTeamId)) {
    return fail(res, 400, 'Invalid opponent team id');
  }

  // Find my team
  const me = await User.findById(req.user._id).select('team');
  if (!me.team) return fail(res, 400, 'You must be in a team to challenge.');

  const myTeam = await Team.findById(me.team).select('captain name tag logo region city');
  if (!myTeam) return fail(res, 404, 'Your team not found.');
  if (!isCaptainOfTeam(myTeam, req.user._id)) {
    return fail(res, 403, 'Only the captain can send a challenge.');
  }

  if (sid(myTeam._id) === sid(opponentTeamId)) {
    return fail(res, 400, 'You cannot challenge your own team.');
  }

  const opponentTeam = await Team.findById(opponentTeamId).select('captain name tag logo members');
  if (!opponentTeam) return fail(res, 404, 'Opponent team not found.');

  // Is there already an existing pending/accepted/live challenge?
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
    venue: (venue || '').trim().slice(0, 100),
    // If no area is given, use the team's city/region so the match shows up in "Near me"
    area:  ((area || '').trim() || myTeam.region || myTeam.city || '').slice(0, 100),
    location: { type: 'Point', coordinates: coords },
    scheduledAt: scheduledAt ? new Date(scheduledAt) : null,
  });

  // Notification to the opponent captain
  await Notification.send(
    opponentTeam.captain,
    'battle_challenge',
    `${myTeam.name} challenged you! 🪁`,
    `${myTeam.name} has sent you a kite battle challenge.` +
      (battle.venue ? ` Venue: ${battle.venue}.` : '') +
      (battle.scheduledAt
        ? ` Time: ${new Date(battle.scheduledAt).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Kolkata' })}.`
        : '') +
      ' Accept or decline.',
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
// Only the captain can view this
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

  // Active = accepted (waiting to start) or live battles that include my team
  const active = await Battle.find({
    $or: [{ challengerTeam: myTeam._id }, { opponentTeam: myTeam._id }],
    status: { $in: ['accepted', 'live'] },
  }).populate('challengerTeam', 'name tag logo')
    .populate('opponentTeam',   'name tag logo')
    .sort({ updatedAt: -1 })
    .limit(20);

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
    active:   active.map((b) => battleCard(b, myTeam._id)),
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
// All battles of my team (team page > Matches tab)
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
// ?city=Jaipur   -> city appears in area/venue (when there is no GPS)
// ?lat=&lng=&radius=25000  -> by GPS (optional, distanceKm is also returned)
// ?status=live|upcoming|final|all  ?q=search  ?page=1&limit=20
// The response also includes counts {live, upcoming} (for the same city/q filter).
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

  // Common filters (except status) - the counts also use these
  const and = [];
  if (city) {
    const re = new RegExp(escapeRe(city), 'i');
    // The city is in the match area/venue, or the region/city of either team is the same
    const cityTeamIds = (await Team.find({ $or: [{ region: re }, { city: re }] }).select('_id').limit(500).lean()).map((t) => t._id);
    and.push({ $or: [{ area: re }, { venue: re }, { challengerTeam: { $in: cityTeamIds } }, { opponentTeam: { $in: cityTeamIds } }] });
  }
  if (q) {
    const re = new RegExp(escapeRe(q), 'i');
    const ids = (await Team.find({ $or: [{ name: re }, { tag: re }] }).select('_id').limit(50).lean()).map((t) => t._id);
    and.push({ $or: [{ venue: re }, { area: re }, { challengerTeam: { $in: ids } }, { opponentTeam: { $in: ids } }] });
  }
  if (hasGeo) {
    // $near throws an error in countDocuments, hence $geoWithin
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
      .populate('challengerTeam', 'name tag logo')
      .populate('opponentTeam',   'name tag logo')
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
    // Live first, then upcoming, then final (within the page)
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
    .populate({ path: 'challengerTeam', select: 'name tag logo captain members', populate: { path: 'members', select: 'name' } })
    .populate({ path: 'opponentTeam',   select: 'name tag logo captain members', populate: { path: 'members', select: 'name' } })
    .populate('challengerCaptain', 'name')
    .populate('opponentCaptain',   'name')
    .populate('cutEvents.claimedBy', 'name')
    .populate('cutEvents.cutPlayer', 'name')
    .populate('cutEvents.winners', 'name')
    .populate('cutEvents.losers', 'name');

  if (!battle) return fail(res, 404, 'Battle not found.');

  res.status(200).json({ success: true, battle: battleDetail(battle, req.user._id) });
}));

// ==================== @POST /api/battles/:id/accept ====================
// The opponent captain accepts the challenge
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

  // Notification to the challenger captain - include the schedule info too
  const schedText = battle.scheduledAt
    ? ` Match schedule: ${new Date(battle.scheduledAt).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' })}.`
    : '';
  await Notification.send(
    battle.challengerCaptain,
    'battle_accepted',
    `${myTeam.name} accepted the challenge! 🎉`,
    `Both captains now need to press "Start Battle" and the match will go LIVE.${schedText}`,
    'Battle',
    battle._id
  );

  res.status(200).json({
    success: true,
    message: `Challenge accepted! The match will begin once both captains press "Start Battle".`,
    battle: battleDetail(battle, req.user._id),
  });
}));

// ==================== @POST /api/battles/:id/reject ====================
// The opponent captain rejects the challenge (while pending)
// A notification goes to the challenger captain
router.post('/:id/reject', protect, wrap('Reject challenge', async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return fail(res, 400, 'Invalid battle id');

  const battle = await Battle.findById(req.params.id)
    .populate('challengerTeam', 'captain name')
    .populate('opponentTeam',   'captain name');
  if (!battle) return fail(res, 404, 'Battle not found.');
  if (battle.status !== 'pending') {
    return fail(res, 400, 'Only pending challenges can be rejected.');
  }

  const uid = sid(req.user._id);
  // Only the captain of the opponent team can reject
  const isOppCaptain = isCaptainOfTeam(battle.opponentTeam, uid);
  if (!isOppCaptain) {
    return fail(res, 403, 'Only the opponent captain can reject this challenge.');
  }

  const { reason = '' } = req.body;
  battle.status = 'cancelled';
  battle.opponentCaptain = req.user._id; // record who rejected
  await battle.save();

  // Rejection notification to the challenger captain
  const oppName = battle.opponentTeam.name || 'Opponent';
  const reasonText = reason.trim() ? ` Reason: ${reason.trim()}` : '';
  await Notification.send(
    battle.challengerCaptain,
    'battle_rejected',
    `${oppName} rejected your challenge`,
    `${oppName} declined your battle challenge.${reasonText}`,
    'Battle',
    battle._id
  );

  res.status(200).json({
    success: true,
    message: `Challenge rejected. ${battle.challengerTeam.name} has been notified.`,
  });
}));

// ==================== @POST /api/battles/:id/cancel ====================
// Cancel a pending/accepted challenge (challenger or opponent captain)
// Note: For opponent "Decline" use /reject. Cancel = withdrawing from your own side.
router.post('/:id/cancel', protect, wrap('Cancel battle', async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return fail(res, 400, 'Invalid battle id');

  const battle = await Battle.findById(req.params.id)
    .populate('challengerTeam', 'captain name')
    .populate('opponentTeam',   'captain name');
  if (!battle) return fail(res, 404, 'Battle not found.');

  const uid = sid(req.user._id);
  const isChallCaptain = sid(battle.challengerCaptain) === uid;
  const isOppCaptain   = sid(battle.opponentCaptain)   === uid;

  if (!isChallCaptain && !isOppCaptain) {
    return fail(res, 403, 'Only a captain involved in this battle can cancel it.');
  }
  if (!['pending', 'accepted'].includes(battle.status)) {
    return fail(res, 400, 'Only pending or accepted battles can be cancelled.');
  }

  battle.status = 'cancelled';
  await battle.save();

  // Cancel notification to the other side
  const myName = isChallCaptain
    ? (battle.challengerTeam.name || 'Challenger')
    : (battle.opponentTeam.name   || 'Opponent');
  const notifyUser = isChallCaptain ? battle.opponentCaptain : battle.challengerCaptain;

  if (notifyUser) {
    await Notification.send(
      notifyUser,
      'battle_cancelled',
      `${myName} cancelled the battle`,
      `${myName} has cancelled the upcoming battle.`,
      'Battle',
      battle._id
    );
  }

  res.status(200).json({ success: true, message: 'Battle cancelled.' });
}));

// ==================== @POST /api/battles/:id/ready ====================
// The captain presses "Accept & start battle" (both ready = live)
// First the challenger, then the opponent (or vice versa) - status = live once both are ready
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

  const chCount = (battle.challengerTeam.members || []).length;
  const opCount = (battle.opponentTeam.members   || []).length;
  if (chCount < MIN_PLAYERS || opCount < MIN_PLAYERS) {
    return fail(
      res, 400,
      `At least ${MIN_PLAYERS} players are required in both teams to start the match ` +
      `(${battle.challengerTeam.name}: ${chCount}, ${battle.opponentTeam.name}: ${opCount}).`
    );
  }

  if (role === 'challenger') battle.challengerReady = true;
  else                        battle.opponentReady   = true;

  // Live once both are ready
  if (battle.challengerReady && battle.opponentReady) {
    battle.status    = 'live';
    battle.startedAt = new Date();

    // Notification to all members of both teams
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
// The captain claims a kite cut for their team (+100 score request)
// body: { cutPlayerId? } - optional: which player made the cut
router.post('/:id/claim-cut', protect, wrap('Claim cut', async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return fail(res, 400, 'Invalid battle id');

  const battle = await Battle.findById(req.params.id)
    .populate('challengerTeam', 'members name')
    .populate('opponentTeam',   'members name');
  if (!battle) return fail(res, 404, 'Battle not found.');
  if (battle.status !== 'live') return fail(res, 400, 'Battle is not live.');

  const role = getBattleRole(battle, req.user._id);
  if (!role) return fail(res, 403, 'Only a battle captain can claim a cut.');

  const myTeam  = role === 'challenger' ? battle.challengerTeam : battle.opponentTeam;
  const oppTeam = role === 'challenger' ? battle.opponentTeam   : battle.challengerTeam;

  // Bout: winnerPlayerIds = players of our team who won, loserPlayerIds = players of the opposing team who lost.
  // The old client only sent cutPlayerId, let that work too (treat it as the winner).
  const asIds = (v) => [...new Set((Array.isArray(v) ? v : []).map(String))];
  let winnerIds = asIds(req.body.winnerPlayerIds);
  const loserIds = asIds(req.body.loserPlayerIds);
  const legacy = req.body.cutPlayerId;
  if (!winnerIds.length && legacy && mongoose.isValidObjectId(legacy)) winnerIds = [String(legacy)];

  if (!winnerIds.length || !loserIds.length) {
    return fail(res, 400, 'Select at least one winning player (from your team) and one losing player (from the opposing team).');
  }
  const myMembers  = new Set((myTeam.members  || []).map(sid));
  const oppMembers = new Set((oppTeam.members || []).map(sid));
  if (!winnerIds.every((id) => mongoose.isValidObjectId(id) && myMembers.has(id))) {
    return fail(res, 400, 'Winning players must be members of your own team.');
  }
  if (!loserIds.every((id) => mongoose.isValidObjectId(id) && oppMembers.has(id))) {
    return fail(res, 400, 'Losing players must be members of the opposing team.');
  }

  battle.cutEvents.push({
    claimedBy:     req.user._id,
    claimedByTeam: myTeam._id,
    cutPlayer:     winnerIds[0],
    winners:       winnerIds,
    losers:        loserIds,
    status:        'pending',
  });
  await battle.save();

  const newCut = battle.cutEvents[battle.cutEvents.length - 1];

  // To show names in the notification
  const named = await User.find({ _id: { $in: [...winnerIds, ...loserIds] } }).select('name').lean();
  const nameOf = Object.fromEntries(named.map((u) => [String(u._id), u.name]));
  const join = (ids) => ids.map((i) => nameOf[i] || 'Player').join(', ');

  // Notification to the opponent captain
  const oppCaptainId = role === 'challenger' ? battle.opponentCaptain : battle.challengerCaptain;
  if (oppCaptainId) {
    await Notification.send(
      oppCaptainId,
      'cut_claimed',
      'Kite Cut Claimed! ✂️',
      `${myTeam.name}: ${join(winnerIds)} defeated ${join(loserIds)}. Approve or reject.`,
      'Battle',
      battle._id
    );
  }

  res.status(201).json({
    success: true,
    message: 'Cut claimed! Waiting for opponent captain to approve.',
    cut: {
      id:            newCut._id,
      claimedByTeam: myTeam._id,
      status:        'pending',
      createdAt:     newCut.createdAt,
    },
  });
}));

// ==================== @POST /api/battles/:id/cuts/:cutId/respond ====================
// The opponent captain approves or rejects the cut
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

  // Only the captain of the opponent side can respond
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

  // Notification to the claimant captain
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
// The captain ends the battle
// Winner is decided automatically: the side with more cuts wins, equal = tie
router.post('/:id/end', protect, wrap('End battle', async (req, res) => {
  if (!mongoose.isValidObjectId(req.params.id)) return fail(res, 400, 'Invalid battle id');

  const battle = await Battle.findById(req.params.id)
    .populate('challengerTeam', 'name')
    .populate('opponentTeam',   'name');
  if (!battle) return fail(res, 404, 'Battle not found.');
  if (battle.status !== 'live') return fail(res, 400, 'Battle is not live.');

  const role = getBattleRole(battle, req.user._id);
  if (!role) return fail(res, 403, 'Only a battle captain can end the battle.');

  // Decide the winner
  let winner = 'tie';
  if (battle.challengerCuts > battle.opponentCuts) winner = 'challenger';
  else if (battle.opponentCuts > battle.challengerCuts) winner = 'opponent';

  battle.status  = 'final';
  battle.winner  = winner;
  battle.endedAt = new Date();
  await battle.save();

  // Update team stats
  const challResult = winner === 'challenger' ? 'W' : winner === 'tie' ? 'T' : 'L';
  const oppResult   = winner === 'opponent'   ? 'W' : winner === 'tie' ? 'T' : 'L';

  // Build the playerCuts object (ignore pending cuts, only approved).
  // Winning player gets +1 cut, losing player gets 0 (but their matchesPlayed increases).
  const approvedCuts = battle.cutEvents.filter((c) => c.status === 'approved');
  const challPlayerCuts = {};
  const oppPlayerCuts   = {};
  for (const c of approvedCuts) {
    const winnerIsChall = sid(c.claimedByTeam) === sid(battle.challengerTeam._id);
    const winMap  = winnerIsChall ? challPlayerCuts : oppPlayerCuts;
    const loseMap = winnerIsChall ? oppPlayerCuts   : challPlayerCuts;
    const winners = (c.winners && c.winners.length) ? c.winners : (c.cutPlayer ? [c.cutPlayer] : []);
    for (const w of winners) winMap[sid(w)] = (winMap[sid(w)] || 0) + 1;
    for (const l of (c.losers || [])) loseMap[sid(l)] = loseMap[sid(l)] || 0;
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

  // Notification to the members of both teams
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
