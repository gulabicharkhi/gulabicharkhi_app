# 🪁 Gulabi Charkhi - Kite Battle Arena

## Project Structure (Folder Structure)

```
gulabi_charkhi/
├── flutter_app/              ← Flutter Frontend
│   ├── lib/
│   │   ├── main.dart         ← App entry point
│   │   ├── screens/
│   │   │   ├── splash_screen.dart    ← Splash / Loading screen
│   │   │   ├── login_screen.dart     ← Login screen
│   │   │   ├── register_screen.dart  ← Register screen
│   │   │   ├── otp_screen.dart       ← OTP verify screen (6 boxes)
│   │   │   └── dashboard_screen.dart ← Main home dashboard
│   │   ├── services/
│   │   │   └── auth_service.dart     ← API calls (login/register/OTP)
│   │   └── utils/
│   │       └── app_theme.dart        ← Colors, theme, GradientButton
│   └── pubspec.yaml
│
└── backend/                  ← Node.js Backend
    ├── server.js             ← Main server
    ├── routes/
    │   └── auth.js           ← Login/Register/OTP routes
    ├── models/
    │   └── User.js           ← MongoDB User model
    ├── middleware/
    │   └── authMiddleware.js ← JWT protect middleware
    ├── config/
    │   └── emailService.js   ← Nodemailer OTP email
    ├── package.json
    └── .env.example          ← Environment variables template
```

---

## Login Flow (Auth Flow)

```
App Open
   │
   ▼
10 sec Intro (kite animation)  ── "Skip" se bhi aage ja sakte ho
   │
   ├── Token hai (pehle se logged in)? ──YES──► Dashboard
   │
  NO
   ▼
Login Screen  ........................ (neeche right side: "Register")
   │
   ├── Email + Password ──► Login success ──► Team Screen ──► "Skip for now" ──► Dashboard
   │                                              │
   │                                              └── Create / Join team ──► Dashboard
   │
   └── "Register" ──► Register Screen  ... (neeche right side: "Login" -> Login Screen)
                          │
                     Fill form ──► OTP Screen (6 boxes, auto-verify)
                                        │
                                   OTP verified ──► Login Screen (email pehle se bhari)
                                                         │
                                                    Login karo ──► Team Screen ──► Skip ──► Dashboard
```

---

## Backend Setup (Kaise start karein)

### Step 1: Dependencies install karo
```bash
cd backend
npm install
```

### Step 2: .env file banao
```bash
cp .env.example .env
# Ab .env file open karo aur apni values daalo
```

### Step 3: .env mein ye fill karo
```
MONGODB_URI=mongodb://localhost:27017/gulabi_charkhi
JWT_SECRET=koi_bhi_strong_random_string
EMAIL_USER=aapkaemail@gmail.com
EMAIL_PASS=gmail_app_password_yahan
```

### Gmail App Password kaise banayein?
1. Gmail.com → Settings → Security
2. 2-Step Verification ON karo
3. "App passwords" → "Mail" select karo
4. Generated password → .env mein daalo

### Step 4: Server start karo
```bash
npm run dev    # Development
npm start      # Production
```

Server: `http://localhost:5000`

---

## Flutter Setup (Kaise start karein)

### Step 1: Dependencies install karo
```bash
cd flutter_app
flutter pub get
```

### Step 2: Backend URL set karo
`lib/services/auth_service.dart` file mein:
```dart
static const String baseUrl = 'http://YOUR_IP:5000/api';
// Local: http://10.0.2.2:5000/api  (Android emulator)
// Real device: http://192.168.x.x:5000/api
```

### Step 3: App run karo
```bash
flutter run
```

---

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/auth/register` | Register + OTP send |
| POST | `/api/auth/verify-otp` | OTP verify + login |
| POST | `/api/auth/resend-otp` | OTP resend |
| POST | `/api/auth/login` | Email+Password login |
| GET | `/api/auth/me` | Current user (protected) |
| POST | `/api/auth/logout` | Logout |
| GET | `/api/health` | Server health check |

---

## Design Colors (Design Colors)

| Variable | Color | Use |
|----------|-------|-----|
| bgPink | `#FCE4EC` | Background |
| primaryPink | `#E91E8C` | Buttons, highlights |
| primaryPurple | `#7B2FBE` | Header gradient end |
| Gradient | Pink → Purple | Buttons, header |

---

## Development Note (Dev mein OTP console mein dikhega)

Agar email send nahi ho raha (dev mein), to OTP console mein print hoga:
```
🔑 OTP for abc@gmail.com: 123456
```

---

## Tech Stack

**Frontend:** Flutter 3.x, Dart, http, shared_preferences

**Backend:** Node.js, Express.js, MongoDB, Mongoose, JWT, Nodemailer, Bcrypt
