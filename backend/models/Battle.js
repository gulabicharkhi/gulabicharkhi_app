const mongoose = require('mongoose');

// ============================================================
// Battle (Match) Model
// Ek battle = do teams ke beech ek kite cutting match
// Status flow: pending -> accepted -> live -> final
//
// Challenge flow:
//   challenger team captain -> POST /api/battles/challenge
//   opponent captain -> POST /api/battles/:id/accept
//   dono captains -> POST /api/battles/:id/start (dono ne accept kiya to live)
//   match ke dauran -> POST /api/battles/:id/claim-cut (kite cut claim)
//   opponent captain -> POST /api/battles/:id/cuts/:cutId/respond (approve/reject)
//   end -> POST /api/battles/:id/end
// ============================================================

const CutEventSchema = new mongoose.Schema({
  _id: { type: mongoose.Schema.Types.ObjectId, default: () => new mongoose.Types.ObjectId() },
  claimedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },   // captain jo claim kar raha hai
  claimedByTeam: { type: mongoose.Schema.Types.ObjectId, ref: 'Team', required: true }, // us captain ki team
  cutPlayer: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },     // kon kata (optional)
  status: { type: String, enum: ['pending', 'approved', 'rejected'], default: 'pending' },
  rejectionReason: { type: String, default: '' },
  createdAt: { type: Date, default: Date.now },
  resolvedAt: { type: Date, default: null },
});

const BattleSchema = new mongoose.Schema({
  // Challenger = jo challenge bheja; opponent = jo receive kiya
  challengerTeam: { type: mongoose.Schema.Types.ObjectId, ref: 'Team', required: true },
  opponentTeam:   { type: mongoose.Schema.Types.ObjectId, ref: 'Team', required: true },

  // Captains jo is battle ko manage kar rahe hain (team ke actual captain na bhi ho sakta hai - transfer ka case)
  challengerCaptain: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  opponentCaptain:   { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null },

  // Battle venue / location (optional - jahan battle ho rahi hai)
  venue: { type: String, trim: true, maxlength: 100, default: '' },
  area:  { type: String, trim: true, maxlength: 100, default: '' }, // e.g. "Jhalana, Jaipur"

  // GPS coordinates (optional - Matches near you filter ke liye)
  location: {
    type: { type: String, enum: ['Point'], default: 'Point' },
    coordinates: { type: [Number], default: [0, 0] }, // [lng, lat]
  },

  // Status
  // pending   = challenge bheja, opponent ne accept nahi kiya
  // accepted  = opponent ne accept kiya, dono captains ne start confirm nahi kiya
  // live      = battle chal rahi hai
  // final     = battle khatam
  // cancelled = koi bhi side ne cancel kiya (pending/accepted mein)
  status: {
    type: String,
    enum: ['pending', 'accepted', 'live', 'final', 'cancelled'],
    default: 'pending',
    index: true,
  },

  // Dono captains ne "Accept & start" dabaya?
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
  // Scheduled match time (optional - jab match fix ho jaye tab set karo)
  scheduledAt:  { type: Date, default: null },
}, {
  timestamps: true, // createdAt, updatedAt
});

// Geospatial index - Matches near you ke liye
BattleSchema.index({ location: '2dsphere' });
BattleSchema.index({ status: 1, createdAt: -1 });
BattleSchema.index({ challengerTeam: 1, status: 1 });
BattleSchema.index({ opponentTeam: 1, status: 1 });

module.exports = mongoose.model('Battle', BattleSchema);
