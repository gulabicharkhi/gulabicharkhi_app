const mongoose = require('mongoose');

const DEFAULT_MAX_MEMBERS = 10;

const TeamSchema = new mongoose.Schema({
  name: {
    type: String,
    required: [true, 'Team name is required'],
    trim: true,
    minlength: [3, 'Team name must be at least 3 characters'],
    maxlength: [30, 'Team name cannot exceed 30 characters'],
  },
  // For a case-insensitive unique check
  nameKey: { type: String, unique: true, index: true },
  inviteCode: { type: String, unique: true, index: true },

  // 2-4 letters shown on match cards (e.g. SKR). If older teams do not have one, it is generated from the name.
  tag: { type: String, trim: true, uppercase: true, maxlength: 4, default: '' },
  region: { type: String, trim: true, maxlength: 60, default: '' },
  // Old field - used as a fallback if there is no region
  city: { type: String, trim: true, default: '' },
  about: { type: String, trim: true, maxlength: 200, default: '' },

  // URL or a small base64 data URI
  logo: { type: String, default: null },
  coverImage: { type: String, default: null },

  isPublic: { type: Boolean, default: true },
  maxMembers: { type: Number, min: 4, max: 20, default: DEFAULT_MAX_MEMBERS },

  captain: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  members: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],

  // Public team par "Join" button pressed by players - the captain approves/rejects
  joinRequests: [
    {
      _id: false,
      user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', index: true },
      createdAt: { type: Date, default: Date.now },
    },
  ],

  // Scoreboard tab
  stats: {
    played: { type: Number, default: 0 },
    wins: { type: Number, default: 0 },
    losses: { type: Number, default: 0 },
    ties: { type: Number, default: 0 },
    cutsScored: { type: Number, default: 0 },
    cutsConceded: { type: Number, default: 0 },
    recentForm: { type: [String], default: [] }, // 'W' | 'L' | 'T', latest last
  },
  // Players table (MP = matches played, CUTS)
  playerStats: [
    {
      _id: false,
      user: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
      matchesPlayed: { type: Number, default: 0 },
      cuts: { type: Number, default: 0 },
    },
  ],

  createdAt: { type: Date, default: Date.now },
});

// 6 character invite code (no confusing letters like 0/O/1/I)
const CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
TeamSchema.statics.generateInviteCode = function () {
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
  }
  return code;
};

// Hook for the Battle/match module: call this when the match ends
//   await Team.recordResult(teamId, { result: 'W', cutsScored: 5, cutsConceded: 2, playerCuts: { [userId]: 3 } })
TeamSchema.statics.recordResult = async function (teamId, { result, cutsScored = 0, cutsConceded = 0, playerCuts = {} }) {
  const team = await this.findById(teamId);
  if (!team) return null;
  const key = { W: 'wins', L: 'losses', T: 'ties' }[result];
  if (!key) throw new Error('result must be W, L or T');
  team.stats.played += 1;
  team.stats[key] += 1;
  team.stats.cutsScored += cutsScored;
  team.stats.cutsConceded += cutsConceded;
  team.stats.recentForm = [...team.stats.recentForm, result].slice(-5);
  for (const ps of team.playerStats) {
    const uid = String(ps.user);
    if (uid in playerCuts) {
      ps.matchesPlayed += 1;
      ps.cuts += playerCuts[uid];
    }
  }
  await team.save();
  return team;
};

TeamSchema.statics.DEFAULT_MAX_MEMBERS = DEFAULT_MAX_MEMBERS;

module.exports = mongoose.model('Team', TeamSchema);
