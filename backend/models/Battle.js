const mongoose = require('mongoose');

// ============================================================
// Battle (Match) Model
// One battle = one kite cutting match between two teams
// Status flow: pending -> accepted -> live -> final
//
// Challenge flow:
//   challenger team captain -> POST /api/battles/challenge
//   opponent captain -> POST /api/battles/:id/accept
//   dono captains -> POST /api/battles/:id/start (goes live once both have accepted)
//   during the match -> POST /api/battles/:id/claim-cut (kite cut claim)
//   opponent captain -> POST /api/battles/:id/cuts/:cutId/respond (approve/reject)
//   end -> POST /api/battles/:id/end
// ============================================================

const CutEventSchema = new mongoose.Schema({
  _id: { type: mongoose.Schema.Types.ObjectId, default: () => new mongoose.Types.ObjectId() },
  claimedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },   // the captain who is making the claim
  claimedByTeam: { type: mongoose.Schema.Types.ObjectId, ref: 'Team', required: true }, // team of that captain
  cutPlayer: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },     // first winner (for older clients)
  // Bout: who won, who lost. Players of the claiming team won, players of the opposing team lost.
  winners: [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
  losers:  [{ type: mongoose.Schema.Types.ObjectId, ref: 'User' }],
  status: { type: String, enum: ['pending', 'approved', 'rejected'], default: 'pending' },
  rejectionReason: { type: String, default: '' },
  createdAt: { type: Date, default: Date.now },
  resolvedAt: { type: Date, default: null },
});

const BattleSchema = new mongoose.Schema({
  // Challenger = the one who sent the challenge; opponent = the one who received it
  challengerTeam: { type: mongoose.Schema.Types.ObjectId, ref: 'Team', required: true },
  opponentTeam:   { type: mongoose.Schema.Types.ObjectId, ref: 'Team', required: true },

  // Captains managing this battle (may not be the actual team captain - captaincy transfer case)
  challengerCaptain: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  opponentCaptain:   { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },

  // Battle venue / location (optional - where the battle is taking place)
  venue: { type: String, trim: true, maxlength: 100, default: '' },
  area:  { type: String, trim: true, maxlength: 100, default: '' }, // e.g. "Jhalana, Jaipur"

  // GPS coordinates (optional - for the Matches near you filter)
  location: {
    type: { type: String, enum: ['Point'], default: 'Point' },
    coordinates: { type: [Number], default: [0, 0] }, // [lng, lat]
  },

  // Status
  // pending   = challenge sent, opponent has not accepted
  // accepted  = opponent accepted, both captains have not confirmed the start
  // live      = battle is in progress
  // final     = battle finished
  // cancelled = cancelled by either side (while pending/accepted)
  status: {
    type: String,
    enum: ['pending', 'accepted', 'live', 'final', 'cancelled'],
    default: 'pending',
    index: true,
  },

  // Did both captains press "Accept & start"?
  challengerReady: { type: Boolean, default: false },
  opponentReady:   { type: Boolean, default: false },

  // Score (cuts)
  challengerCuts: { type: Number, default: 0 },
  opponentCuts:   { type: Number, default: 0 },

  // Cut events (live feed)
  cutEvents: [CutEventSchema],

  // Result
  // 'challenger' | 'opponent' | 'tie' | null
  winner: { type: String, enum: ['challenger', 'opponent', 'tie', null], default: null },

  // Timestamps
  challengedAt: { type: Date, default: Date.now },
  acceptedAt:   { type: Date, default: null },
  startedAt:    { type: Date, default: null },
  endedAt:      { type: Date, default: null },
  // Scheduled match time (optional - set it once the match is fixed)
  scheduledAt:  { type: Date, default: null },
}, {
  timestamps: true, // createdAt, updatedAt
});

// Geospatial index - for Matches near you
BattleSchema.index({ location: '2dsphere' });
BattleSchema.index({ status: 1, createdAt: -1 });
BattleSchema.index({ challengerTeam: 1, status: 1 });
BattleSchema.index({ opponentTeam: 1, status: 1 });

module.exports = mongoose.model('Battle', BattleSchema);
