// ============================================================
// Notification Model — UPDATED with Firebase Push Support
// models/Notification.js
//
// Purana model ka pura behaviour SAME hai.
// Naya feature: .send() aur .broadcast() ab FCM push bhi bhejte hain.
//
// Flow:
//  1. DB mein notification save hoti hai (pehle jaisi)
//  2. User ka fcmToken fetch hota hai (User model se)
//  3. Firebase se push bheja jata hai
//  4. Push fail ho to bhi main operation fail nahi hoti
// ============================================================

const mongoose = require('mongoose');
const { sendPush, sendMulticastPush } = require('../config/firebase');

const NotificationSchema = new mongoose.Schema({
  user:    { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
  type:    { type: String, required: true, trim: true },
  title:   { type: String, default: '' },
  body:    { type: String, default: '' },
  refType: { type: String, default: null },
  refId:   { type: mongoose.Schema.Types.ObjectId, default: null },
  read:    { type: Boolean, default: false },
  createdAt: { type: Date, default: Date.now },
});

NotificationSchema.index({ user: 1, createdAt: -1 });

const idOf = (v) => (v && v._id ? v._id : v);

// ============================================================
// Ek user ko notification + push bhejo
// ============================================================
NotificationSchema.statics.send = async function (user, type, title, body, refType = null, refId = null) {
  try {
    if (!user) return null;

    // 1. DB mein save karo
    const notification = await this.create({
      user: idOf(user),
      type,
      title,
      body,
      refType,
      refId: idOf(refId) || null,
    });

    // 2. FCM push bhejo (async, non-blocking)
    _pushToUser(idOf(user), title, body, {
      type,
      refType: refType || '',
      refId: refId ? String(idOf(refId)) : '',
      notifId: String(notification._id),
    }).catch(() => {}); // fail hone par ignore

    return notification;
  } catch (e) {
    console.error('Notification.send failed:', e.message);
    return null;
  }
};

// ============================================================
// Bahut saare users ko notification + push bhejo
// ============================================================
NotificationSchema.statics.broadcast = async function (users, type, title, body, refType = null, refId = null) {
  try {
    const unique = [...new Set((users || []).filter(Boolean).map((u) => String(idOf(u))))];
    if (!unique.length) return [];

    // 1. DB mein sab save karo
    const notifications = await this.insertMany(
      unique.map((u) => ({ user: u, type, title, body, refType, refId: idOf(refId) || null }))
    );

    // 2. FCM push bhejo (async, non-blocking)
    _pushToUsers(unique, title, body, {
      type,
      refType: refType || '',
      refId: refId ? String(idOf(refId)) : '',
    }).catch(() => {});

    return notifications;
  } catch (e) {
    console.error('Notification.broadcast failed:', e.message);
    return [];
  }
};

// ============================================================
// Internal helpers — User model se fcmToken lao
// ============================================================

// User model ko lazily require karo (circular dependency avoid ke liye)
function getUserModel() {
  return require('./User');
}

async function _pushToUser(userId, title, body, data) {
  try {
    const User = getUserModel();
    const user = await User.findById(userId).select('fcmToken').lean();
    if (!user?.fcmToken) return;

    const result = await sendPush(user.fcmToken, { title, body, data });

    // Invalid token ho to User se remove karo
    if (result.error === 'invalid_token') {
      await User.updateOne({ _id: userId }, { $unset: { fcmToken: 1 } });
    }
  } catch (e) {
    console.error('_pushToUser error:', e.message);
  }
}

async function _pushToUsers(userIds, title, body, data) {
  try {
    const User = getUserModel();
    const users = await User.find({
      _id: { $in: userIds },
      fcmToken: { $exists: true, $ne: null, $ne: '' },
    }).select('_id fcmToken').lean();

    if (!users.length) return;

    const tokens = users.map((u) => u.fcmToken);
    const tokenToUserId = Object.fromEntries(users.map((u) => [u.fcmToken, String(u._id)]));

    // Invalid tokens ko DB se clean karo
    const cleanupFn = async (invalidTokens) => {
      await User.updateMany(
        { fcmToken: { $in: invalidTokens } },
        { $unset: { fcmToken: 1 } }
      );
    };

    await sendMulticastPush(tokens, { title, body, data }, { cleanupFn });
  } catch (e) {
    console.error('_pushToUsers error:', e.message);
  }
}

module.exports = mongoose.model('Notification', NotificationSchema);
