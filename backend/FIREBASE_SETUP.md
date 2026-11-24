# 🔥 Firebase Push Notifications — Complete Setup Guide
## Gulabi Charkhi App

---

## OVERVIEW: What changed

| File | Status | What changed |
|------|--------|--------------|
| `config/firebase.js` | 🆕 NEW | Firebase Admin SDK wrapper |
| `models/User.js` | ✏️ UPDATE | Added the `fcmToken` field |
| `models/Notification.js` | ✏️ UPDATE | `.send()` and `.broadcast()` now also send push |
| `routes/notifications.js` | ✏️ UPDATE | 2 new routes: `POST /fcm-token`, `DELETE /fcm-token` |
| `server.js` | ✏️ UPDATE | Added the `initFirebase()` call |
| `lib/services/notification_service.dart` | 🆕 NEW | Flutter FCM service |
| `main.dart` | ✏️ PATCH | Firebase.initializeApp + NotificationService.init |

---

## STEP 1: Firebase Project Setup (5 min)

1. Open the **Firebase Console**: https://console.firebase.google.com
2. Create a **New Project** → "gulabi-charkhi" (or add to an existing one)
3. **Enable Cloud Messaging**:
   - Project Settings → Cloud Messaging → Enable

---

## STEP 2: Android Setup

### 2.1 — Add google-services.json
1. Firebase Console → Project Settings → Your Apps → click the Android icon
2. Package name: `com.gulabicharkhi.app` (enter your actual package name)
3. Download `google-services.json`
4. Put it in `android/app/google-services.json`

### 2.2 — Update build.gradle

**android/build.gradle** (project level):
```gradle
buildscript {
    dependencies {
        // add after the existing ones:
        classpath 'com.google.gms:google-services:4.4.0'
    }
}
```

**android/app/build.gradle** (app level):
```gradle
// Add at the end of the file:
apply plugin: 'com.google.gms.google-services'
```

### 2.3 — Add the channel in AndroidManifest.xml

Inside the `<application>` tag of `android/app/src/main/AndroidManifest.xml`:
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

1. Firebase Console → Project Settings → Your Apps → click the iOS icon
2. Bundle ID: `com.gulabicharkhi.app`
3. Download `GoogleService-Info.plist`
4. In Xcode, add it at `Runner/GoogleService-Info.plist`
5. Xcode → Target → Signing & Capabilities → "+" → add Push Notifications
6. Background Modes → check "Remote notifications"

---

## STEP 4: Flutter pubspec.yaml

```yaml
dependencies:
  firebase_core: ^3.6.0
  firebase_messaging: ^15.1.3
  flutter_local_notifications: ^18.0.1
```

Then run:
```bash
flutter pub get
```

---

## STEP 5: Generate firebase_options.dart with the FlutterFire CLI

```bash
# Install the FlutterFire CLI (one time)
dart pub global activate flutterfire_cli

# Log in with the Firebase CLI
firebase login

# Configure the project (run from the project root)
flutterfire configure --project=gulabi-charkhi
```

This will automatically generate `lib/firebase_options.dart`.

---

## STEP 6: Backend Service Account

### 6.1 — Generate the key
1. Firebase Console → Project Settings → Service Accounts
2. "Generate new private key" → a JSON file will be downloaded
3. File name: `firebase-service-account.json`

### 6.2 — Add it to the backend

**Local development:**
```bash
# Keep it in the backend folder (add it to .gitignore!)
cp ~/Downloads/firebase-service-account.json backend/firebase-service-account.json

# Add it to .gitignore:
echo "firebase-service-account.json" >> backend/.gitignore
```

**Production (Render/Railway/Heroku):**
```bash
# Convert the JSON into a single line:
cat firebase-service-account.json | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d))"

# Then paste that output into the FIREBASE_SERVICE_ACCOUNT_JSON env variable
```

### 6.3 — Install the firebase-admin package
```bash
cd backend
npm install firebase-admin
```

---

## STEP 7: Replace the Backend Files

```bash
# Back up the existing files
cp backend/models/User.js backend/models/User.js.backup
cp backend/models/Notification.js backend/models/Notification.js.backup
cp backend/routes/notifications.js backend/routes/notifications.js.backup
cp backend/server.js backend/server.js.backup

# Copy the new files (from this package)
cp backend_firebase/config/firebase.js backend/config/firebase.js
cp backend_firebase/models/User.js backend/models/User.js
cp backend_firebase/models/Notification.js backend/models/Notification.js
cp backend_firebase/routes/notifications.js backend/routes/notifications.js
cp backend_firebase/server.js backend/server.js
```

---

## STEP 8: Add the Flutter Files

```bash
cp backend_firebase/lib_additions/notification_service.dart lib/services/notification_service.dart
```

Then make these changes in `main.dart` (see main_fcm_patch.dart):
1. Add `Firebase.initializeApp()`
2. Add `NotificationService.init()`
3. Add `NotificationService.registerToken()` in `AuthService.login()`
4. Add `NotificationService.clearToken()` on logout

---

## STEP 9: Test

### Backend test:
```bash
cd backend
node server.js
# The console should show: "🔥 Firebase Admin SDK initialized — push notifications ENABLED"
```

### Flutter test:
```bash
flutter run
# Log in → in your Firebase Console → Engage → Messaging → send a Test message
```

### API test (Postman/curl):
```bash
# After logging in, take the token:
curl -X POST http://localhost:5000/api/notifications/fcm-token \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"token": "DEVICE_FCM_TOKEN"}'
# Response: {"success": true, "message": "FCM token saved."}
```

---

## Notification Types (reference)

These notifications are sent in battles:

| Type | Trigger | Receiver |
|------|---------|----------|
| `battle_challenge` | Challenge sent | Opponent captain |
| `battle_accepted` | Challenge accepted | Challenger captain |
| `battle_rejected` | Challenge rejected | Challenger captain |
| `battle_cancelled` | Battle cancelled | Captain of the other side |
| `battle_started` | Both ready → LIVE | All members of both teams |
| `cut_claimed` | Kite cut claimed | Opponent captain |
| `cut_approved` | Cut approved | Claiming captain |
| `cut_rejected` | Cut rejected | Claiming captain |
| `battle_ended` | Battle ended | All members of both teams |

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Firebase not ready" | Check the service account JSON — is it valid? |
| Notification does not arrive on Android | Check `google-services.json`, check the build.gradle plugins |
| Notification does not arrive on iOS | Check the APNs certificate, check the capabilities |
| "invalid_token" error | The user has probably uninstalled the app — the token is auto-cleared |
| Notification does not arrive in the background | Check the AndroidManifest channel ID |

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
