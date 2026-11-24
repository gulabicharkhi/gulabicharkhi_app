// ============================================================
// Demo data seed: teams + captains + LIVE / UPCOMING / FINAL matches
//
//   cd backend
//   npm run seed            -> demo data banao (purana demo data hata kar)
//   npm run seed:clear      -> sirf demo data hata do
//
// Demo users ka password: Demo@1234   (email verified hain, seedha login ho jata hai)
// Captains (login karke challenge / accept / start / cut claim / end test karo):
//   jpb.captain@demo.gc.test   -> Jaipur Patangbaaz   (JPB)
//   pcc.captain@demo.gc.test   -> Pink City Cutters   (PCC)
//   aff.captain@demo.gc.test   -> Amer Fort Flyers    (AFF)
//   jjt.captain@demo.gc.test   -> Jhalana Jets        (JJT)
//   mmj.captain@demo.gc.test   -> Malviya Manjha      (MMJ)
// ============================================================
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const mongoose = require('mongoose');
const User = require('../models/User');
const Team = require('../models/Team');
const Battle = require('../models/Battle');
const Notification = require('../models/Notification');

const DOMAIN = 'demo.gc.test';
const PASSWORD = 'Demo@1234';
const hoursAgo = (h) => new Date(Date.now() - h * 3600 * 1000);
const minsAgo = (m) => new Date(Date.now() - m * 60 * 1000);

// [lng, lat]
const JAIPUR = { jhalana: [75.8277, 26.8869], amer: [75.8513, 26.9855], malviya: [75.8068, 26.8546], mansarovar: [75.7597, 26.8523] };

const TEAMS = [
  { key: 'jpb', name: 'Jaipur Patangbaaz', tag: 'JPB', city: 'Jaipur', members: ['Rohit Sharma', 'Aman Verma', 'Karan Singh'] },
  { key: 'pcc', name: 'Pink City Cutters', tag: 'PCC', city: 'Jaipur', members: ['Vikram Rathore', 'Nitin Joshi', 'Saurabh Gupta'] },
  { key: 'aff', name: 'Amer Fort Flyers', tag: 'AFF', city: 'Jaipur', members: ['Deepak Meena', 'Arjun Shekhawat', 'Manish Jain'] },
  { key: 'jjt', name: 'Jhalana Jets', tag: 'JJT', city: 'Jaipur', members: ['Pankaj Saini', 'Harsh Agarwal', 'Yash Soni'] },
  { key: 'mmj', name: 'Malviya Manjha', tag: 'MMJ', city: 'Jaipur', members: ['Rahul Khandelwal', 'Sumit Bansal', 'Ravi Yadav'] },
  { key: 'ddd', name: 'Delhi Dor Dhamaka', tag: 'DDD', city: 'Delhi', members: ['Gaurav Malhotra', 'Tarun Kapoor', 'Sahil Arora'] },
  { key: 'ccc', name: 'Chandni Chowk Cutters', tag: 'CCC', city: 'Delhi', members: ['Imran Khan', 'Nikhil Mehra', 'Aditya Bhatia'] },
  { key: 'aut', name: 'Ahmedabad Uttarayan', tag: 'AUT', city: 'Ahmedabad', members: ['Jignesh Patel', 'Hardik Shah', 'Kunal Desai'] },
];

async function clearDemo() {
  const users = await User.find({ email: new RegExp(`@${DOMAIN.replace(/\./g, '\\.')}$`) }).select('_id team');
  const userIds = users.map((u) => u._id);
  const teams = await Team.find({ captain: { $in: userIds } }).select('_id');
  const teamIds = teams.map((t) => t._id);
  const b = await Battle.deleteMany({ $or: [{ challengerTeam: { $in: teamIds } }, { opponentTeam: { $in: teamIds } }] });
  await Notification.deleteMany({ user: { $in: userIds } });
  await Team.deleteMany({ _id: { $in: teamIds } });
  await User.deleteMany({ _id: { $in: userIds } });
  console.log(`🧹 Removed demo data: ${userIds.length} users, ${teamIds.length} teams, ${b.deletedCount} battles`);
}

async function main() {
  await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/gulabi_charkhi');
  console.log('✅ MongoDB connected');
  await clearDemo();
  if (process.argv.includes('--clear')) return;

  // ---------- Users + Teams ----------
  const T = {}; // key -> { team, captain, members: [User] }
  for (const t of TEAMS) {
    const mk = async (name, email) => {
      const u = new User({ name, email, password: PASSWORD, city: t.city, isVerified: true });
      await u.save();
      return u;
    };
    const captain = await mk(`${t.members[0]} (C)`, `${t.key}.captain@${DOMAIN}`);
    const others = [];
    for (let i = 1; i < t.members.length; i++) {
      others.push(await mk(t.members[i], `${t.key}.player${i}@${DOMAIN}`));
    }
    const all = [captain, ...others];
    const team = await Team.create({
      name: t.name,
      nameKey: t.name.toLowerCase(),
      inviteCode: Team.generateInviteCode(),
      tag: t.tag,
      region: t.city,
      city: t.city,
      about: `${t.name} - ${t.city} ki patang cutting team`,
      isPublic: true,
      captain: captain._id,
      members: all.map((u) => u._id),
      playerStats: all.map((u) => ({ user: u._id })),
    });
    await User.updateMany({ _id: { $in: all.map((u) => u._id) } }, { $set: { team: team._id } });
    T[t.key] = { team, captain, members: all };
  }
  console.log(`👥 Created ${TEAMS.length} teams`);

  // ---------- Battle helper ----------
  // events: [['c'|'o', 'approved'|'rejected'|'pending', playerIndex?]]  c = challenger ne claim kiya
  const makeBattle = async ({ ch, op, status, venue, area, coords, cCuts = 0, oCuts = 0, events = [], startedAgoMin, endedAgoMin, ready }) => {
    const C = T[ch], O = T[op];
    const b = new Battle({
      challengerTeam: C.team._id,
      opponentTeam: O.team._id,
      challengerCaptain: C.captain._id,
      opponentCaptain: status === 'pending' ? null : O.captain._id,
      venue, area,
      location: { type: 'Point', coordinates: coords || [0, 0] },
      status,
      challengedAt: hoursAgo(3),
      acceptedAt: status === 'pending' ? null : hoursAgo(2),
    });
    if (status === 'accepted') {
      b.challengerReady = ready === 'challenger' || ready === 'both';
      b.opponentReady = ready === 'opponent' || ready === 'both';
    }
    if (status === 'live' || status === 'final') {
      b.challengerReady = b.opponentReady = true;
      b.startedAt = minsAgo(startedAgoMin || 30);
    }
    if (status === 'final') {
      b.endedAt = minsAgo(endedAgoMin || 10);
      b.winner = cCuts > oCuts ? 'challenger' : oCuts > cCuts ? 'opponent' : 'tie';
    }
    b.challengerCuts = cCuts;
    b.opponentCuts = oCuts;

    // Cut events (live feed) - approved wale score se match karte hain
    let approvedC = 0, approvedO = 0;
    const evs = events.length ? events : [
      ...Array.from({ length: cCuts }, () => ['c', 'approved']),
      ...Array.from({ length: oCuts }, () => ['o', 'approved']),
    ];
    evs.forEach(([side, st, pi], i) => {
      const claimer = side === 'c' ? C : O;
      const player = claimer.members[(pi ?? i) % claimer.members.length];
      b.cutEvents.push({
        claimedBy: claimer.captain._id,
        claimedByTeam: claimer.team._id,
        cutPlayer: player._id,
        status: st,
        rejectionReason: st === 'rejected' ? 'Manjha touch hua, cut nahi tha' : '',
        createdAt: minsAgo(25 - i * 2),
        resolvedAt: st === 'pending' ? null : minsAgo(24 - i * 2),
      });
      if (st === 'approved') (side === 'c' ? approvedC++ : approvedO++);
    });
    if (events.length) { b.challengerCuts = approvedC; b.opponentCuts = approvedO; }
    await b.save();

    // Final match ka result team stats me bhi (leaderboard ke liye)
    if (status === 'final') {
      const res = b.winner === 'challenger' ? ['W', 'L'] : b.winner === 'opponent' ? ['L', 'W'] : ['T', 'T'];
      const per = (side) => {
        const out = {};
        b.cutEvents.filter((e) => e.status === 'approved' && String(e.claimedByTeam) === String((side === 'c' ? C : O).team._id))
          .forEach((e) => { out[String(e.cutPlayer)] = (out[String(e.cutPlayer)] || 0) + 1; });
        return out;
      };
      await Team.recordResult(C.team._id, { result: res[0], cutsScored: b.challengerCuts, cutsConceded: b.opponentCuts, playerCuts: per('c') });
      await Team.recordResult(O.team._id, { result: res[1], cutsScored: b.opponentCuts, cutsConceded: b.challengerCuts, playerCuts: per('o') });
      await User.updateMany({ team: C.team._id }, { $inc: { 'stats.matches': 1, ...(res[0] === 'W' ? { 'stats.wins': 1 } : {}) } });
      await User.updateMany({ team: O.team._id }, { $inc: { 'stats.matches': 1, ...(res[1] === 'W' ? { 'stats.wins': 1 } : {}) } });
    }
    return b;
  };

  // ---------- FINAL (pehle, taaki history bane) ----------
  await makeBattle({ ch: 'jpb', op: 'aff', status: 'final', venue: 'Amer Road Ground', area: 'Amer, Jaipur', coords: JAIPUR.amer, cCuts: 7, oCuts: 4, startedAgoMin: 300, endedAgoMin: 240 });
  await makeBattle({ ch: 'pcc', op: 'jjt', status: 'final', venue: 'Jhalana Ground', area: 'Jhalana, Jaipur', coords: JAIPUR.jhalana, cCuts: 3, oCuts: 6, startedAgoMin: 200, endedAgoMin: 150 });
  await makeBattle({ ch: 'mmj', op: 'pcc', status: 'final', venue: 'Malviya Nagar Terrace', area: 'Malviya Nagar, Jaipur', coords: JAIPUR.malviya, cCuts: 5, oCuts: 5, startedAgoMin: 120, endedAgoMin: 80 });
  await makeBattle({ ch: 'ddd', op: 'ccc', status: 'final', venue: 'Red Fort Maidan', area: 'Old Delhi, Delhi', cCuts: 8, oCuts: 2, startedAgoMin: 400, endedAgoMin: 340 });

  // ---------- LIVE ----------
  // Jaipur Patangbaaz vs Pink City Cutters: ek cut pending (PCC captain approve/reject kar sakta hai)
  await makeBattle({
    ch: 'jpb', op: 'pcc', status: 'live', venue: 'Jhalana Ground', area: 'Jhalana, Jaipur', coords: JAIPUR.jhalana, startedAgoMin: 30,
    events: [['c', 'approved'], ['o', 'approved'], ['c', 'approved'], ['c', 'rejected'], ['o', 'approved'], ['c', 'approved'], ['c', 'pending']],
  });
  await makeBattle({
    ch: 'aff', op: 'jjt', status: 'live', venue: 'Amer Road Ground', area: 'Amer, Jaipur', coords: JAIPUR.amer, startedAgoMin: 12,
    events: [['c', 'approved'], ['o', 'approved']],
  });
  await makeBattle({
    ch: 'ddd', op: 'ccc', status: 'live', venue: 'Lal Qila Ground', area: 'Old Delhi, Delhi', startedAgoMin: 20, cCuts: 2, oCuts: 3,
  });

  // ---------- UPCOMING ----------
  // pending: MMJ ne JPB ko challenge bheja (JPB captain accept kar sakta hai)
  await makeBattle({ ch: 'mmj', op: 'jpb', status: 'pending', venue: 'Malviya Nagar Terrace', area: 'Malviya Nagar, Jaipur', coords: JAIPUR.malviya });
  // pending: JJT ne MMJ ko challenge bheja
  await makeBattle({ ch: 'jjt', op: 'mmj', status: 'pending', venue: 'Mansarovar Ground', area: 'Mansarovar, Jaipur', coords: JAIPUR.mansarovar });
  // accepted: AFF captain ready, PCC captain ka wait (PCC captain "Start" dabaye to live)
  await makeBattle({ ch: 'aff', op: 'mmj', status: 'accepted', ready: 'challenger', venue: 'Amer Road Ground', area: 'Amer, Jaipur', coords: JAIPUR.amer });
  await makeBattle({ ch: 'aut', op: 'ddd', status: 'accepted', ready: 'none', venue: 'Sabarmati Riverfront', area: 'Ahmedabad' });

  const counts = await Promise.all(['live', 'pending', 'accepted', 'final'].map((s) => Battle.countDocuments({ status: s })));
  console.log(`🪁 Battles -> live:${counts[0]} pending:${counts[1]} accepted:${counts[2]} final:${counts[3]}`);
  console.log('\n🔑 Login (password: ' + PASSWORD + ')');
  TEAMS.forEach((t) => console.log(`   ${t.tag}  ${t.key}.captain@${DOMAIN}   (${t.city})`));
  console.log('\nDone ✅  App me Jaipur wale captain se login karke Matches tab kholo.');
}

main()
  .catch((e) => { console.error('❌ Seed failed:', e); process.exitCode = 1; })
  .finally(() => mongoose.disconnect());
