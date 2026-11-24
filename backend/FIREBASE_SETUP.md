# 🔥 Firebase Push Notifications — Complete Setup Guide
## Gulabi Charkhi App

---

## OVERVIEW: Kya-kya change hua

| File | Status | Kya badla |
|------|--------|-----------|
| `config/firebase.js` | 🆕 NAYA | Firebase Admin SDK wrapper |
| `models/User.js` | ✏️ UPDATE | `fcmToken` field add kiya |
| `models/Notification.js` | ✏️ UPDATE | `.send()` aur `.broadcast()` ab push bhi bhejte hain |
| `routes/notifications.js` | ✏️ UPDATE | 2 naye routes: `POST /fcm-token`, `DELETE /fcm-token` |
| `server.js` | ✏️ UPDATE | `initFirebase()` call add kiya |
| `lib/services/notification_service.dart` | 🆕 NAYA | Flutter FCM service |
| `main.dart` | ✏️ PATCH | Firebase.initializeApp + NotificationService.init |

---

## STEP 1: Firebase Project Setup (5 min)

1. **Firebase Console** kholo: https://console.firebase.google.com
2. **New Project** banao → "gulabi-charkhi" (ya existing mein add karo)
3. **Cloud Messaging enable karo**:
   - Project Settings → Cloud Messaging → Enable

---

## STEP 2: Android Setup

### 2.1 — google-services.json add karo
1. Firebase Console → Project Settings → Your Apps → Android icon click karo
2. Package name: `com.gulabicharkhi.app` (apna actual package name daalo)
3. `google-services.json` download karo
4. `android/app/google-services.json` mein rakho

### 2.2 — build.gradle update karo

**android/build.gradle** (project level):
```gradle
buildscript {
    dependencies {
        // existing ke baad add karo:
        classpath 'com.google.gms:google-services:4.4.0'
    }
}
```

**android/app/build.gradle** (app level):
```gradle
// File ke end mein add karo:
apply plugin: 'com.google.gms.google-services'
```

### 2.3 — AndroidManifest.xml mein channel add karo

`android/app/src/main/AndroidManifest.xml` mein `<application>` tag ke andar:
```xml
<meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="gulabi_battles" />
<meta-data
    android:name="com.google.firebase.messaging.default_notification_icon"
    android:resource="@mipmap/ic_launcher" />
```

---

## STEP 3: iOS Setup

1. Firebase Console → Project Settings → Your Apps → iOS icon click karo
2. Bundle ID: `com.gulabicharkhi.app`
3. `GoogleService-Info.plist` download karo
4. Xcode mein `Runner/GoogleService-Info.plist` mein add karo
5. Xcode → Target → Signing & Capabilities → "+" → Push Notifications add karo
6. Background Modes → "Remote notifications" check karo

---

## STEP 4: Flutter pubspec.yaml

```yaml
dependencies:
  firebase_core: ^3.6.0
  firebase_messaging: ^15.1.3
  flutter_local_notifications: ^18.0.1
```

Phir run karo:
```bash
flutter pub get
```

---

## STEP 5: FlutterFire CLI se firebase_options.dart generate karo

```bash
# FlutterFire CLI install karo (ek baar)
dart pub global activate flutterfire_cli

# Firebase CLI se login karo
firebase login

# Project configure karo (project ke root se chalao)
flutterfire configure --project=gulabi-charkhi
```

Yeh automatically `lib/firebase_options.dart` generate karega.

---

## STEP 6: Backend Service Account

### 6.1 — Key generate karo
1. Firebase Console → Project Settings → Service Accounts
2. "Generate new private key" → JSON file download hogi
3. File ka naam: `firebase-service-account.json`

### 6.2 — Backend mein add karo

**Local development:**
```bash
# Backend folder mein rakho (gitignore mein add karo!)
cp ~/Downloads/firebase-service-account.json backend/firebase-service-account.json

# .gitignore mein add karo:
echo "firebase-service-account.json" >> backend/.gitignore
```

**Production (Render/Railway/Heroku):**
```bash
# JSON ko ek line mein convert karo:
cat firebase-service-account.json | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d))"

# Phir us output ko FIREBASE_SERVICE_ACCOUNT_JSON env variable mein paste karo
```

### 6.3 — firebase-admin package install karo
```bash
cd backend
npm install firebase-admin
```

---

## STEP 7: Backend Files Replace karo

```bash
# Existing files backup karo
cp backend/models/User.js backend/models/User.js.backup
cp backend/models/Notification.js backend/models/Notification.js.backup
cp backend/routes/notifications.js backend/routes/notifications.js.backup
cp backend/server.js backend/server.js.backup

# Naye files copy karo (is package se)
cp backend_firebase/config/firebase.js backend/config/firebase.js
cp backend_firebase/models/User.js backend/models/User.js
cp backend_firebase/models/Notification.js backend/models/Notification.js
cp backend_firebase/routes/notifications.js backend/routes/notifications.js
cp backend_firebase/server.js backend/server.js
```

---

## STEP 8: Flutter Files Add karo

```bash
cp backend_firebase/lib_additions/notification_service.dart lib/services/notification_service.dart
```

Phir `main.dart` mein ye changes karo (main_fcm_patch.dart dekho):
1. `Firebase.initializeApp()` add karo
2. `NotificationService.init()` add karo
3. `AuthService.login()` mein `NotificationService.registerToken()` add karo
4. Logout mein `NotificationService.clearToken()` add karo

---

## STEP 9: Test karo

### Backend test:
```bash
cd backend
node server.js
# Console mein: "🔥 Firebase Admin SDK initialized — push notifications ENABLED" dikhna chahiye
```

### Flutter test:
```bash
flutter run
# Login karo → apne Firebase Console → Engage → Messaging → Test message bhejo
```

### API test (Postman/curl):
```bash
# Login ke baad token leke:
curl -X POST http://localhost:5000/api/notifications/fcm-token \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"token": "DEVICE_FCM_TOKEN"}'
# Response: {"success": true, "message": "FCM token saved."}
```

---

## Notification Types (reference)

Battles mein ye notifications jaati hain:

| Type | Trigger | Receiver |
|------|---------|----------|
| `battle_challenge` | Challenge bheja | Opponent captain |
| `battle_accepted` | Challenge accept kiya | Challenger captain |
| `battle_rejected` | Challenge reject kiya | Challenger captain |
| `battle_cancelled` | Battle cancel kiya | Dusri side ka captain |
| `battle_started` | Dono ready → LIVE | Dono teams ke sare members |
| `cut_claimed` | Kite cut claim kiya | Opponent captain |
| `cut_approved` | Cut approve kiya | Claiming captain |
| `cut_rejected` | Cut reject kiya | Claiming captain |
| `battle_ended` | Battle end | Dono teams ke sare members |

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Firebase not ready" | Service account JSON check karo — valid hai? |
| Android par notification nahi aati | `google-services.json` check karo, build.gradle plugins check karo |
| iOS par notification nahi aati | APNs certificate check karo, capabilities check karo |
| "invalid_token" error | User ne app uninstall kiya hoga — token auto-clear ho jata hai |
| Background mein notification nahi aati | AndroidManifest channel ID check karo |

---

## Package.json (backend dependencies)

```json
{
  "dependencies": {
    "firebase-admin": "^12.0.0"
  }
}
```

Install:
```bash
npm install firebase-admin
```
