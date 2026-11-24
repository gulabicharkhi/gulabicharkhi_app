// ============================================================
// Notifications Routes — UPDATED
// routes/notifications.js
//
// The old routes are the same.
// NEW route: POST /api/notifications/fcm-token
//   → The Flutter app registers/updates its FCM token here
// ============================================================

const express = require('express');
const Notification = require('../models/Notification');
const User = require('../models/User');
const { protect } = require('../middleware/authMiddleware');

const router = express.Router();

const fail = (res, status, message) =>
  res.status(status).json({ success: false, message });

// ==================== @POST /api/notifications/fcm-token ====================
// The Flutter app saves its FCM token here.
// When to call:
//   - When the app opens (main.dart or dashboard initState)
//   - After login
//   - In the FirebaseMessaging.instance.onTokenRefresh stream
// body: { token: "FCM_TOKEN_STRING" }

router.post('/fcm-token', protect, async (req, res) => {
  try {
    const { token } = req.body;

    if (!token || typeof token !== 'string' || token.trim().length < 10) {
      return fail(res, 400, 'Valid FCM token required.');
    }

    await User.findByIdAndUpdate(
      req.user._id,
      { fcmToken: token.trim() },
      { new: false }
    );

    res.status(200).json({ success: true, message: 'FCM token saved.' });
  } catch (error) {
    console.error('FCM token save error:', error);
    fail(res, 500, 'Could not save FCM token.');
  }
});

// ==================== @DELETE /api/notifications/fcm-token ====================
// Clear the token on logout so that no push arrives

router.delete('/fcm-token', protect, async (req, res) => {
  try {
    await User.findByIdAndUpdate(req.user._id, { $unset: { fcmToken: 1 } });
    res.status(200).json({ success: true, message: 'FCM token cleared.' });
  } catch (error) {
    fail(res, 500, 'Could not clear FCM token.');
  }
});

// ==================== @GET /api/notifications ====================
// All notifications of the user (newest first)
// ?page=1&limit=20&unreadOnly=true

router.get('/', protect, async (req, res) => {
  try {
    const page       = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit      = Math.min(50, Math.max(1, parseInt(req.query.limit, 10) || 20));
    const unreadOnly = req.query.unreadOnly === 'true';

    const filter = { user: req.user._id };
    if (unreadOnly) filter.read = false;

    const [notifications, total, unreadCount] = await Promise.all([
      Notification.find(filter)
        .sort({ createdAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit),
      Notification.countDocuments(filter),
      Notification.countDocuments({ user: req.user._id, read: false }),
    ]);

    res.status(200).json({
      success: true,
      page,
      total,
      unreadCount,
      hasMore: page * limit < total,
      notifications: notifications.map((n) => ({
        id:        n._id,
        type:      n.type,
        title:     n.title,
        body:      n.body,
        refType:   n.refType,
        refId:     n.refId,
        read:      n.read,
        createdAt: n.createdAt,
      })),
    });
  } catch (error) {
    console.error('Get notifications error:', error);
    fail(res, 500, 'Could not fetch notifications.');
  }
});

// ==================== @POST /api/notifications/read-all ====================
// Mark all notifications as read

router.post('/read-all', protect, async (req, res) => {
  try {
    await Notification.updateMany(
      { user: req.user._id, read: false },
      { $set: { read: true } }
    );
    res.status(200).json({ success: true, message: 'All notifications marked as read.' });
  } catch (error) {
    fail(res, 500, 'Failed to mark notifications.');
  }
});

// ==================== @POST /api/notifications/:id/read ====================
// Mark one notification as read

router.post('/:id/read', protect, async (req, res) => {
  try {
    await Notification.updateOne(
      { _id: req.params.id, user: req.user._id },
      { $set: { read: true } }
    );
    res.status(200).json({ success: true });
  } catch (error) {
    fail(res, 500, 'Failed.');
  }
});

// ==================== @DELETE /api/notifications/clear ====================
// Delete all read notifications

router.delete('/clear', protect, async (req, res) => {
  try {
    await Notification.deleteMany({ user: req.user._id, read: true });
    res.status(200).json({ success: true, message: 'Read notifications cleared.' });
  } catch (error) {
    fail(res, 500, 'Failed.');
  }
});

module.exports = router;
