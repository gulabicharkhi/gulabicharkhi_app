const express = require('express');
const mongoose = require('mongoose');
const Team = require('../models/Team');
const User = require('../models/User');
const Battle = require('../models/Battle');
const { protect } = require('../middleware/authMiddleware');

const router = express.Router();

const DEFAULT_MAX = Team.DEFAULT_MAX_MEMBERS;
const MIN_LIMIT = 4;
const MAX_LIMIT = 20;

// true  = public team par "Join" dabane se captain ko request jati hai (screen: "find and request to join")
// false = public team par Join turant ho jata hai
// Invite code / QR se join hamesha turant hota hai.
const PUBLIC_JOIN_NEEDS_APPROVAL = true;

// APP_INVITE_BASE_URL = Flutter deep link (e.g. gulabicharkhi://join)
// WEB_INVITE_BASE_URL = web fallback (e.g. https://api.yourdomain.com/join)
// Agar kuch set nahi = backend server ka own /join/CODE endpoint use karo
const INVITE_BASE = (
  process.env.APP_INVITE_BASE_URL ||
  process.env.WEB_INVITE_BASE_URL ||
  `http://localhost:${process.env.PORT || 5000}/join`
).replace(/\/$/, '');

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
const maxOf = (t) => t.maxMembers || DEFAULT_MAX;
const isCaptainOf = (t, uid) => sid(t.captain) === sid(uid);
const isMemberOf = (t, uid) => t.members.some((m) => sid(m) === sid(uid));
const hasRequested = (t, uid) => (t.joinRequests || []).some((r) => sid(r.user) === sid(uid));
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// Purani teams (tag nahi) ke liye name se tag
const tagOf = (t) =>
  t.tag || String(t.name || '').replace(/[^a-zA-Z0-9]/g, '').slice(0, 3).toUpperCase();

const inviteLinkOf = (t) => `${INVITE_BASE}/${t.inviteCode}`;

// List / card ke liye chhota object (invite code yahan KABHI nahi - private team ka code leak hota tha)
const teamCard = (t, viewerId) => ({
  id: t._id,
  name: t.name,
  tag: tagOf(t),
  region: t.region || t.city || '',
  city: t.region || t.city || '', // purane client ke liye
  about: t.about || '',
  logo: t.logo || null,
  isPublic: t.isPublic,
  memberCount: t.members.length,
  maxMembers: maxOf(t),
  status: t.members.length >= maxOf(t) ? 'full' : 'ready',
  isMember: viewerId ? isMemberOf(t, viewerId) : false,
  isCaptain: viewerId ? isCaptainOf(t, viewerId) : false,
  requested: viewerId ? hasRequested(t, viewerId) : false,
});

const memberView = (u, t) => {
  const ps = (t.playerStats || []).find((p) => sid(p.user) === sid(u));
  return {
    id: u._id,
    name: u.name,
    city: u.city || '',
    profilePhoto: u.profilePhoto || null,
    isCaptain: isCaptainOf(t, u),
    matchesPlayed: ps ? ps.matchesPlayed : 0,
    cuts: ps ? ps.cuts : 0,
  };
};

// Team page (Members / Scoreboard / Invite tabs) ka poora data. t.members populated hona chahiye.
const teamDetail = (t, viewerId) => {
  const member = isMemberOf(t, viewerId);
  const captain = isCaptainOf(t, viewerId);
  const s = t.stats || {};
  const played = s.played || 0;
  const form = (s.recentForm || []).slice(-5);
  const out = {
    ...teamCard(t, viewerId),
    coverImage: t.coverImage || null,
    captainId: sid(t.captain),
    createdAt: t.createdAt,
    members: t.members.map((u) => memberView(u, t)),
  };
  // Scoreboard public hai (private team ko non-member ka route hi rok deta hai)
  out.scoreboard = {
    played,
    wins: s.wins || 0,
    losses: s.losses || 0,
    ties: s.ties || 0,
    winRate: played ? Math.round(((s.wins || 0) / played) * 100) : 0,
    cutsScored: s.cutsScored || 0,
    cutsConceded: s.cutsConceded || 0,
    recentForm: [...Array(5 - form.length).fill(null), ...form], // null = "—"
  };
  // Invite code / link sirf members ko
  if (member) {
    out.inviteCode = t.inviteCode;
    out.inviteLink = inviteLinkOf(t);
    out.qrData = inviteLinkOf(t); // app is string ka QR banayega
  }
  if (captain) out.pendingRequests = (t.joinRequests || []).length;
  return out;
};

const loadDetail = (id) => Team.findById(id).populate('members', 'name city profilePhoto');

const validImageUrl = (v, maxLen) => {
  if (v === null || v === '') return { value: null };
  if (typeof v !== 'string') return { error: 'Invalid image' };
  if (/^https?:\/\//i.test(v) && v.length <= 500) return { value: v };
  if (/^data:image\/(png|jpe?g|webp);base64,/i.test(v) && v.length <= maxLen) return { value: v };
  return { error: 'Image must be a link or a small png/jpg/webp (logo up to ~200KB, cover up to ~600KB)' };
};

// Create (full) ya edit (partial) ki body validate karo
const parseTeamInput = (body, partial = false) => {
  const out = {};
  const has = (k) => body[k] !== undefined;

  if (!partial || has('name')) {
    const name = String(body.name || '').trim();
    if (name.length < 3 || name.length > 30) return { error: 'Team name must be 3 to 30 characters' };
    out.name = name;
  }
  if (!partial || has('tag')) {
    const tag = String(body.tag || '').replace(/\s+/g, '').toUpperCase();
    if (!/^[A-Z0-9]{2,4}$/.test(tag)) return { error: 'Tag must be 2 to 4 letters or numbers' };
    out.tag = tag;
  }
  if (!partial || has('region')) {
    const region = String(body.region ?? body.city ?? '').trim();
    if (region.length < 2 || region.length > 60) return { error: 'Enter your region / area' };
    out.region = region;
  }
  if (has('about')) {
    const about = String(body.about || '').trim();
    if (about.length > 200) return { error: 'About cannot exceed 200 characters' };
    out.about = about;
  }
  if (has('maxMembers')) {
    const n = Number(body.maxMembers);
    if (!Number.isInteger(n) || n < MIN_LIMIT || n > MAX_LIMIT) {
      return { error: `Max members must be between ${MIN_LIMIT} and ${MAX_LIMIT}` };
    }
    out.maxMembers = n;
  }
  if (has('isPublic')) out.isPublic = body.isPublic !== false && body.isPublic !== 'false';
  if (has('logo')) {
    const r = validImageUrl(body.logo, 280000);
    if (r.error) return { error: r.error };
    out.logo = r.value;
  }
  if (has('coverImage')) {
    const r = validImageUrl(body.coverImage, 850000);
    if (r.error) return { error: r.error };
    out.coverImage = r.value;
  }
  return { data: out };
};

const newInviteCode = async () => {
  for (let i = 0; i < 10; i++) {
    const c = Team.generateInviteCode();
    if (!(await Team.exists({ inviteCode: c }))) return c;
  }
  return null;
};

// User ko team mein daalo. Dono steps atomic hain, isliye double-tap / 2 teams ek saath possible nahi.
// return: { team } ya { status, message }
const addMember = async (teamId, userId) => {
  const claimed = await User.updateOne({ _id: userId, team: null }, { $set: { team: teamId } });
  if (!claimed.modifiedCount) return { status: 409, message: 'You are already in a team.' };

  const team = await Team.findOneAndUpdate(
    {
      _id: teamId,
      $expr: { $lt: [{ $size: '$members' }, { $ifNull: ['$maxMembers', DEFAULT_MAX] }] },
    },
    {
      $addToSet: { members: userId },
      $pull: { joinRequests: { user: userId } },
      $push: { playerStats: { user: userId, matchesPlayed: 0, cuts: 0 } },
    },
    { new: true }
  );
  if (!team) {
    await User.updateOne({ _id: userId, team: teamId }, { $set: { team: null } }); // rollback
    const exists = await Team.exists({ _id: teamId });
    return exists
      ? { status: 400, message: 'This team is full.' }
      : { status: 404, message: 'Team not found.' };
  }
  // Ab ye user kisi aur team ki request nahi rakh sakta
  await Team.updateMany({ 'joinRequests.user': userId }, { $pull: { joinRequests: { user: userId } } });
  return { team };
};

const removeMemberDoc = async (teamId, userId) => {
  await Team.updateOne(
    { _id: teamId },
    { $pull: { members: userId, playerStats: { user: userId } } }
  );
  await User.updateOne({ _id: userId, team: teamId }, { $set: { team: null } });
};

const disband = async (team) => {
  await User.updateMany({ team: team._id }, { $set: { team: null } });
  await Team.deleteOne({ _id: team._id });
};

router.param('id', (req, res, next, id) => {
  if (!mongoose.isValidObjectId(id)) return fail(res, 400, 'Invalid team id');
  next();
});

// ==================== @POST /api/teams/create ====================
// Create Team screen. Banane wala captain.
// body: name, tag, region, about?, maxMembers? (4-20, default 10), isPublic?, logo?, coverImage?
router.post('/create', protect, wrap('Create team', async (req, res) => {
  const { data, error } = parseTeamInput(req.body, false);
  if (error) return fail(res, 400, error);

  const nameKey = data.name.toLowerCase();
  if (await Team.exists({ nameKey })) return fail(res, 409, 'This team name is already taken.');

  const teamId = new mongoose.Types.ObjectId();
  const claimed = await User.updateOne({ _id: req.user._id, team: null }, { $set: { team: teamId } });
  if (!claimed.modifiedCount) return fail(res, 409, 'You are already in a team.');

  try {
    let team;
    for (let i = 0; i < 5 && !team; i++) {
      const inviteCode = await newInviteCode();
      if (!inviteCode) break;
      try {
        team = await Team.create({
          _id: teamId,
          ...data,
          nameKey,
          inviteCode,
          maxMembers: data.maxMembers || DEFAULT_MAX,
          captain: req.user._id,
          members: [req.user._id],
          playerStats: [{ user: req.user._id }],
        });
      } catch (e) {
        if (e.code === 11000 && e.keyPattern && e.keyPattern.nameKey) throw e;
        if (e.code !== 11000) throw e; // invite code clash - dobara try
      }
    }
    if (!team) throw new Error('Could not generate invite code');

    return res.status(201).json({
      success: true,
      message: 'Team created! You are the captain.',
      team: teamDetail(await loadDetail(team._id), req.user._id),
    });
  } catch (error) {
    await User.updateOne({ _id: req.user._id, team: teamId }, { $set: { team: null } }); // rollback
    if (error.code === 11000) return fail(res, 409, 'This team name is already taken.');
    if (error.name === 'ValidationError') {
      return fail(res, 400, Object.values(error.errors)[0].message);
    }
    throw error;
  }
}));

// ==================== @GET /api/teams/mine ====================
// Teams screen ("MY TEAMS") + dashboard gate ("Get on a team to start battling")
// `team` = abhi ek user ek hi team mein ho sakta hai; `teams` list UI ke liye.
router.get('/mine', protect, wrap('My team', async (req, res) => {
  const me = await User.findById(req.user._id).select('team');
  const team = me.team ? await loadDetail(me.team) : null;
  const detail = team ? teamDetail(team, req.user._id) : null;
  // Pending requests (user ne kahan request bheji hai) - Teams screen par dikhane ke liye
  const pending = await Team.find({ 'joinRequests.user': req.user._id }).select('name tag region logo members maxMembers isPublic city');
  res.status(200).json({
    success: true,
    hasTeam: !!team,
    team: detail,
    teams: detail ? [detail] : [],
    pendingRequests: pending.map((t) => ({ ...teamCard(t, req.user._id), requested: true })),
  });
}));

// ==================== @GET /api/teams/public ====================
// Join a Team > Browse tab. ?q= (name / tag / region), ?page=1, ?limit=20
router.get('/public', protect, wrap('Public teams', async (req, res) => {
  const q = String(req.query.q || '').trim();
  const page = Math.max(1, parseInt(req.query.page, 10) || 1);
  const limit = Math.min(30, Math.max(1, parseInt(req.query.limit, 10) || 20));

  const filter = { isPublic: true };
  if (q) {
    const re = new RegExp(escapeRe(q), 'i');
    filter.$or = [{ name: re }, { tag: re }, { region: re }, { city: re }];
  }

  const [teams, total] = await Promise.all([
    Team.find(filter)
      .select('-coverImage -playerStats -stats')
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit),
    Team.countDocuments(filter),
  ]);

  res.status(200).json({
    success: true,
    page,
    total,
    hasMore: page * limit < total,
    teams: teams.map((t) => teamCard(t, req.user._id)),
  });
}));

// ==================== @GET /api/teams/code/:code ====================
// Join a Team > Code tab ("Find team") aur QR scan: pehle team dikhao, phir user Join dabaye.
router.get('/code/:code', protect, wrap('Find by code', async (req, res) => {
  const code = String(req.params.code || '').trim().toUpperCase();
  // QR mein poora link ho sakta hai - last part hi code hai
  const team = await Team.findOne({ inviteCode: code.split('/').pop() }).select('-coverImage -playerStats -stats');
  if (!team) return fail(res, 404, 'Team not found. Check the invite code.');
  res.status(200).json({ success: true, team: teamCard(team, req.user._id) });
}));

// ==================== @POST /api/teams/join ====================
// { inviteCode }  -> turant join (code / QR captain ne khud share kiya)
// { teamId }      -> public team: captain ko request (ya turant join, upar ka flag dekho)
router.post('/join', protect, wrap('Join team', async (req, res) => {
  const raw = String(req.body.inviteCode || '').trim().toUpperCase();
  const inviteCode = raw.split('/').pop();
  const { teamId } = req.body;

  if (!inviteCode && !teamId) return fail(res, 400, 'Enter an invite code.');
  if (teamId && !mongoose.isValidObjectId(teamId)) return fail(res, 400, 'Invalid team id');

  const me = await User.findById(req.user._id).select('team');
  if (me.team) return fail(res, 409, 'You are already in a team.');

  // ---- invite code ----
  if (inviteCode) {
    const team = await Team.findOne({ inviteCode }).select('_id name');
    if (!team) return fail(res, 404, 'Team not found. Check the invite code.');
    const r = await addMember(team._id, req.user._id);
    if (r.error || !r.team) return fail(res, r.status, r.message);
    return res.status(200).json({
      success: true,
      joined: true,
      message: `You joined ${r.team.name}!`,
      team: teamDetail(await loadDetail(r.team._id), req.user._id),
    });
  }

  // ---- public team (Browse tab) ----
  const team = await Team.findById(teamId);
  if (!team || !team.isPublic) return fail(res, 404, 'Team not found. Check the invite code.');
  if (team.members.length >= maxOf(team)) return fail(res, 400, 'This team is full.');

  if (!PUBLIC_JOIN_NEEDS_APPROVAL) {
    const r = await addMember(team._id, req.user._id);
    if (!r.team) return fail(res, r.status, r.message);
    return res.status(200).json({
      success: true,
      joined: true,
      message: `You joined ${r.team.name}!`,
      team: teamDetail(await loadDetail(r.team._id), req.user._id),
    });
  }

  if (hasRequested(team, req.user._id)) {
    return fail(res, 409, 'You already requested to join this team.', { requested: true });
  }
  await Team.updateOne(
    { _id: team._id, 'joinRequests.user': { $ne: req.user._id } },
    { $push: { joinRequests: { user: req.user._id } } }
  );
  res.status(202).json({
    success: true,
    joined: false,
    requested: true,
    message: `Request sent to ${team.name}. The captain will review it.`,
  });
}));

// ==================== @POST /api/teams/leave ====================
// Member team chhodta hai. Captain tabhi chhod sakta hai jab captaincy transfer kar de
// (ya wo akela ho - tab team disband ho jati hai).
router.post('/leave', protect, wrap('Leave team', async (req, res) => {
  const me = await User.findById(req.user._id).select('team');
  if (!me.team) return fail(res, 404, 'You are not in a team.');
  const team = await Team.findById(me.team);
  if (!team) {
    await User.updateOne({ _id: me._id }, { $set: { team: null } });
    return res.status(200).json({ success: true, message: 'You left the team.' });
  }
  if (isCaptainOf(team, me._id)) {
    if (team.members.length > 1) {
      return fail(res, 400, 'Transfer captaincy to another member before leaving.');
    }
    await disband(team);
    return res.status(200).json({ success: true, message: 'Team disbanded since you were the only member.' });
  }
  await removeMemberDoc(team._id, me._id);
  res.status(200).json({ success: true, message: `You left ${team.name}.` });
}));

// ==================== @DELETE /api/teams/requests/:id ====================
// User apni bheji hui request wapas leta hai (:id = team id)
router.delete('/requests/:id', protect, wrap('Cancel request', async (req, res) => {
  await Team.updateOne({ _id: req.params.id }, { $pull: { joinRequests: { user: req.user._id } } });
  res.status(200).json({ success: true, message: 'Request cancelled.' });
}));

// ==================== @GET /api/teams/leaderboard ====================
// Top teams: zyada wins, barabar ho to zyada cuts. Sirf public teams jinhone match khela ho.
router.get('/leaderboard', protect, wrap('Leaderboard', async (req, res) => {
  const teams = await Team.find({ isPublic: true, 'stats.played': { $gt: 0 } })
    .select('name tag region city stats members')
    .sort({ 'stats.wins': -1, 'stats.cutsScored': -1, 'stats.played': 1 })
    .limit(20);

  const myTeam = req.user.team ? sid(req.user.team) : null;
  res.status(200).json({
    success: true,
    teams: teams.map((t, i) => ({
      rank: i + 1,
      id: t._id,
      name: t.name,
      tag: tagOf(t),
      region: t.region || t.city || '',
      played: t.stats.played || 0,
      wins: t.stats.wins || 0,
      losses: t.stats.losses || 0,
      ties: t.stats.ties || 0,
      cutsScored: t.stats.cutsScored || 0,
      isMine: myTeam === sid(t._id),
    })),
  });
}));

// ==================== @GET /api/teams/:id ====================
// Team page. Member ko poora (invite + scoreboard), public team ka non-member ko basic view (Join team button).
router.get('/:id', protect, wrap('Team detail', async (req, res) => {
  const team = await loadDetail(req.params.id);
  if (!team) return fail(res, 404, 'Team not found.');
  if (!team.isPublic && !isMemberOf(team, req.user._id)) {
    return fail(res, 403, 'This team is private. Use an invite code to join.');
  }
  res.status(200).json({ success: true, team: teamDetail(team, req.user._id) });
}));

// ==================== @GET /api/teams/:id/matches ====================
// Matches tab. Match/battle module jab team stats record kare tab yahan uski list jodni hai.
router.get('/:id/matches', protect, wrap('Team matches', async (req, res) => {
  const team = await Team.findById(req.params.id).select('members isPublic');
  if (!team) return fail(res, 404, 'Team not found.');
  if (!team.isPublic && !isMemberOf(team, req.user._id)) return fail(res, 403, 'This team is private.');

  const tid = String(req.params.id);
  const battles = await Battle.find({
    $or: [{ challengerTeam: tid }, { opponentTeam: tid }],
    status: { $in: ['live', 'accepted', 'pending', 'final'] },
  })
    .populate('challengerTeam', 'name tag')
    .populate('opponentTeam', 'name tag')
    .sort({ createdAt: -1 })
    .limit(50);

  const matches = battles.map((b) => {
    const isChall = sid(b.challengerTeam) === tid;
    const opp = isChall ? b.opponentTeam : b.challengerTeam;
    const side = isChall ? 'challenger' : 'opponent';
    let result = null;
    if (b.status === 'final') result = b.winner === 'tie' ? 'T' : b.winner === side ? 'W' : 'L';
    // Best time to show: scheduled > ended > started > challenged
    const when = b.scheduledAt || b.endedAt || b.startedAt || b.challengedAt;
    return {
      id: b._id,
      status: b.status,
      venue: b.venue || '',
      area: b.area || '',
      opponent: { id: sid(opp), name: opp?.name || '', tag: opp?.tag || '' },
      myCuts: isChall ? b.challengerCuts : b.opponentCuts,
      oppCuts: isChall ? b.opponentCuts : b.challengerCuts,
      result,
      when,
      scheduledAt: b.scheduledAt || null,
      endedAt: b.endedAt || null,
      startedAt: b.startedAt || null,
    };
  });

  res.status(200).json({ success: true, matches });
}));

// ==================== CAPTAIN ONLY ====================
const captainOnly = async (req, res) => {
  const team = await Team.findById(req.params.id);
  if (!team) {
    fail(res, 404, 'Team not found.');
    return null;
  }
  if (!isCaptainOf(team, req.user._id)) {
    fail(res, 403, 'Only the captain can do this.');
    return null;
  }
  return team;
};

// ==================== @PUT /api/teams/:id ====================
// Team edit: name, tag, region, about, maxMembers, isPublic, logo, coverImage (jo bhejo wahi badlega)
router.put('/:id', protect, wrap('Edit team', async (req, res) => {
  const team = await captainOnly(req, res);
  if (!team) return;

  const { data, error } = parseTeamInput(req.body, true);
  if (error) return fail(res, 400, error);

  if (data.maxMembers !== undefined && data.maxMembers < team.members.length) {
    return fail(res, 400, `Team already has ${team.members.length} members. Remove some first.`);
  }
  if (data.name !== undefined) {
    const nameKey = data.name.toLowerCase();
    if (await Team.exists({ nameKey, _id: { $ne: team._id } })) {
      return fail(res, 409, 'This team name is already taken.');
    }
    team.nameKey = nameKey;
  }
  Object.assign(team, data);
  try {
    await team.save();
  } catch (e) {
    if (e.code === 11000) return fail(res, 409, 'This team name is already taken.');
    throw e;
  }
  res.status(200).json({
    success: true,
    message: 'Team updated.',
    team: teamDetail(await loadDetail(team._id), req.user._id),
  });
}));

// ==================== @POST /api/teams/:id/regenerate-code ====================
// Code leak ho gaya? Naya code (purana turant band)
router.post('/:id/regenerate-code', protect, wrap('Regenerate code', async (req, res) => {
  const team = await captainOnly(req, res);
  if (!team) return;
  const code = await newInviteCode();
  if (!code) return fail(res, 500, 'Could not generate a code. Try again.');
  team.inviteCode = code;
  await team.save();
  res.status(200).json({
    success: true,
    message: 'New invite code generated.',
    inviteCode: code,
    inviteLink: inviteLinkOf(team),
    qrData: inviteLinkOf(team),
  });
}));

// ==================== @GET /api/teams/:id/requests ====================
router.get('/:id/requests', protect, wrap('List requests', async (req, res) => {
  const team = await captainOnly(req, res);
  if (!team) return;
  await team.populate('joinRequests.user', 'name city profilePhoto');
  res.status(200).json({
    success: true,
    requests: team.joinRequests
      .filter((r) => r.user)
      .map((r) => ({
        userId: r.user._id,
        name: r.user.name,
        city: r.user.city || '',
        profilePhoto: r.user.profilePhoto || null,
        requestedAt: r.createdAt,
      })),
  });
}));

// ==================== @POST /api/teams/:id/requests/:userId/approve | reject ====================
router.post('/:id/requests/:userId/approve', protect, wrap('Approve request', async (req, res) => {
  const team = await captainOnly(req, res);
  if (!team) return;
  const { userId } = req.params;
  if (!mongoose.isValidObjectId(userId)) return fail(res, 400, 'Invalid user id');
  if (!hasRequested(team, userId)) return fail(res, 404, 'Request not found.');

  const r = await addMember(team._id, userId);
  if (!r.team) {
    if (r.status === 409) {
      // Is beech wo kisi aur team mein chala gaya
      await Team.updateOne({ _id: team._id }, { $pull: { joinRequests: { user: userId } } });
      return fail(res, 409, 'This player has already joined another team.');
    }
    return fail(res, r.status, r.message);
  }
  res.status(200).json({
    success: true,
    message: 'Player added to the team.',
    team: teamDetail(await loadDetail(team._id), req.user._id),
  });
}));

router.post('/:id/requests/:userId/reject', protect, wrap('Reject request', async (req, res) => {
  const team = await captainOnly(req, res);
  if (!team) return;
  const { userId } = req.params;
  if (!mongoose.isValidObjectId(userId)) return fail(res, 400, 'Invalid user id');
  await Team.updateOne({ _id: team._id }, { $pull: { joinRequests: { user: userId } } });
  res.status(200).json({ success: true, message: 'Request rejected.' });
}));

// ==================== @DELETE /api/teams/:id/members/:userId ====================
// Captain kisi member ko nikalta hai
router.delete('/:id/members/:userId', protect, wrap('Remove member', async (req, res) => {
  const team = await captainOnly(req, res);
  if (!team) return;
  const { userId } = req.params;
  if (!mongoose.isValidObjectId(userId)) return fail(res, 400, 'Invalid user id');
  if (sid(userId) === sid(req.user._id)) {
    return fail(res, 400, 'Captain cannot be removed. Transfer captaincy or leave the team.');
  }
  if (!isMemberOf(team, userId)) return fail(res, 404, 'This player is not in your team.');
  await removeMemberDoc(team._id, userId);
  res.status(200).json({
    success: true,
    message: 'Member removed.',
    team: teamDetail(await loadDetail(team._id), req.user._id),
  });
}));

// ==================== @POST /api/teams/:id/transfer-captain ====================
// body: { userId } - naya captain (team ka member hona chahiye)
router.post('/:id/transfer-captain', protect, wrap('Transfer captain', async (req, res) => {
  const team = await captainOnly(req, res);
  if (!team) return;
  const { userId } = req.body;
  if (!mongoose.isValidObjectId(userId) || !isMemberOf(team, userId)) {
    return fail(res, 400, 'Pick a member of your team.');
  }
  if (sid(userId) === sid(req.user._id)) return fail(res, 400, 'You are already the captain.');
  team.captain = userId;
  await team.save();
  res.status(200).json({
    success: true,
    message: 'Captaincy transferred.',
    team: teamDetail(await loadDetail(team._id), req.user._id),
  });
}));

// ==================== @DELETE /api/teams/:id ====================
// Team disband - sab members free ho jate hain
router.delete('/:id', protect, wrap('Delete team', async (req, res) => {
  const team = await captainOnly(req, res);
  if (!team) return;
  await disband(team);
  res.status(200).json({ success: true, message: 'Team disbanded.' });
}));

module.exports = router;
