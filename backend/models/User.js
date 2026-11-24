// ============================================================
// User Model — UPDATED: fcmToken field add kiya
// models/User.js
//
// Purana model ka pura code SAME hai, sirf fcmToken field add kiya hai.
// Search for "FCM" to find the new additions.
// ============================================================

const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const UserSchema = new mongoose.Schema({
  name: {
    type: String,
    required: [true, 'Name is required'],
    trim: true,
    maxlength: [50, 'Name cannot exceed 50 characters'],
  },
  email: {
    type: String,
    required: [true, 'Email is required'],
    unique: true,
    lowercase: true,
    trim: true,
    match: [/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/, 'Invalid email'],
  },
  password: {
    type: String,
    required: [true, 'Password is required'],
    minlength: [6, 'Password must be at least 6 characters'],
    select: false,
  },
  city: {
    type: String,
    trim: true,
    default: '',
  },

  // ==================== Profile fields ====================
  phone: {
    type: String,
    trim: true,
    default: '',
  },
  dateOfBirth: {
    type: Date,
    default: null,
  },
  profilePhoto: {
    type: String,
    default: null,
  },

  // ==================== Auth ====================
  isVerified: {
    type: Boolean,
    default: false,
  },
  otp: {
    code:      { type: String, default: null },
    expiresAt: { type: Date,   default: null },
    attempts:  { type: Number, default: 0 },
    sentAt:    { type: Date,   default: null },
  },

  // ==================== Team ====================
  team: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Team',
    default: null,
  },

  // ==================== Federation ====================
  federationId: {
    type: String,
    default: null,
  },

  // ==================== Stats ====================
  stats: {
    matches: { type: Number, default: 0 },
    wins:    { type: Number, default: 0 },
    rank:    { type: Number, default: null },
  },

  // ==================== Sessions ====================
  sessions: [
    {
      _id: false,
      token:    { type: String, required: true },
      device:   { type: String, default: 'Unknown' },
      loginAt:  { type: Date, default: Date.now },
      lastSeen: { type: Date, default: Date.now },
    },
  ],

  // ==================== FCM — NAYA FIELD ====================
  // Flutter app se login/startup par POST /api/notifications/fcm-token pe bheja jata hai
  // Push notifications iske zariye jaati hain (Firebase Cloud Messaging)
  // Ek device par login karne par pichla token replace ho jata hai
  // App uninstall ya token expire hone par push fail hoti hai aur field clear ho jati hai
  fcmToken: {
    type: String,
    default: null,
    select: false,  // by default queries mein nahi aata (security)
  },

  createdAt: {
    type: Date,
    default: Date.now,
  },
});

// ==================== Hooks ====================

UserSchema.pre('save', async function () {
  if (!this.isModified('password')) return;
  const salt = await bcrypt.genSalt(12);
  this.password = await bcrypt.hash(this.password, salt);
});

// ==================== Methods ====================

UserSchema.methods.comparePassword = async function (enteredPassword) {
  return bcrypt.compare(enteredPassword, this.password);
};

UserSchema.methods.generateOtp = function () {
  const otp = Math.floor(100000 + Math.random() * 900000).toString();
  this.otp = {
    code:      otp,
    expiresAt: new Date(Date.now() + 10 * 60 * 1000),
    attempts:  0,
    sentAt:    new Date(),
  };
  return otp;
};

UserSchema.methods.verifyOtp = function (inputOtp) {
  if (!this.otp || !this.otp.code || !this.otp.expiresAt) {
    return { valid: false, message: 'No OTP found. Please request a new one.' };
  }
  if (new Date() > this.otp.expiresAt) {
    return { valid: false, message: 'OTP expired. Please request a new one.' };
  }
  if (this.otp.attempts >= 5) {
    return { valid: false, message: 'Too many attempts. Please request a new OTP.' };
  }
  this.otp.attempts += 1;
  if (this.otp.code !== inputOtp) {
    return { valid: false, message: 'Invalid OTP. Please try again.' };
  }
  this.otp = { code: null, expiresAt: null, attempts: 0, sentAt: null };
  return { valid: true };
};

module.exports = mongoose.model('User', UserSchema);
