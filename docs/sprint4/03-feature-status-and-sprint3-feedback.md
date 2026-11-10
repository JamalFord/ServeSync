# ServeSync Sprint 4 — Feature list, feature status, and Sprint 3 feedback

Updated 10 November 2026. Part 1 is the feature list to paste into the Sprint 4 document. Part 2 says what was built on 10 November and what each feature depends on. Parts 3 and 4 are the Section 5 corrections and the Sprint 3 feedback (unchanged).

## 1. Feature list for the document

The Sprint 4 brief asks the team to print all the features mentioned from Sprint 1 as a list. The block below is that list: the twelve features the team wrote down at the start of the project, in the same order, with the requirement, the use case, where each one is in the application, and its test cases. The same block is on the copy-and-paste page (`sections-10-11.html`, first Copy button). Give its heading a Heading style so that it gets an entry in the table of contents.

<!-- feature-list:start -->
# Project Features

The twelve features defined in Sprint 1 are listed below. All twelve are implemented in the Sprint 4 system: each one has a screen in the application, routes in the REST API, and tables in the MySQL database. The Test cases column refers to Section 10 (10.1.7).

| No. | Feature (Sprint 1) | Requirement | Use case | Where it is in the application | Test cases |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | Incoming inventory; contacting and managing suppliers | FR-1 | UC-05 | Inventory → Supplier Orders (create, receive, cancel a purchase order); Manage → Suppliers (contact details) | 5.1 – 5.10, T13, T14 |
| 2 | User management module | FR-2 | UC-01, UC-08 | PIN keypad (log in); Manage → User Accounts (create, edit, deactivate, reset PIN, end session) | 1.1 – 1.6, 8.1 – 8.10 |
| 3 | Supply database with permissions | FR-3 | UC-04 | Inventory tab (stock list, add and edit items, stock adjustment with a reason); changes limited to Manager and Administrator | 5.5, 11.7, T15 |
| 4 | Payroll | FR-4 | UC-09 | Manage → Payroll (hours and pay per employee, pay rates, adjust a shift with a reason, mark as paid) | T16 |
| 5 | Employee management | FR-5 | UC-01 | Shifts tab (clock in and clock out, separate from log in); Manage → User Accounts (role and pay rate) | 1.7 – 1.9, T16 |
| 6 | Display interface: spoilage tracking | FR-6 | UC-11 | Inventory → Spoilage (record spoilage, spoilage log, stock deducted once) | 11.1 – 11.9 |
| 7 | Reservation management | FR-7 | UC-03 | Manage → Reservations (create, edit, seat, cancel, no-show; double bookings refused) | T02 – T05 |
| 8 | Google review summary (AI powered) | FR-8 | UC-07 | AI Copilot → Reviews (review list, rating breakdown, AI summary of strengths and complaints, Google import) | T08 – T10 |
| 9 | Ordering management | FR-9 | UC-02 | Floor Plan, Quick POS and Kitchen (KDS) tabs; orders saved to the database and stock reduced by recipe | 2.1 – 2.8, T06, T07, T19 |
| 10 | Consumption analytics (AI powered) | FR-10 | UC-06 | AI Copilot → Demand (usage per item, days of stock left, stock-out date, order quantity, create purchase order) | T11, T12 |
| 11 | Customer service administration | FR-11 | UC-12 | Manage → Customer Service (log an issue, search, start, resolve with notes) | T18 |
| 12 | Application and hiring database | FR-12 | UC-10 | Manage → Hiring (applicants, hiring stages, hire and create the staff account, onboarding status) | T17 |

Three later client requests (menu management, price management, and third-party delivery integration) are listed in Section 2 as planned work and are not part of this list.
<!-- feature-list:end -->

## 2. What was built on 10 November, and what each feature depends on

| Feature | Before | Now |
| :--- | :--- | :--- |
| 1 Suppliers | Create and receive purchase orders | Added: cancel a pending order; add and edit supplier contacts |
| 2 User management | API only | Added: User Accounts screen |
| 3 Supply database | Read-only list | Added: add and edit items; stock adjustment with a reason and an audit record |
| 4 Payroll | Estimate on the Shifts screen; rates not saved | Added: pay rate saved per employee; payroll screen; adjustment with a reason; paid status |
| 5 Employee management | Clock in and out at a fixed $15.00 | Shifts now use the employee's own pay rate |
| 7 Reservations | Table only | Added: full API and screen, with double-booking and capacity checks |
| 8 Review summary | Fixed sample text | Added: Customer_Reviews and Review_Summaries tables, review entry, summary generated from the stored reviews, Google import |
| 9 Ordering | Orders kept in the app and synced through Firebase | Orders are saved to Customer_Orders and Order_Items; stock is reduced by recipe; the kitchen display reads its tickets from the API on every device; clearing the table completes the order. Firebase is no longer used. |
| 10 Consumption analytics | Fixed sample text | Forecast calculated from the inventory audit log; purchase order can be created from a recommendation |
| 11 Customer service | API only | Added: screen, In Progress status, search |
| 12 Hiring | Table and list only | Added: hiring stages, notes, hire action that creates the staff account, onboarding status, screen |

Things to know before describing the two AI features in the demo:

- **The numbers are always calculated from the database** (ratings, usage, days of stock left, order quantities). They change when reviews, orders, spoilage, or deliveries change.
- **The written summary is produced by one of two engines, and the screen shows which.** If the server has an `ANTHROPIC_API_KEY`, Claude writes it. If not, a built-in engine writes it (sentiment word lists and theme matching for reviews; a moving-average forecast for stock). As of this update no key is set on Railway, so the screen will say "ServeSync built-in analysis". To use Claude, add `ANTHROPIC_API_KEY` in the Railway service variables. The Claude path has not been run, because no key was available.
- **Google reviews:** the import calls the Google Places API and needs `GOOGLE_PLACES_API_KEY` and `GOOGLE_PLACE_ID` on the server. ServeSync is not a real restaurant, so there is no Google listing to import from; without the keys the screen shows "Google reviews: Unavailable" and the import button reports that Google is not connected. The twelve reviews loaded for the demo are sample data and are labelled "Sample". The import has not been run against Google.
- **Fourteen days of sample kitchen usage** are loaded into the inventory audit log (reason "Sample usage history") so the forecast has history on day one. Real orders and spoilage add to it.

New database objects (for Section 6, which still lists the original 19 tables): tables `Customer_Reviews`, `Review_Summaries`, `Menu_Item_Ingredients` (22 tables in total); columns `Customer_Orders.kitchen_status`, `Users.hourly_rate`, `Payroll.adjustment_reason`, `Payroll.adjusted_by`, `Job_Applicants.notes`, `Job_Applicants.hired_user_id`, `Job_Applicants.onboarding_status`, `Customer_Orders.completed_at`, `Customer_Orders.payment_method`, `Reservations.notes`. They are added automatically when the server starts (`backend/migrations.py`); nothing is dropped.

## 3. Corrections needed in Section 5 of the document

These are places where the Sprint 3 text no longer matches the system. They are in Section 5, so whoever owns that section should make them.

| Where | Problem | Suggested change |
| :--- | :--- | :--- |
| FR-5 (Section 2 and 5.2.5) | The text says "Upon successful login, the system shall record the employee's clock-in timestamp … and record a clock-out timestamp upon session termination." The same document says the client asked for clock-in and clock-out to be explicit and separate from login. The system follows the client. | Reword to: "The system shall record a clock-in timestamp when the employee chooses to clock in and a clock-out timestamp when the employee chooses to clock out. Logging in or out shall not start or end a shift." |
| 5.1 Use cases | UC-11 (Record Inventory Spoilage) and UC-12 (Manage Customer Service Issues) are called "proposed" inside 5.2.6 and 5.2.11, but they are not written out in 5.1, which stops at UC-10. UC-11 is one of the five tested use cases. | Add UC-11 and UC-12 to 5.1 as full use cases (name, actors, description, alternate path, exception path, pre-condition, post-condition). |
| UC-09 name | 5.1 calls it "Audit & Disburse Employee Payroll"; 5.2.4 says it was revised to "Review & Adjust Employee Payroll". | Use the revised name in 5.1. |
| FR-13, FR-14, FR-15 | Listed in Section 2 but have no 5.2.x requirement section and no use case. | Add 5.2.13 to 5.2.15, or state in Section 2 that they are planned for a later sprint. |
| Every requirement in 5.2 | The Sprint 4 brief asks each requirement to list its test cases, for example "Test cases: 3.1, 3.2, 3.5". | Copy the lists from 10.1.7 in the testing section (file 02). |
| Section 6, Users table and login description | Out of date. | See file 01, Part B. |

## 4. Sprint 3 feedback and what to do about it

| Feedback | What it means | What to do in Sprint 4 | Status |
| :--- | :--- | :--- | :--- |
| "Class diagram → 80%. Missing aggregations." | The class diagram only had plain association lines. The grader wants whole–part relationships shown with diamonds. | Use the class diagram in file 01, Part D. It has four compositions (filled diamond) and four aggregations (hollow diamond), and Section 7.3 explains each one. When redrawing it, keep the diamond on the "whole" side. | Drafted. Needs to be drawn into the document. |
| "Sequence diagram → 85%. Missing instances. Recheck format." | In a UML sequence diagram each box at the top is an object, written `name : Class` (for example `appState : AppState`), not only a class or component name. "Format" most likely refers to the standard parts: a lifeline under each object, activation bars while an object is working, solid arrows for calls, dashed arrows for returns. | Section 8 (Behavioral Modeling) needs its sequence diagrams redrawn this way. Two examples in the correct format are in file 02, Section 11.4, and can be reused in Section 8. | Examples drafted. Section 8 owner still has to redraw theirs. |
| "−5%. Different use case diagrams are required." | Sprint 3 had one use case diagram (5.3). The grader expects more than one. The most likely reading is one diagram per actor or per subsystem instead of a single combined diagram. This is my interpretation; if the wording is unclear, ask the instructor. | In 5.3, draw several smaller use case diagrams, for example: (1) authentication and staff, (2) dining and orders, (3) inventory and purchasing, (4) administration and hiring, (5) AI and feedback. Use «include» and «extend» where they apply (for example "Receive delivery" «extend» "Manage purchase orders"; every use case «include» "Log in"). Draw every actor as a stick figure outside the system box, each use case as an oval inside it; `use-case-diagram.svg` in this folder (used in Section 11.6) shows the style. | Not started. Section 5 owner. |
| "Demo is locally hosted. Not complete." | The Sprint 3 demo ran on one computer. | The system is now hosted: web app on GitHub Pages, API and MySQL on Railway. Demo from the public link, not from a local run. Say this in Section 9 and show it in the deployment diagram (file 02, Section 11.5). Before the demo, open the link and log in once to wake the Railway database. | Hosting done. Checked on 9 November 2026: the Railway API answers, it reads the Railway MySQL database (19 tables, 5 user accounts), it rejects requests that have no login, and the GitHub Pages link serves the app. Still to do by hand: log in once on the public link using the Cloud option. |

Links for Section 9:

- Web app: https://jamalford.github.io/ServeSync/
- API: https://servesync-production-d1da.up.railway.app
- GitHub: https://github.com/JamalFord/ServeSync

