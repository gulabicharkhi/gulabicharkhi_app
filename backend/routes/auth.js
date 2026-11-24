const express = require('express');
const User = require('../models/User');
const { sendOtpEmail } = require('../config/emailService');
const jwt = require('jsonwebtoken');
const { protect, generateToken, getJwtSecret } = require('../middleware/authMiddleware');

const router = express.Router();

const isDev = () => process.env.NODE_ENV === 'development';
const isProd = () => process.env.NODE_ENV === 'production';

const normEmail = (e) => String(e || '').trim().toLowerCase();

// ==================== Helpers ====================

// The user object to send to Flutter
const publicUser = (user) => ({
  id: user._id,
  name: user.name,
  playerName: user.name, // alias for profile screen
  email: user.email,
  city: user.city || '',
  location: user.city || '', // alias
  phone: user.phone || '',
  dateOfBirth: user.dateOfBirth || null,
  isVerified: user.isVerified,
  profilePhoto: user.profilePhoto || null,
  federationId: user.federationId || null,
  stats: user.stats || { matches: 0, wins: 0, rank: null },
  team:
    user.team && user.team.name
      ? { id: user.team._id, name: user.team.name, tag: user.team.tag || '', inviteCode: user.team.inviteCode }
      : null,
});

// Send the OTP email. If the email fails, in dev the OTP is printed in the console
// and the response will say the email was not sent (earlier it silently showed success)
const deliverOtp = async (email, otp, name, purpose = 'verify') => {
  const result = await sendOtpEmail(email, otp, name, purpose);
  if (!result.success && !isProd()) {
    console.log(`🔑 OTP for ${email}: ${otp}   (email not sent: ${result.hint})`);
  }
  return result;
};

// OTP fields attached to the response
const otpMeta = (result, otp) => {
  const meta = { emailSent: result.success };
  if (!result.success) {
    if (!isProd()) meta.emailError = result.hint;
    if (isDev()) meta.devOtp = otp; // ONLY in development, never in production
  }
  return meta;
};

// ==================== @POST /api/auth/register ====================
router.post('/register', async (req, res) => {
  try {
    const { password, name, city } = req.body;
    const email = normEmail(req.body.email);

    if (!email || !password || !name || !String(name).trim()) {
      return res.status(400).json({
        success: false,
        message: 'Email, password, and name are required',
      });
    }

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) {
      return res.status(400).json({ success: false, message: 'Enter a valid email address' });
    }

    if (String(password).length < 6) {
      return res.status(400).json({
        success: false,
        message: 'Password must be at least 6 characters',
      });
    }

    let user = await User.findOne({ email });
    const isNewUser = !user;

    if (user && user.isVerified) {
      return res.status(409).json({
        success: false,
        message: 'Email already registered. Please sign in.',
      });
    }

    if (user) {
      // Registered earlier but not verified - update the details and send a new OTP
      user.name = String(name).trim();
      user.city = city?.trim() || '';
      user.password = password;
    } else {
      user = new User({
        name: String(name).trim(),
        email,
        password,
        city: city?.trim() || '',
      });
    }

    const otp = user.generateOtp();
    await user.save();

    const result = await deliverOtp(email, otp, user.name);

    res.status(isNewUser ? 201 : 200).json({
      success: true,
      message: result.success
        ? `OTP sent to ${email}. Please verify to complete registration.`
        : 'Account created, but OTP email could not be sent. Tap "Resend" to try again.',
      email,
      ...otpMeta(result, otp),
    });
  } catch (error) {
    if (error.name === 'ValidationError') {
      const first = Object.values(error.errors)[0];
      return res.status(400).json({ success: false, message: first.message });
    }
    console.error('Register error:', error);
    res.status(500).json({ success: false, message: 'Registration failed. Try again.' });
  }
});

// ==================== @POST /api/auth/verify-otp ====================
router.post('/verify-otp', async (req, res) => {
  try {
    const email = normEmail(req.body.email);
    const otp = req.body.otp;

    if (!email || !otp) {
      return res.status(400).json({ success: false, message: 'Email and OTP are required' });
    }

    const user = await User.findOne({ email });
    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found. Please register first.',
      });
    }

    const result = user.verifyOtp(String(otp).trim());
    if (!result.valid) {
      await user.save(); // update attempts
      return res.status(400).json({ success: false, message: result.message });
    }

    user.isVerified = true;
    await user.save();
    await user.populate('team');

    res.status(200).json({
      success: true,
      message: 'Email verified successfully! Welcome to Gulabi Charkhi!',
      token: generateToken(user._id),
      user: publicUser(user),
    });
  } catch (error) {
    console.error('OTP verify error:', error);
    res.status(500).json({ success: false, message: 'Verification failed. Try again.' });
  }
});

// ==================== @POST /api/auth/resend-otp ====================
router.post('/resend-otp', async (req, res) => {
  try {
    const email = normEmail(req.body.email);

    if (!email) {
      return res.status(400).json({ success: false, message: 'Email is required' });
    }

    const user = await User.findOne({ email });
    if (!user) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }

    if (user.isVerified) {
      return res.status(400).json({
        success: false,
        message: 'Email already verified. Please sign in.',
      });
    }

    // 25 sec cooldown to prevent spam
    if (user.otp?.sentAt && Date.now() - new Date(user.otp.sentAt).getTime() < 25 * 1000) {
      return res.status(429).json({
        success: false,
        message: 'Please wait a few seconds before requesting a new OTP.',
      });
    }

    const otp = user.generateOtp();
    await user.save();

    const result = await deliverOtp(email, otp, user.name);

    res.status(200).json({
      success: true,
      message: result.success
        ? 'New OTP sent to your email'
        : 'OTP email could not be sent. Please try again.',
      ...otpMeta(result, otp),
    });
  } catch (error) {
    console.error('Resend OTP error:', error);
    res.status(500).json({ success: false, message: 'Failed to resend OTP' });
  }
});

// ==================== @POST /api/auth/login ====================
router.post('/login', async (req, res) => {
  try {
    const email = normEmail(req.body.email);
    const { password } = req.body;

    if (!email || !password) {
      return res.status(400).json({
        success: false,
        message: 'Email and password are required',
      });
    }

    const user = await User.findOne({ email }).select('+password').populate('team');
    if (!user) {
      return res.status(401).json({ success: false, message: 'Invalid email or password' });
    }

    // Check the password first (earlier it sent the OTP without checking the password = could cause spam)
    const isMatch = await user.comparePassword(password);
    if (!isMatch) {
      return res.status(401).json({ success: false, message: 'Invalid email or password' });
    }

    if (!user.isVerified) {
      const otp = user.generateOtp();
      await user.save();
      const result = await deliverOtp(email, otp, user.name);

      return res.status(403).json({
        success: false,
        message: result.success
          ? 'Email not verified. A new OTP has been sent.'
          : 'Email not verified, and the OTP email could not be sent. Tap "Resend" on the next screen.',
        requiresVerification: true,
        email,
        ...otpMeta(result, otp),
      });
    }

    res.status(200).json({
      success: true,
      message: 'Login successful! Welcome back!',
      token: generateToken(user._id),
      user: publicUser(user),
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ success: false, message: 'Login failed. Try again.' });
  }
});

// ==================== FORGOT PASSWORD ====================
// The reset token is different from the login token: its payload has `uid`, not `id`,
// so it cannot be used to access protected routes (login).
const makeResetToken = (userId) =>
  jwt.sign({ uid: String(userId), purpose: 'password_reset' }, getJwtSecret(), {
    expiresIn: '10m',
  });

// Step 1: email do -> OTP jayega
// ==================== @POST /api/auth/forgot-password ====================
router.post('/forgot-password', async (req, res) => {
  try {
    const email = normEmail(req.body.email);
    if (!email) {
      return res.status(400).json({ success: false, message: 'Email is required' });
    }

    const user = await User.findOne({ email });
    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'No account found with this email.',
      });
    }

    if (!user.isVerified) {
      return res.status(403).json({
        success: false,
        message: 'This email is not verified yet. Please login once to verify it.',
      });
    }

    // 25 sec cooldown to prevent spam
    if (user.otp?.sentAt && Date.now() - new Date(user.otp.sentAt).getTime() < 25 * 1000) {
      return res.status(429).json({
        success: false,
        message: 'Please wait a few seconds before requesting a new OTP.',
      });
    }

    const otp = user.generateOtp();
    await user.save();

    const result = await deliverOtp(email, otp, user.name, 'reset');

    res.status(200).json({
      success: true,
      message: result.success
        ? `Password reset OTP sent to ${email}.`
        : 'OTP email could not be sent. Tap "Resend" to try again.',
      email,
      ...otpMeta(result, otp),
    });
  } catch (error) {
    console.error('Forgot password error:', error);
    res.status(500).json({ success: false, message: 'Failed to send reset OTP. Try again.' });
  }
});

// Step 2: Verify OTP -> you get a short-lived resetToken (10 min)
// ==================== @POST /api/auth/verify-reset-otp ====================
router.post('/verify-reset-otp', async (req, res) => {
  try {
    const email = normEmail(req.body.email);
    const otp = req.body.otp;
    if (!email || !otp) {
      return res.status(400).json({ success: false, message: 'Email and OTP are required' });
    }

    const user = await User.findOne({ email });
    if (!user || !user.isVerified) {
      return res.status(404).json({ success: false, message: 'User not found.' });
    }

    const result = user.verifyOtp(String(otp).trim());
    await user.save(); // save the cleared attempts / OTP
    if (!result.valid) {
      return res.status(400).json({ success: false, message: result.message });
    }

    res.status(200).json({
      success: true,
      message: 'OTP verified. Now set a new password.',
      resetToken: makeResetToken(user._id),
    });
  } catch (error) {
    console.error('Verify reset OTP error:', error);
    res.status(500).json({ success: false, message: 'Verification failed. Try again.' });
  }
});

// Step 3: Set the new password
// ==================== @POST /api/auth/reset-password ====================
router.post('/reset-password', async (req, res) => {
  try {
    const email = normEmail(req.body.email);
    const { resetToken, newPassword } = req.body;

    if (!email || !resetToken || !newPassword) {
      return res.status(400).json({
        success: false,
        message: 'Email, reset token and new password are required',
      });
    }
    if (String(newPassword).length < 6) {
      return res.status(400).json({
        success: false,
        message: 'Password must be at least 6 characters',
      });
    }

    let decoded;
    try {
      decoded = jwt.verify(String(resetToken), getJwtSecret());
    } catch (_) {
      return res.status(401).json({
        success: false,
        message: 'Reset session expired. Please start again.',
      });
    }
    if (decoded.purpose !== 'password_reset') {
      return res.status(401).json({ success: false, message: 'Invalid reset token.' });
    }

    const user = await User.findOne({ email }).select('+password');
    if (!user || String(user._id) !== decoded.uid) {
      return res.status(401).json({ success: false, message: 'Invalid reset token.' });
    }

    user.password = String(newPassword); // the pre-save hook will hash it
    await user.save();

    res.status(200).json({
      success: true,
      message: 'Password reset successful. Please login with your new password.',
    });
  } catch (error) {
    if (error.name === 'ValidationError') {
      const first = Object.values(error.errors)[0];
      return res.status(400).json({ success: false, message: first.message });
    }
    console.error('Reset password error:', error);
    res.status(500).json({ success: false, message: 'Could not reset password. Try again.' });
  }
});

// ==================== @GET /api/auth/me ====================
router.get('/me', protect, async (req, res) => {
  try {
    await req.user.populate('team');
    res.status(200).json({
      success: true,
      user: { ...publicUser(req.user), createdAt: req.user.createdAt },
    });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Server error' });
  }
});

// ==================== @POST /api/auth/logout ====================
router.post('/logout', protect, (req, res) => {
  res.status(200).json({ success: true, message: 'Logged out successfully' });
});

module.exports = router;
