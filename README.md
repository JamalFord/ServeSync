# ServeSync — Restaurant Management App

### ▶️ [Open the live web app](https://jamalford.github.io/ServeSync/) &nbsp;·&nbsp; 📱 [Download the Android APK](https://github.com/JamalFord/ServeSync/releases/latest) &nbsp;·&nbsp; 🩺 [Cloud API status](https://servesync-production-d1da.up.railway.app/health)

**Course:** Software Engineering (CTW XLS Group ACS66) — Fall Semester 2026
**Guide:** Dr. Tushara Sadasivuni
**Group:** 1
**Team Members:** Jamal F., Kristian N., <ins>Mason M.</ins> (Coordinator), Salem M., Sneha P.

| Layer | Technology | Hosted on |
| :--- | :--- | :--- |
| App (iOS, Android, Web) | Flutter 3.24 / Dart | GitHub Pages (web), GitHub Releases (APK) |
| REST API | Python 3 (`ThreadingHTTPServer` + PyMySQL) | Railway |
| Database | MySQL 8 | Railway |

---

## 1. Try It

1. Open the **[live web app](https://jamalford.github.io/ServeSync/)** (works on phones and desktops), or install the **[Android APK](https://github.com/JamalFord/ServeSync/releases/latest)**.
2. Sign in with a demo PIN, or tap a name under **Quick Demo Profiles**:

| Role | Employee | Demo PIN |
| :--- | :--- | :--- |
| Administrator | Salem Marye | `1234` |
| Manager | Kristian Napier | `2345` |
| FOH Staff | Jamal Ford | `3456` |
| FOH Staff | Sneha Patel | `4567` |
| FOH Staff | Mason Mathias | `5678` |

The header shows **☁ Cloud** when the app is connected to the Railway API, or **Offline** when it is running on built-in demo data (the app falls back automatically if the cloud is unreachable).

> These are shared demo accounts on a public demo deployment. Do not enter real employee data.

---

## 2. Architecture

```text
┌──────────────────────────────┐
│ Flutter app (mobile/)        │
│ iOS · Android · Web          │
└──────────────┬───────────────┘
               │ HTTPS · JSON · Bearer token
               ▼
┌──────────────────────────────┐
│ ServeSync REST API (backend/)│  Railway service, root directory /backend
│ PIN auth, roles, shifts,     │
│ inventory, purchasing,       │
│ orders, reservations,        │
│ reviews, payroll, hiring     │
└──────────────┬───────────────┘
               │ PyMySQL · transactions
               ▼
┌──────────────────────────────┐
│ MySQL 8 (Railway)            │  schema: backend/railway_full_schema.sql
│                              │  + backend/migrations.py (Sprint 4 additions)
└──────────────────────────────┘
```

- The app never connects to MySQL directly; all database access goes through the API. No other data service is used (Firebase was removed in Sprint 4).
- PINs are stored as salted **scrypt** hashes, with an HMAC lookup key so login needs no username.
- **Login and clock-in are separate** (client requirement): logging in starts an app session, *Clock In/Out* start and end the shift, and logging out does **not** end an open shift.
- One active session per employee. The app closes a session it left open (page refresh, app killed) before logging in again, so staff are never locked out.

### What runs through the cloud API

| Feature | Data source |
| :--- | :--- |
| PIN login / logout, clock in / clock out | Railway API + MySQL |
| Inventory levels, spoilage logging (UC-11) | Railway API + MySQL |
| Supplier purchase orders: create and receive deliveries (UC-05) | Railway API + MySQL |
| POS orders and kitchen display (KDS) | Railway API + MySQL. Every device reads the kitchen tickets from the API every 5 seconds. |
| Reservations, customer service, suppliers, user accounts, payroll, hiring (Manage tab) | Railway API + MySQL |
| Customer reviews and summary, consumption forecast (AI Copilot) | Railway API + MySQL. The written summary uses Claude if `ANTHROPIC_API_KEY` is set, otherwise a built-in engine. |
| Floor plan (which table is seated) | Held on each device |

---

## 3. App Features (`mobile/`)

| Tab / screen | What it does |
| :--- | :--- |
| **PIN keypad** | 4-digit login, quick demo profiles, theme picker |
| **Floor Plan** | Live table status (Available / Seated / Ordered / Check / Dirty); seat a party with a manual party-size counter (capped at table capacity) |
| **Quick POS** | Build an order per table and assign each item to a seat (Seat 1…N or Shared, where N is the party size); send to kitchen |
| **Kitchen (KDS)** | Ticket queue with seat badges; advance tickets through prep to served |
| **Inventory** | Stock levels with low-stock alerts, spoilage logging with stock before/after, **Supplier Orders** tab to create purchase orders and receive deliveries (auto-increments stock) |
| **Shifts** | Clock in / out with elapsed time and earnings; **Manager Payroll** portal with wage audit and hourly-rate editing |
| **✨ AI Copilot** | Demand-forecast, waste and labor insights. *Currently scripted demo responses — not yet connected to an AI model.* |
| **Themes** | Four presets: Midnight Ember, Modern Bistro, Cyber Kitchen, Tuscan Trattoria |

---

## 4. Running Locally

### Flutter app

Requires Flutter 3.24+ (`flutter doctor`).

```bash
cd mobile
flutter pub get
flutter run -d chrome          # web
flutter run -d "iPhone 17"     # iOS Simulator (needs full Xcode + CocoaPods)
flutter run                    # pick a connected device
```

The app talks to the Railway API by default. To use a local backend instead:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

### Backend (local, SQLite)

For development without MySQL, the API can run on the bundled SQLite database:

```bash
python3 -m pip install -r backend/requirements.txt
python3 database/seed_database.py      # (re)creates database/servesync_dev.db with demo data
./scripts/run_backend.sh               # run from the repo root; serves http://127.0.0.1:8000
```

### Backend (local, MySQL)

Set `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` and `PIN_LOOKUP_SECRET`, then run `python3 backend/server.py`. On startup the server creates any missing tables from `backend/railway_full_schema.sql` and seeds the demo staff.

---

## 5. Deployment

### Railway (API + MySQL)

| Setting | Value |
| :--- | :--- |
| Service source | `JamalFord/ServeSync`, branch `main`, root directory `/backend` |
| Start command | `Procfile` → `web: python server.py` |
| Public URL | `https://servesync-production-d1da.up.railway.app` |

| Variable | Purpose |
| :--- | :--- |
| `MYSQLHOST`, `MYSQLPORT`, `MYSQLUSER`, `MYSQLPASSWORD`, `MYSQLDATABASE` | Injected by the Railway MySQL service (or use `DB_*` equivalents) |
| `PIN_LOOKUP_SECRET` | Secret (32+ chars) for PIN lookups. **Set your own value in Railway**; the default in the code is public. Changing it later requires re-seeding PINs. |
| `PORT` | Set by Railway (8080) |

**Automatic database setup:** on every start, `server.py` checks that all 19 required tables exist. If any are missing it loads `railway_full_schema.sql` and seeds the demo staff; if tables exist but `Users` is empty it seeds staff only. It retries while MySQL is still booting, and a request that hits a missing table re-triggers setup. Check the deploy logs for `[Init]` lines.

**Health checks:**
- `GET /health` — API is running
- `GET /db-test` — database reachable; returns user count and table list

To add or reset demo staff on an existing database: `python3 database/seed_cloud_mysql.py` (upserts the accounts in §1).

### GitHub Actions

| Workflow | Trigger | Result |
| :--- | :--- | :--- |
| `build_apk.yml` | Push to `main` that changes `mobile/` | Builds the Android APK and publishes a [GitHub Release](https://github.com/JamalFord/ServeSync/releases) |
| `deploy_web.yml` | Push to `main` that changes `mobile/` | Builds Flutter web and publishes it to [GitHub Pages](https://jamalford.github.io/ServeSync/) |

GitHub Pages must be set to **Settings → Pages → Source: GitHub Actions** (not "Deploy from a branch").

---

## 6. Testing

```bash
cd mobile && flutter test               # app tests, incl. API client online/offline handling
cd mobile && flutter analyze            # static analysis
python3 tests/test_sprint3_backend.py   # backend behavior tests (isolated SQLite)
```

`tests/test_user_management.py` targets the older Sprint 2 schema (`database/01_schema.sql`) and currently fails against the current backend; the Sprint 3 suite above is the maintained one.

---

## 7. Database Schema

**Canonical schema:** `backend/railway_full_schema.sql` (also copied to `database/`) — 19 tables, used by Railway.

| Area | Tables |
| :--- | :--- |
| Users & security (UC-01, UC-08) | `Users`, `Sessions`, `Login_Attempts`, `User_Management_Lock`, `Payroll` |
| Dining (UC-02, UC-03) | `Dining_Tables`, `Reservations`, `Menu_Items`, `Customer_Orders`, `Order_Items` |
| Inventory (UC-04, UC-11) | `Inventory`, `Inventory_Transactions`, `Inventory_Spoilage` |
| Purchasing (UC-05) | `Suppliers`, `Supplier_Orders`, `Supplier_Order_Items`, `Delivery_Receipts` |
| HR & service (UC-10, UC-12) | `Job_Applicants`, `Customer_Service_Issues` |

`database/01_schema.sql` and `02_sprint3_schema.sql` are the earlier Sprint 2/3 scripts, kept for the course record. They predate the session/shift separation (e.g. `Sessions.payroll_id` is `NOT NULL` there) and should not be used for new installs.

---

## 8. Repository Layout

```text
ServeSync/
├── README.md
├── mobile/                          # Flutter app (iOS / Android / Web)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── services/
│   │   │   ├── app_state.dart       # App state, offline demo data, cloud sync
│   │   │   └── api_client.dart      # Railway REST API client
│   │   ├── screens/                 # auth, floor_plan, pos, kds, inventory, shifts, ai, shell
│   │   ├── models/
│   │   └── theme/app_theme.dart     # 4 theme presets
│   └── test/
├── backend/                         # Railway service root
│   ├── server.py                    # HTTP server + automatic DB setup
│   ├── service.py                   # Business logic, auth, transactions
│   ├── railway_full_schema.sql      # Canonical MySQL schema + seed data
│   ├── Procfile · requirements.txt · env.example
├── database/                        # Seed scripts, legacy schemas, SQLite dev DB
├── tests/                           # Python backend tests
├── scripts/                         # Local run / test / build helpers
├── .github/workflows/               # APK release + GitHub Pages deploy
├── swift/ · xcode/                  # Sprint 3 SwiftUI prototype (superseded by mobile/)
└── evidence/                        # Saved test output for course submissions
```

The original SwiftUI prototype (`swift/`, `xcode/ServeSyncLocal`) is kept for the Sprint 3 record; active development is in `mobile/`.
