# Invite Link Setup Guide

## Problem
`gulabi.charkhi` domain exist nahi karta — isliye link browser mein open nahi hota.

## Solution: 2 options

---

### Option A — Sirf Code Share Karo (Easiest, abhi karo)
`.env` mein set karo:
```
APP_INVITE_BASE_URL=gulabicharkhi://join
WEB_INVITE_BASE_URL=http://YOUR_SERVER_IP:5000/join
```
Share hoga: `gulabicharkhi://join/RHVJWH`
- App installed hai to seedha khulega
- Browser mein kholne se `/join/CODE` page dikhega (server pe)

---

### Option B — Real Domain (Production ke liye)
1. Domain kharido (e.g. `gulabicharkhi.app`)
2. `.env` mein:
```
WEB_INVITE_BASE_URL=https://gulabicharkhi.app/join
APP_INVITE_BASE_URL=gulabicharkhi://join
```

---

## Flutter Deep Link Setup

### Android — `android/app/src/main/AndroidManifest.xml`
`<activity>` ke andar add karo:
```xml
<!-- Custom scheme: gulabicharkhi://join/CODE -->
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="gulabicharkhi" android:host="join" />
</intent-filter>

<!-- HTTP fallback: https://yourdomain.com/join/CODE -->
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="https"
          android:host="yourdomain.com"
          android:pathPrefix="/join" />
</intent-filter>
```

### iOS — `ios/Runner/Info.plist`
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>gulabicharkhi</string>
    </array>
  </dict>
</array>
```

---

## pubspec.yaml mein add karo
```yaml
dependencies:
  app_links: ^6.3.2
  mobile_scanner: ^5.2.3  # QR scan ke liye
```

## main.dart mein uncomment karo
`_initDeepLinks()` function mein `AppLinks()` wala commented code uncomment karo.

---

## Abhi Test Karo (Local)
1. Backend chal raha ho
2. Phone ko same WiFi pe rakho
3. `.env` mein: `WEB_INVITE_BASE_URL=http://192.168.1.X:5000/join`
4. Browser mein: `http://192.168.1.X:5000/join/RHVJWH`
   → Pink page dikhega with "App mein kholein" button
