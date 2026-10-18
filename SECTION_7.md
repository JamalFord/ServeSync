# 7.0 User Management Implementation

ServeSync Restaurant Management Application | Group 1 | Fall 2026

This section describes the supplied user-management implementation and database scripts for ServeSync. The module connects a SwiftUI staff interface to a Python API and MySQL database. It supports administrator-created employee accounts, unified PIN login, logout, sessions and role checks, following UC-01 and UC-08.

## 7.1 Employee Account Registration

Registration follows the Add User workflow in UC-08. An authenticated administrator enters the employee's full name, selects FOH Staff, Manager or Administrator, and assigns a unique four-digit PIN. The backend validates the input and saves the profile in Users. Public self-registration is not included in this staff application.

The access_code field stores a salted scrypt hash rather than a readable PIN. A separate keyed PIN lookup identifies the account because login uses only the PIN. Duplicate PINs and invalid role values are rejected. The initial administrator is created through a one-time setup command with a chosen PIN.

## 7.2 Login and Shift Tracking

The login screen sends the entered PIN to the API. The backend finds an active account, verifies its hash and determines its current role. On success, it creates a Payroll clock-in record and a session in one transaction. Invalid codes display Invalid Code and do not create shifts. A second active session for the same employee is rejected to avoid duplicate clock-ins.

## 7.3 Logout and Basic Session Handling

A random session token is returned to the app, while only its hash is stored in Sessions. Protected requests require the token and a current active account. The token remains in app memory while navigating. Logout records the clock-out time, calculates shift hours, removes the session and returns to login. These database changes are committed together.

Sessions expire after 12 hours; the next API request closes expired shifts at their expiry timestamps. If the app terminates without logout, an administrator can end the active session and correct the shift as needed. Payroll rates default to zero until configured by the payroll module; this section does not initiate bank deposits.

## 7.4 Role Management

Every protected request reads the employee's current role from the database. Only administrators may create or edit employees, change roles, reset PINs, deactivate accounts, inspect payroll or end another user's session. The SwiftUI dashboard identifies the current role and displays administrative navigation only to administrators. Existing restaurant screens can be connected to that dashboard.

## 7.5 Database Implementation

MySQL is the selected DBMS from section 6. The SQL scripts implement tables for four major use cases: UC-08, UC-02, UC-03 and UC-04. UC-01 authentication and shift tracking is included as supporting functionality for user management.

| Use case | Tables implemented |
| --- | --- |
| UC-08 User accounts | Users, Sessions, Login_Attempts, User_Management_Lock |
| UC-02 Customer dining orders | Customer_Orders, Menu_Items, Order_Items |
| UC-03 Table reservations | Reservations, Dining_Tables |
| UC-04 Restaurant inventory | Inventory, Inventory_Transactions |
| Supporting UC-01 Authentication | Payroll, Users, Sessions |

### Primary Keys and Relationships

Each main table has its own primary key. Customer_Orders.user_id, Reservations.created_by and Payroll.user_id reference Users.user_id. Each Order_Items row links an order to a menu item. Reservations.table_number references Dining_Tables. Inventory_Transactions links stock adjustments to the inventory item and responsible employee. Foreign keys preserve these relationships.

### Refinements to the Section 6 Design

The Users table retains the documented attributes and adds pin_lookup. Sessions, Login_Attempts and a locking row support authentication consistency. Menu_Items and Order_Items represent the dishes, quantities, modifications and prices required by UC-02. Dining_Tables and reservation end_time support future capacity and overlap checks. Inventory_Transactions retains adjustment history; inventory quantities use DECIMAL(10,2), correcting the duplicated type in section 6.

Removing an employee deactivates the account rather than deleting its historical references. Administrators cannot deactivate or demote their own account, and at least one active administrator must remain. PIN resets and deactivation close active shifts and invalidate sessions. Role changes take effect on the next protected backend request.

### SQL Scripts and Backend

database/01_schema.sql creates the MySQL database, tables, primary keys, foreign keys and validation constraints. database/02_sample_data.sql inserts sample menu items, dining tables and inventory. Neither script supplies a plaintext default administrator PIN. They target a new MySQL 8.0.16 or newer database.

backend/service.py implements validation, parameterized database operations, authentication, sessions and authorization. backend/server.py exposes the HTTP API using PyMySQL for database access. swift/ServeSyncUserManagement.swift supplies the login, dashboard, employee list and account editor views. Database credentials and the PIN lookup secret remain on the backend.

For UC-02, UC-03 and UC-04, this section provides the database structures and authenticated read endpoints. Full order entry, reservation conflict resolution and inventory adjustment interfaces are separate restaurant workflow implementations.

## 7.6 Verification and Demonstration

Seventeen automated backend behavior tests passed using an isolated SQLite test double. On October 5, 2026, the SwiftUI client was also built and run in Xcode's iPhone simulator on Salem Marye's Mac and connected to the Python API and MySQL 8.4.11. The following manual checks were completed through the app and MySQL console.

| Manual check | Observed result |
| --- | --- |
| Administrator login | Administrator Home displayed Salem Marye and clock-in confirmation. |
| Employee registration | Test Employee appeared as FOH Staff, Active. |
| Employee login and dashboard | FOH Staff Home displayed without administrative navigation. |
| Account deactivation | Login using the inactive employee PIN was rejected. |
| PIN reset and reactivation | Old PIN failed; replacement PIN successfully logged in. |
| Role update | Employee role changed to Manager; Manager Home appeared without administrative navigation. |
| Database persistence | Users query returned Salem Marye as Administrator and Test Employee as Manager, both Active. |
| Shift and session records | Seven Payroll records had clock-in and clock-out timestamps; Sessions contained zero rows after logout. |

Screenshots document the administrator dashboard, employee directory and FOH dashboard. PIN reset, deactivation and Manager screen outcomes were confirmed during the manual walkthrough. The database evidence file reproduces the query results supplied from the MySQL console. Hidden navigation verifies the interface behavior; backend permission enforcement is covered separately by the automated tests.

### Integration Status

The standalone user-management demo successfully connects SwiftUI, the Python API and MySQL. Integration into the team's complete restaurant application remains separate. Orders, reservations and inventory include database structures and authenticated read endpoints; full operational interfaces are outside this module.

The working ServeSyncLocal Xcode project is included under xcode/ServeSyncLocal. Its app entry point opens ContentView, which loads ServeSyncUserManagementRoot. The project preserves the simulator configuration used for the demonstration, including an iOS 27.0 deployment target and Swift 5 language mode.
