const mongoose = require('mongoose');

// ============================================================
// Tournament Model
// Association wale sanctioned tournaments create karte hain
// App mein: Association tab > Sanctioned Tournaments list
// Status: registrations_open | invite_only | waitlist | closed | ongoing | finished
// ============================================================

const TournamentSchema = new mongoose.Schema({
  title: { type: String, required: true, trim: true, maxlength: 100 },

  // Schedule
  date: { type: Date, required: true },

  // Venue
  venue: { type: String, trim: true, maxlength: 100, default: '' },
  area:  { type: String, trim: true, maxlength: 100, default: '' }, // e.g. "Amer Road"

  // GPS (Matches near you / distance filter ke liye)
  location: {
    type: { type: String, enum: ['Point'], default: 'Point' },
    coordinates: { type: [Number], default: [0, 0] }, // [lng, lat]
  },

  // Registration status badge (app mein dikhega)
  registrationStatus: {
    type: String,
    enum: ['registrations_open', 'invite_only', 'waitlist', 'closed'],
    default: 'registrations_open',
  },

  // Linked association (optional)
  association: { type: mongoose.Schema.Types.ObjectId, ref: 'Association', default: null },

  // Description / rules
  description: { type: String, trim: true, maxlength: 1000, default: '' },

  // Registered teams
  registeredTeams: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Team' }],

  createdAt: { type: Date, default: Date.now },
}, { timestamps: true });

TournamentSchema.index({ location: '2dsphere' });
TournamentSchema.index({ date: 1 });

module.exports = mongoose.model('Tournament', TournamentSchema);
