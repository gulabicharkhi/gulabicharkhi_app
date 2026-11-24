const mongoose = require('mongoose');

// ============================================================
// Association (Kite Federation) Model
// In the app: shown in the Association tab
// e.g. "Rajasthan Patang Sangh", "Jaipur Kite Federation"
//
// Officials/Judges are also stored in this model
// Federation membership registration is also here
// ============================================================

const OfficialSchema = new mongoose.Schema({
  _id: false,
  name:  { type: String, required: true, trim: true },
  role:  { type: String, trim: true, default: '' }, // "Lead Judge", "Match Referee", etc.
  photo: { type: String, default: null }, // URL or base64
});

const FederationMemberSchema = new mongoose.Schema({
  user:        { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  fullName:    { type: String, trim: true },
  phone:       { type: String, trim: true, default: '' },
  city:        { type: String, trim: true, default: '' },
  status:      { type: String, enum: ['pending', 'approved', 'rejected'], default: 'pending' },
  federationId: { type: String, default: null }, // assigned after approval, e.g. "KA-JPR-001"
  registeredAt: { type: Date, default: Date.now },
});

const RuleBookSection = new mongoose.Schema({
  _id: false,
  title:   { type: String, required: true },
  content: { type: String, default: '' },
});

const AssociationSchema = new mongoose.Schema({
  name:    { type: String, required: true, trim: true, maxlength: 100 },
  state:   { type: String, trim: true, default: '' }, // "Rajasthan"
  city:    { type: String, trim: true, default: '' }, // "Jaipur, RJ"
  logo:    { type: String, default: null },           // URL or base64

  // Contact
  email:   { type: String, trim: true, default: '' }, // "hello@kiteassociation.in"
  website: { type: String, trim: true, default: '' },

  // Officials & Judges (shown on the Association detail page)
  officials: [OfficialSchema],

  // Rule book sections (expandable accordions in app)
  ruleBook: [RuleBookSection],

  // Federation members
  members: [FederationMemberSchema],

  // Sanctioned events count (auto-calculated or manual)
  sanctionedEvents: { type: Number, default: 0 },

  createdAt: { type: Date, default: Date.now },
}, { timestamps: true });

// Virtual: total members count
AssociationSchema.virtual('memberCount').get(function () {
  return this.members.filter((m) => m.status === 'approved').length;
});

module.exports = mongoose.model('Association', AssociationSchema);
