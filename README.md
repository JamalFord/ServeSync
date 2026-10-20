Copy this into your GitHub `README.md`:

````markdown
# ServeSync (Restaurant Management iOS Application)

**Course:** Software Engineering (CTW XLS Group ACS66) | Fall Semester 2026  
**Group Number:** 1  
**Team Members:** Jamal F., Kristian N., Mason M., Salem M., Sneha P.  
**Database:** MySQL 8.0.16+  
**Backend:** Python REST API with PyMySQL  
**Frontend:** SwiftUI  
**Repository:** [JamalFord/ServeSync](https://github.com/JamalFord/ServeSync)

---

## 1. System Overview and Architecture

ServeSync is a native iOS restaurant management application designed to centralize daily operations for a single restaurant location. Its project scope includes customer orders, reservations, inventory, supplier purchasing, employee management, shift tracking, payroll records, hiring, and customer service.

MySQL is the selected database management system, consistent with the Sprint 3 document.

```text
┌─────────────────────────────┐
│ Native iOS Application      │
│ SwiftUI                     │
└──────────────┬──────────────┘
               │ REST / JSON
               ▼
┌─────────────────────────────┐
│ Python Backend API          │
│ Authentication, permissions│
│ and business logic          │
└──────────────┬──────────────┘
               │ PyMySQL / SQL
               ▼
┌─────────────────────────────┐
│ MySQL Database              │
│ Relational tables, keys,    │
│ constraints and transactions│
└─────────────────────────────┘
```

The iOS application communicates with the backend API, and the backend manages database access. The application does not connect directly to MySQL.

- **MySQL:** Selected application database.
- **Python:** Backend authentication, role permissions, validation, and transaction processing.
- **SwiftUI:** Native iPhone and iPad interface.
- **SQLite:** Used by existing isolated backend tests and the sample-data script.

Firebase/Cloud Firestore is not the selected application database. Existing Firebase configuration and Firestore reference files are legacy artifacts.

**Current status:** The repository contains a MySQL connection implementation and SQL schema scripts. Schema alignment and end-to-end MySQL/iOS verification remain outstanding.

---

## 2. Sprint 3 Implementation Scope

### A. Supplier Purchase Orders and Delivery Receiving — UC-05

**Screens:** `SupplierOrdersView.swift`, `PurchaseOrderDetailView`, `CreatePurchaseOrderSheet`, and `ReceiveDeliverySheet`.

The implementation includes workflows for managers and administrators to:

- Browse suppliers.
- Create purchase orders with item quantities and costs.
- Review purchase orders and their line items.
- Record partial or complete deliveries.
- Increase inventory quantities when deliveries are received.
- Track order status as `Pending`, `Partial`, or `Received`.

The backend groups delivery updates into a database transaction and uses a `request_id` to identify repeated receipt submissions.

### B. Inventory Spoilage Recording — UC-11

**Screens:** `SpoilageLoggingView.swift` and `RecordSpoilageSheet`.

The implementation includes workflows for managers and administrators to:

- Select an inventory item.
- Enter the spoiled quantity and reason.
- Validate that the quantity does not exceed available stock.
- Deduct spoiled stock.
- Retain spoilage records with stock quantities before and after the adjustment.
- Record the inventory change in the transaction history.

### C. Explicit Shift Tracking — UC-01

Clock-in and clock-out are separate employee actions:

- **Login:** Starts an application session.
- **Clock In:** Starts a work shift.
- **Clock Out:** Ends the active work shift.
- **Logout:** Ends the application session without automatically ending the shift.

This follows the client clarification in the sprint document and the current backend behavior. Some older sections of the document still describe automatic clock-in and clock-out during login and logout.

### D. Four Additional Database Use Cases

| Use Case | MySQL Tables |
| :--- | :--- |
| UC-05: Supplier Purchasing and Delivery Receiving | `Suppliers`, `Supplier_Orders`, `Supplier_Order_Items`, `Delivery_Receipts` |
| UC-11: Inventory Spoilage | `Inventory_Spoilage`, `Inventory`, `Inventory_Transactions` |
| UC-10: Job Applicants | `Job_Applicants` |
| UC-12: Customer Service Administration | `Customer_Service_Issues` |

These extend the baseline database tables for:

- User accounts and sessions — UC-08
- Customer dining orders — UC-02
- Reservations — UC-03
- Inventory management — UC-04
- Payroll and shift records — UC-01

### E. Additional Project Requirements

The sprint document also identifies menu management, price management, third-party delivery integration, AI review summaries, and consumption analytics as project requirements. These requirements should not be interpreted as completed integrations.

---

## 3. Database Design

MySQL stores structured restaurant records using relational tables, primary keys, foreign keys, and constraints.

The schema is organized into two scripts:

| File | Purpose |
| :--- | :--- |
| `database/01_schema.sql` | Baseline tables for users, sessions, payroll, orders, menu items, reservations, dining tables, and inventory |
| `database/02_sprint3_schema.sql` | Additional tables for supplier purchasing, delivery receipts, spoilage, applicants, and customer service issues |

The backend uses parameterized SQL and database transactions. PIN authentication uses salted scrypt hashes and a server-side secret for PIN lookup.

### Known MySQL Integration Issues

The current schema and backend require alignment before the MySQL workflows can be considered fully operational:

1. **Session and shift separation:** `Sessions.payroll_id` is declared `NOT NULL`, but the backend inserts `NULL` when creating a session because login does not automatically start a shift.
2. **Inventory transaction column:** The schema defines `Inventory_Transactions.created_at`, while delivery and spoilage operations insert into a column named `timestamp`.
3. **Backend launcher:** `scripts/run_backend.sh` assigns a SQLite file path to `DB_NAME`, while `backend/server.py` initializes a MySQL connection.

These issues require implementation changes and MySQL integration testing. Updating this README does not resolve them.

---

## 4. Setup and Execution

Run commands from the repository root.

### Prerequisites

- Python 3.11+
- MySQL 8.0.16+ and the MySQL command-line client
- macOS with Xcode and the appropriate iOS SDK for building the iOS application

### Step 1: Install Backend Dependencies

On macOS or Linux:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r backend/requirements.txt
```

On Windows using Command Prompt:

```bat
python -m venv .venv
.venv\Scripts\activate.bat
python -m pip install -r backend/requirements.txt
```

### Step 2: Create the MySQL Schema

For a fresh installation, connect using an account with permission to create the database and tables:

```bash
mysql -u root -p
```

Run the following inside the MySQL client:

```sql
SOURCE database/01_schema.sql;
USE servesync;
SOURCE database/02_sprint3_schema.sql;
```

The baseline script creates the `servesync` database. It is intended for a fresh installation and is not a repeatable migration for an existing database.

Resolve the schema issues listed above before verifying login, delivery receiving, or spoilage recording.

### Step 3: Configure the Backend

Set these environment variables in the shell used to launch the backend:

| Variable | Description |
| :--- | :--- |
| `DB_HOST` | MySQL hostname; defaults to `127.0.0.1` |
| `DB_PORT` | MySQL port; defaults to `3306` |
| `DB_USER` | MySQL account used by the backend |
| `DB_PASSWORD` | Password for the MySQL account |
| `DB_NAME` | Database name: `servesync` |
| `PIN_LOOKUP_SECRET` | Private, stable secret containing at least 32 characters |
| `API_HOST` | API bind address; defaults to `127.0.0.1` |
| `PORT` | API port; defaults to `8000` |

Keep the same `PIN_LOOKUP_SECRET` across restarts so existing PIN lookups continue to work. Keep database passwords and private secrets out of version control.

### Step 4: Create the Initial Administrator

After resolving the schema issues, create the first administrator in a database with an empty `Users` table:

```bash
python backend/server.py --bootstrap --name "ServeSync Administrator"
```

The command prompts for the administrator’s four-digit PIN.

### Step 5: Start the Backend

With the environment variables configured:

```bash
python backend/server.py
```

The default local API address is:

```text
http://127.0.0.1:8000
```

Use this direct command for MySQL setup until the supplied launcher scripts are corrected.

The development server uses HTTP. HTTPS requires separate hosting and TLS configuration.

### Step 6: Build the iOS Application

On a Mac with Xcode and the required SDK installed:

```bash
./scripts/build_ios.sh
```

The native project is located at:

```text
xcode/ServeSyncLocal/ServeSyncLocal.xcodeproj
```

After backend setup, verify login, explicit clock-in/out, purchase-order receiving, and spoilage recording through the application. A successful build alone does not verify database integration.

---

## 5. Backend Tests and SQLite Sample Data

The existing sample-data script creates a local SQLite database:

```bash
python database/seed_database.py
```

Its output database is:

```text
database/servesync_dev.db
```

This script does not populate MySQL.

Run the Sprint 3 backend behavior tests with:

```bash
python tests/test_sprint3_backend.py
```

The tests cover authentication and explicit shift tracking, supplier orders and receiving, spoilage, role permissions, applicants, and customer service.

These tests use an isolated SQLite database. Passing them does not verify MySQL schema compatibility or the complete iOS-to-MySQL workflow.

The sprint document reports 17 earlier backend behavior tests against SQLite and identifies MySQL execution and Xcode testing as outstanding.

---

## 6. Demo Accounts

The SQLite sample-data script creates these local demonstration accounts:

| Role | Employee | Demo PIN |
| :--- | :--- | :--- |
| Administrator | Salem Marye | `1234` |
| Manager | Kristian Napier | `2345` |
| FOH Staff | Jamal Ford | `3456` |
| FOH Staff | Sneha Patel | `4567` |

These accounts are not automatically created in MySQL. For MySQL, create the initial administrator with the bootstrap command and add employee accounts through user management.

The listed PINs are intended for local demonstrations only.

---

## 7. Repository Directory Layout

```text
ServeSync/
├── README.md
├── GoogleService-Info.plist          # Legacy Firebase configuration
├── backend/
│   ├── service.py                   # Business logic, authentication, and transactions
│   ├── server.py                    # Python REST API server
│   └── requirements.txt             # PyMySQL dependency
├── database/
│   ├── 01_schema.sql                # Baseline MySQL schema
│   ├── 02_sprint3_schema.sql         # Sprint 3 MySQL extension
│   ├── firestore_schema.json        # Legacy Firestore reference
│   ├── seed_database.py             # SQLite sample-data script
│   └── servesync_dev.db              # SQLite development database
├── evidence/
│   └── sprint3_test_results.txt      # Saved test output
├── scripts/
│   ├── run_backend.bat
│   ├── run_backend.sh               # Requires MySQL configuration correction
│   ├── run_tests.bat
│   ├── run_tests.sh
│   └── build_ios.sh                 # Command-line iOS build
├── swift/
│   ├── ServeSyncUserManagement.swift
│   ├── SupplierOrdersView.swift
│   ├── SpoilageLoggingView.swift
│   └── ContentView.swift
├── tests/
│   ├── test_sprint3_backend.py
│   └── test_user_management.py
└── xcode/
    └── ServeSyncLocal/
        └── ServeSyncLocal.xcodeproj
```
````
