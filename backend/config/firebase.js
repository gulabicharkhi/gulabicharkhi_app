// ============================================================
// Firebase Admin SDK Initializer
// config/firebase.js
// ============================================================

const { initializeApp, cert } = require('firebase-admin/app');
const { getMessaging: getAdminMessaging } = require('firebase-admin/messaging');
const path = require('path');
const fs   = require('fs');

let _initialized = false;
let _messaging   = null;

function initFirebase() {
  if (_initialized) return _messaging;

  try {
    let serviceAccount;

    // Option A: JSON directly in env (best for Render / Railway / Heroku deployment)
    if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
      serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
    }
    // Option B: File path in env
    else if (process.env.FIREBASE_SERVICE_ACCOUNT_PATH) {
      const filePath = path.resolve(process.env.FIREBASE_SERVICE_ACCOUNT_PATH);
      serviceAccount = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    }
    // Option C: Default path (kept in the backend/ folder)
    else {
      const defaultPath = path.join(__dirname, '..', 'firebase-service-account.json');
      if (fs.existsSync(defaultPath)) {
        serviceAccount = JSON.parse(fs.readFileSync(defaultPath, 'utf8'));
      }
    }

    if (!serviceAccount) {
      console.warn('⚠️  Firebase: Service account not found. Push notifications will be DISABLED.');
      console.warn('   For setup, see docs/FIREBASE_SETUP.md');
      return null;
    }

    const app = initializeApp({
      credential: cert(serviceAccount),
    });

    _messaging   = getAdminMessaging(app);
    _initialized = true;
    console.log('🔥 Firebase Admin SDK initialized — push notifications ENABLED');
    return _messaging;

  } catch (err) {
    console.error('❌ Firebase init failed:', err.message);
    console.warn('   Push notifications DISABLED rahenge (baaki sab kaam karega)');
    return null;
  }
}

// Get the messaging instance lazily
function getMessaging() {
  if (_initialized) return _messaging;
  return initFirebase();
}

// ============================================================
// Send a push notification (single token)
// Returns: { success: true } | { success: false, error }
// ============================================================
async function sendPush(fcmToken, { title, body, data = {} }) {
  const messaging = getMessaging();
  if (!messaging || !fcmToken) return { success: false, error: 'Firebase not ready or no token' };

  try {
    const message = {
      token: fcmToken,
      notification: { title: String(title), body: String(body) },
      data: Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, String(v)])
      ),
      android: {
        priority: 'high',
        notification: {
          channelId: 'gulabi_battles',
          sound: 'default',
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
          },
        },
      },
    };

    await messaging.send(message);
    return { success: true };
  } catch (err) {
    // Silently ignore an invalid token (the user has probably uninstalled the app)
    if (err.code === 'messaging/registration-token-not-registered' ||
        err.code === 'messaging/invalid-registration-token') {
      return { success: false, error: 'invalid_token', code: err.code };
    }
    console.error('FCM sendPush error:', err.message);
    return { success: false, error: err.message };
  }
}

// ============================================================
// Multicast push (many tokens at once — max 500 per call)
// Automatically cleans up invalid tokens
// ============================================================
async function sendMulticastPush(fcmTokens, { title, body, data = {} }, { cleanupFn } = {}) {
  const messaging = getMessaging();
  if (!messaging || !fcmTokens?.length) return { success: false, error: 'No tokens' };

  const unique = [...new Set(fcmTokens.filter(Boolean))];
  if (!unique.length) return { success: true, sent: 0 };

  const BATCH = 500;
  let totalSent = 0;
  const invalidTokens = [];

  for (let i = 0; i < unique.length; i += BATCH) {
    const batch = unique.slice(i, i + BATCH);
    try {
      const message = {
        tokens: batch,
        notification: { title: String(title), body: String(body) },
        data: Object.fromEntries(
          Object.entries(data).map(([k, v]) => [k, String(v)])
        ),
        android: {
          priority: 'high',
          notification: {
            channelId: 'gulabi_battles',
            sound: 'default',
            clickAction: 'FLUTTER_NOTIFICATION_CLICK',
          },
        },
        apns: {
          payload: { aps: { sound: 'default', badge: 1 } },
        },
      };

      const response = await messaging.sendEachForMulticast(message);
      totalSent += response.successCount;

      // Collect invalid tokens
      response.responses.forEach((r, idx) => {
        if (!r.success) {
          const code = r.error?.code || '';
          if (code === 'messaging/registration-token-not-registered' ||
              code === 'messaging/invalid-registration-token') {
            invalidTokens.push(batch[idx]);
          }
        }
      });
    } catch (err) {
      console.error('FCM multicast error:', err.message);
    }
  }

  // Remove invalid tokens from the DB (if a cleanup function was provided)
  if (invalidTokens.length && cleanupFn) {
    try { await cleanupFn(invalidTokens); } catch (e) { /* silent */ }
  }

  return { success: true, sent: totalSent, invalidTokens };
}

module.exports = { initFirebase, getMessaging, sendPush, sendMulticastPush };
