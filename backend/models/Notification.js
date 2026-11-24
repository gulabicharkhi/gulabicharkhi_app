// ============================================================
// Notification Model — UPDATED with Firebase Push Support
// models/Notification.js
//
// The old model behaviour is exactly the SAME.
// New feature: .send() and .broadcast() now also send FCM push.
//
// Flow:
//  1. The notification is saved in the DB (as before)
//  2. The user's fcmToken is fetched (from the User model)
//  3. The push is sent via Firebase
//  4. If the push fails, the main operation still does not fail
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
// Send a notification + push to one user
// ============================================================
NotificationSchema.statics.send = async function (user, type, title, body, refType = null, refId = null) {
  try {
    if (!user) return null;

    // 1. Save in the DB
    const notification = await this.create({
      user: idOf(user),
      type,
      title,
      body,
      refType,
      refId: idOf(refId) || null,
    });

    // 2. Send the FCM push (async, non-blocking)
    _pushToUser(idOf(user), title, body, {
      type,
      refType: refType || '',
      refId: refId ? String(idOf(refId)) : '',
      notifId: String(notification._id),
    }).catch(() => {}); // ignore on failure

    return notification;
  } catch (e) {
    console.error('Notification.send failed:', e.message);
    return null;
  }
};

// ============================================================
// Send a notification + push to many users
// ============================================================
NotificationSchema.statics.broadcast = async function (users, type, title, body, refType = null, refId = null) {
  try {
    const unique = [...new Set((users || []).filter(Boolean).map((u) => String(idOf(u))))];
    if (!unique.length) return [];

    // 1. Save all in the DB
    const notifications = await this.insertMany(
      unique.map((u) => ({ user: u, type, title, body, refType, refId: idOf(refId) || null }))
    );

    // 2. Send the FCM push (async, non-blocking)
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
// Internal helpers — get fcmToken from the User model
// ============================================================

// Require the User model lazily (to avoid a circular dependency)
function getUserModel() {
  return require('./User');
}

async function _pushToUser(userId, title, body, data) {
  try {
    const User = getUserModel();
    const user = await User.findById(userId).select('fcmToken').lean();
    if (!user?.fcmToken) return;

    const result = await sendPush(user.fcmToken, { title, body, data });

    // If the token is invalid, remove it from the User
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

    // Clean invalid tokens from the DB
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
