const express = require('express');
const User = require('../models/User');
const { protect, generateToken } = require('../middleware/authMiddleware');

const router = express.Router();

const fail = (res, status, message) =>
  res.status(status).json({ success: false, message });

const wrap = (label, fn) => async (req, res) => {
  try {
    await fn(req, res);
  } catch (error) {
    console.error(`${label} error:`, error);
    if (!res.headersSent) fail(res, 500, 'Something went wrong. Try again.');
  }
};

// ==================== @GET /api/profile ====================
// Profile screen - full user data
router.get('/', protect, wrap('Get profile', async (req, res) => {
  const user = await User.findById(req.user._id)
    .select('name email city phone dateOfBirth profilePhoto federationId isVerified stats sessions createdAt')
    .populate('team', 'name tag inviteCode');

  if (!user) return fail(res, 404, 'User not found.');

  res.status(200).json({
    success: true,
    user: {
      id:           user._id,
      name:         user.name,
      playerName:   user.name, // alias used by the profile screen
      email:        user.email,
      city:         user.city || '',
      location:     user.city || '', // alias
      phone:        user.phone || '',
      dateOfBirth:  user.dateOfBirth || null,
      profilePhoto: user.profilePhoto || null,
      federationId: user.federationId || null,
      isVerified:   user.isVerified,
      stats:        user.stats || { matches: 0, wins: 0, rank: null },
      sessionCount: (user.sessions || []).length,
      createdAt:    user.createdAt,
      team: user.team
        ? { id: user.team._id, name: user.team.name, tag: user.team.tag, inviteCode: user.team.inviteCode }
        : null,
    },
  });
}));

// ==================== @PUT /api/profile ====================
// Profile update: name (playerName), city (location), phone, dateOfBirth
// Profile screen > Update button
router.put('/', protect, wrap('Update profile', async (req, res) => {
  // Accept playerName as name (the profile screen can send either)
  const name = req.body.name ?? req.body.playerName;
  const city = req.body.city ?? req.body.location;
  const { phone, dateOfBirth } = req.body;

  const user = await User.findById(req.user._id);
  if (!user) return fail(res, 404, 'User not found.');

  if (name !== undefined) {
    const n = String(name).trim();
    if (!n || n.length > 50) return fail(res, 400, 'Name must be 1 to 50 characters.');
    user.name = n;
  }
  if (city !== undefined) user.city  = String(city  || '').trim();
  if (phone !== undefined) user.phone = String(phone || '').trim();
  if (dateOfBirth !== undefined) {
    const d = dateOfBirth ? new Date(dateOfBirth) : null;
    if (dateOfBirth && isNaN(d?.getTime())) return fail(res, 400, 'Invalid date of birth.');
    user.dateOfBirth = d;
  }

  await user.save();
  await user.populate('team', 'name tag inviteCode');

  res.status(200).json({
    success: true,
    message: 'Profile updated.',
    user: {
      id:           user._id,
      name:         user.name,
      playerName:   user.name,
      email:        user.email,
      city:         user.city || '',
      location:     user.city || '',
      phone:        user.phone || '',
      dateOfBirth:  user.dateOfBirth || null,
      profilePhoto: user.profilePhoto || null,
      federationId: user.federationId || null,
      isVerified:   user.isVerified,
      stats:        user.stats || { matches: 0, wins: 0, rank: null },
      team: user.team
        ? { id: user.team._id, name: user.team.name, tag: user.team.tag, inviteCode: user.team.inviteCode }
        : null,
    },
  });
}));

// ==================== @PUT /api/profile/photo ====================
// Profile photo update
// body: { photo: "data:image/jpeg;base64,..." or URL }
router.put('/photo', protect, wrap('Update photo', async (req, res) => {
  const { photo } = req.body;

  if (photo !== null && photo !== undefined) {
    if (typeof photo !== 'string') return fail(res, 400, 'Invalid photo.');
    // Allow null (remove), URL, or a small base64 (~200KB max)
    if (photo !== '' && !photo.startsWith('http') && !photo.startsWith('data:image')) {
      return fail(res, 400, 'Photo must be a URL or base64 image.');
    }
    if (photo.startsWith('data:image') && photo.length > 280000) {
      return fail(res, 400, 'Photo too large. Maximum ~200KB allowed.');
    }
  }

  await User.updateOne({ _id: req.user._id }, { $set: { profilePhoto: photo || null } });

  res.status(200).json({
    success: true,
    message: 'Profile photo updated.',
    profilePhoto: photo || null,
  });
}));

// ==================== @GET /api/profile/sessions ====================
// Active sessions list (Profile screen > Active sessions)
router.get('/sessions', protect, wrap('Sessions', async (req, res) => {
  const user = await User.findById(req.user._id).select('sessions');

  res.status(200).json({
    success: true,
    sessions: (user.sessions || []).map((s) => ({
      device:   s.device,
      loginAt:  s.loginAt,
      lastSeen: s.lastSeen,
    })),
  });
}));

// ==================== @DELETE /api/profile/sessions ====================
// Logout from all sessions (token-based - the frontend should delete the tokens)
router.delete('/sessions', protect, wrap('Clear sessions', async (req, res) => {
  await User.updateOne({ _id: req.user._id }, { $set: { sessions: [] } });
  res.status(200).json({ success: true, message: 'All sessions cleared. Please login again.' });
}));

// ==================== @GET /api/profile/home ====================
// Home screen user card data: name, city, stats (matches, wins, rank), team
router.get('/home', protect, wrap('Home profile', async (req, res) => {
  const user = await User.findById(req.user._id)
    .select('name city profilePhoto stats team federationId')
    .populate('team', 'name tag');

  res.status(200).json({
    success: true,
    user: {
      id:           user._id,
      name:         user.name,
      city:         user.city || '',
      profilePhoto: user.profilePhoto || null,
      stats: {
        matches: user.stats?.matches || 0,
        wins:    user.stats?.wins    || 0,
        rank:    user.stats?.rank    || null,
      },
      team: user.team ? { id: user.team._id, name: user.team.name, tag: user.team.tag } : null,
      federationId: user.federationId || null,
    },
  });
}));

module.exports = router;
