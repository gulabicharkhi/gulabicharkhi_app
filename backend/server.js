// ============================================================
// server.js — UPDATED: Firebase Admin SDK is initialized on startup
// ============================================================

const express  = require('express');
const mongoose = require('mongoose');
const cors     = require('cors');
const dotenv   = require('dotenv');

dotenv.config();

const { verifyEmailSetup } = require('./config/emailService');
const { initFirebase }     = require('./config/firebase'); // <-- NEW

const app = express();

// ==================== MIDDLEWARE ====================
app.use(express.json({ limit: '2mb' }));
app.use(cors({
  origin: '*',
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// ==================== DATABASE ====================
mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/gulabi_charkhi')
  .then(() => console.log('✅ MongoDB connected'))
  .catch(err => console.error('❌ MongoDB error:', err));

// ==================== FIREBASE INIT ====================
initFirebase(); // set up push notifications

// ==================== ROUTES ====================
app.use('/api/auth',          require('./routes/auth'));
app.use('/api/teams',         require('./routes/teams'));
app.use('/api/battles',       require('./routes/battles'));
app.use('/api/associations',  require('./routes/associations'));
app.use('/api/notifications', require('./routes/notifications')); // updated version
app.use('/api/profile',       require('./routes/profile'));
app.use('/api/search',        require('./routes/search'));

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'OK', app: 'Gulabi Charkhi API', time: new Date() });
});

// ==================== WEB INVITE LINK ====================
app.get('/join/:code', (req, res) => {
  const code = String(req.params.code || '').trim().toUpperCase();
  if (!code || !/^[A-Z0-9]{4,8}$/.test(code)) {
    return res.status(400).send('Invalid invite code.');
  }

  const appDeepLink = `gulabicharkhi://join/${code}`;
  const appName     = process.env.APP_NAME || 'Gulabi Charkhi';
  const playStoreUrl = process.env.PLAY_STORE_URL || '#';
  const appStoreUrl  = process.env.APP_STORE_URL  || '#';

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Join Team • ${appName}</title>
  <style>
    * { margin:0; padding:0; box-sizing:border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: linear-gradient(135deg, #E93D95, #A64CF5);
      min-height: 100vh; display:flex; align-items:center;
      justify-content:center; padding:24px;
    }
    .card { background:white; border-radius:24px; padding:36px 28px;
      max-width:360px; width:100%; text-align:center;
      box-shadow:0 20px 60px rgba(0,0,0,0.2); }
    .logo { font-size:48px; margin-bottom:8px; }
    h1 { font-size:22px; font-weight:900; color:#1A1A1A; margin-bottom:4px; }
    .sub { font-size:14px; color:#888; margin-bottom:24px; }
    .code-box { background:#FDE8F1; border-radius:14px; padding:16px;
      font-size:28px; font-weight:900; letter-spacing:8px;
      color:#E93D95; margin-bottom:24px; }
    .btn { display:block; width:100%; padding:15px; border-radius:14px;
      font-size:15px; font-weight:800; text-decoration:none;
      cursor:pointer; border:none; margin-bottom:10px; }
    .btn-primary { background:linear-gradient(90deg,#E93D95,#A64CF5); color:white; }
    .btn-outline { background:white; border:2px solid #E93D95; color:#E93D95; font-size:13px; }
    .divider { color:#CCC; font-size:12px; margin:8px 0 14px; }
    .stores { display:flex; gap:10px; }
    .stores a { flex:1; }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">🪁</div>
    <h1>${appName}</h1>
    <p class="sub">You have been invited to join a team</p>
    <div class="code-box">${code}</div>
    <a class="btn btn-primary" id="openApp" href="${appDeepLink}">Open in App</a>
    <p class="divider">— Don't have the app? —</p>
    <div class="stores">
      <a href="${playStoreUrl}" class="btn btn-outline">📱 Play Store</a>
      <a href="${appStoreUrl}"  class="btn btn-outline">🍎 App Store</a>
    </div>
  </div>
  <script>
    setTimeout(function() {
      document.getElementById('openApp').href = '${appDeepLink}';
    }, 100);
  </script>
</body>
</html>`);
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({ success: false, message: 'Route not found' });
});

// Error handler
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ success: false, message: 'Server error' });
});

// ==================== START ====================
const PORT = process.env.PORT || 5000;
app.listen(PORT, '0.0.0.0', async () => {

  console.log(`🚀 Gulabi Charkhi API running on port ${PORT}`);
  await verifyEmailSetup();
});
