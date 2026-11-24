const jwt = require('jsonwebtoken');
const User = require('../models/User');

// Token banane aur verify karne ke liye EK hi secret (pehle dono jagah alag the,
// .env na milne par token ban jata tha lekin verify fail ho jata tha)
const getJwtSecret = () => process.env.JWT_SECRET || 'gulabi_charkhi_secret_key_2024';

const generateToken = (userId) =>
  jwt.sign({ id: userId }, getJwtSecret(), {
    expiresIn: process.env.JWT_EXPIRES_IN || '30d',
  });

const protect = async (req, res, next) => {
  try {
    let token;

    if (req.headers.authorization?.startsWith('Bearer ')) {
      token = req.headers.authorization.split(' ')[1];
    }

    if (!token) {
      return res.status(401).json({
        success: false,
        message: 'Not authorized. Please login first.',
      });
    }

    const decoded = jwt.verify(token, getJwtSecret());

    const user = await User.findById(decoded.id).select('-password').populate('team', 'name tag inviteCode');
    if (!user) {
      return res.status(401).json({
        success: false,
        message: 'User not found. Please login again.',
      });
    }

    req.user = user;
    next();
  } catch (error) {
    if (error.name === 'JsonWebTokenError') {
      return res.status(401).json({ success: false, message: 'Invalid token.' });
    }
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({ success: false, message: 'Token expired. Please login again.' });
    }
    console.error('Auth middleware error:', error);
    res.status(500).json({ success: false, message: 'Server error' });
  }
};

module.exports = { protect, generateToken, getJwtSecret };
