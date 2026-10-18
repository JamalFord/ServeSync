# ServeSync (Restaurant Management iOS Application)

**Course:** Software Engineering (CTW XLS Group ACS66) | Fall Semester 2026  
**Group Number:** 1  
**Team Members:** Jamal F., Kristian N., Mason M., Salem M., Sneha P.  
**Firebase Project:** `servesync-798c7` (Number: `1023257586929`)  
**Repository:** [https://github.com/JamalFord/ServeSync](https://github.com/JamalFord/ServeSync)

---

## 1. System Overview & Architecture

ServeSync is an all-in-one restaurant management mobile application built natively in **SwiftUI** for Apple iOS. It centralizes front-of-house customer dining orders, table reservations, inventory management, supplier purchasing, employee shift tracking, and customer service.

```text
┌───────────────────────────┐
│   Native iOS Client       │  SwiftUI (iOS 16+, Swift 5)
│   (iPhone / iPad App)     │  Views: User Mgmt, Supplier POs, Spoilage Log
└─────────────┬─────────────┘
              │ HTTPS / REST (JSON)
              ▼
┌───────────────────────────┐
│   ServeSync Backend API   │  Python 3.11+ / Cloud Functions
│   Business Logic & Auth   │  Scrypt PIN hashing, RBAC, Idempotency, Atomicity
└─────────────┬─────────────┘
              │
      ┌───────┴────────────────────────┐
      ▼                                ▼
┌──────────────────────────┐   ┌──────────────────────────┐
│  Google Cloud Firestore  │   │  Local Dev / Test DB     │
│  (servesync-798c7)       │   │  SQLite / MySQL 8+ DDL   │
│  NoSQL Document Store    │   │  Automated Tests & Demos │
└──────────────────────────┘   └──────────────────────────┘
```

---

## 2. Sprint 3 Implemented Deliverables

### A. Two Complete Native iOS Features (GUI + Logic + DB)
1. **Feature A: UC-05 Supplier Purchase Orders & Delivery Receiving**
   - **Screens:** `SupplierOrdersView.swift`, `PurchaseOrderDetailView`, `CreatePurchaseOrderSheet`, `ReceiveDeliverySheet`.
   - **Workflow:** Managers/Admins can browse approved suppliers, create POs with item lines and costs, inspect open orders, and record deliveries.
   - **Atomic Receipt:** Supports partial delivery receipts. Entering received quantities increases inventory stock, marks line items, updates order status (*Pending $\rightarrow$ Partial $\rightarrow$ Received*), logs audit entries, and uses an idempotent `request_id` to prevent duplicate stock updates.
2. **Feature B: UC-11 Record Inventory Spoilage**
   - **Screens:** `SpoilageLoggingView.swift`, `RecordSpoilageSheet`.
   - **Workflow:** Managers/Admins select affected stock items, enter spoiled quantities, and choose reasons (*Expired, Temperature Fluctuation, Prep Waste, Contaminated*).
   - **Atomic Deduction:** Validates that quantity does not exceed on-hand stock, atomically reduces inventory, creates a persistent spoilage record with stock before/after, and appends an inventory transaction log.

### B. Client Refinement: Explicit Shift Time Tracking (UC-01)
- As requested by the client, employee **Clock In** and **Clock Out** are explicit, dedicated actions.
- Logging in grants access to the app session. Logging out revokes the session token but **preserves an active work shift**. Unresolved shifts remain open until explicit clock-out.

### C. Four Additional Database Use Cases (Cloud Firestore + SQL DDL)
1. **UC-05**: `suppliers`, `purchaseOrders`, `deliveryReceipts`
2. **UC-11**: `spoilageRecords`, `inventoryTransactions`, `inventory`
3. **UC-10**: `applicants` (Job candidate tracking and onboarding pipeline)
4. **UC-12**: `serviceIssues` (Customer service incident logging and resolution notes)

---

## 3. Quick Start & Execution (No IDE Required)

The backend and verification test suite run completely from the command line on any standard machine with Python 3:

### Step 1: Seed the Database
Populate sample users, inventory items, suppliers, and initial orders:
```bash
# On Windows:
python database\seed_database.py

# On macOS / Linux:
python3 database/seed_database.py
```

### Step 2: Run Automated Verification Tests
Runs the 5-suite verification covering UC-01, UC-05, UC-11, UC-10, UC-12, RBAC, and idempotency:
```bash
# On Windows:
scripts\run_tests.bat
# or:
python tests\test_sprint3_backend.py

# On macOS / Linux:
./scripts/run_tests.sh
# or:
python3 tests/test_sprint3_backend.py
```

### Step 3: Launch Local API Backend
```bash
# On Windows:
scripts\run_backend.bat

# On macOS / Linux:
./scripts/run_backend.sh
```
The API starts on `http://127.0.0.1:8000`.

### Step 4: Run Native iOS App
- **Option 1 (Xcode):** Open `xcode/ServeSyncLocal/ServeSyncLocal.xcodeproj` in Xcode on a Mac and select any iOS Simulator (e.g. iPhone 16) or connected device.
- **Option 2 (Command Line without IDE):** On a Mac, run:
  ```bash
  ./scripts/build_ios.sh
  ```

---

## 4. Demo Access Credentials

The pre-seeded database includes test accounts for all restaurant roles:

| Role | Employee Name | PIN Code | Permitted Operations |
| :--- | :--- | :--- | :--- |
| **Administrator** | Salem Marye | `1234` | Full access: User Management, Supplier POs, Spoilage, Shift tracking |
| **Manager** | Kristian Napier | `2345` | Supplier POs & Receiving (UC-05), Spoilage Logging (UC-11), Shift tracking |
| **FOH Staff** | Jamal Ford | `3456` | Dining Orders, Table Reservations, Shift Clock In/Out |
| **FOH Staff** | Sneha Patel | `4567` | Dining Orders, Table Reservations, Shift Clock In/Out |

---

## 5. Repository Directory Layout

```text
ServeSync/
├── GoogleService-Info.plist               # Firebase Apple configuration (servesync-798c7)
├── README.md                              # This documentation
├── backend/
│   ├── service.py                         # Business logic, atomic transactions & RBAC
│   ├── server.py                          # Multi-threaded HTTP REST API server
│   └── requirements.txt                   # Optional dependencies (PyMySQL)
├── database/
│   ├── 01_schema.sql                      # Sprint 2 baseline MySQL schema
│   ├── 02_sprint3_schema.sql              # Sprint 3 MySQL schema extension (UC-05, 10, 11, 12)
│   ├── firestore_schema.json              # Cloud Firestore collection data dictionary
│   ├── seed_database.py                   # Automated seed script for dev & test environments
│   └── servesync_dev.db                   # Pre-seeded development database
├── evidence/
│   └── sprint3_test_results.txt           # Captured test execution output
├── scripts/
│   ├── run_backend.bat / run_backend.sh   # Start local API without IDE
│   ├── run_tests.bat / run_tests.sh       # Run automated test suite
│   └── build_ios.sh                       # Command-line xcodebuild script
├── swift/
│   ├── ServeSyncUserManagement.swift      # User management, PIN auth & explicit shift tracking
│   ├── SupplierOrdersView.swift           # Native Feature A: Supplier purchasing & receiving (UC-05)
│   ├── SpoilageLoggingView.swift          # Native Feature B: Spoilage logging & stock deduction (UC-11)
│   └── ContentView.swift                  # Root view container
├── tests/
│   ├── test_sprint3_backend.py            # Automated test suite for Sprint 3
│   └── test_user_management.py            # Preserved Sprint 2 test suite
└── xcode/
    └── ServeSyncLocal/                    # Complete native Xcode project
        └── ServeSyncLocal.xcodeproj
```
