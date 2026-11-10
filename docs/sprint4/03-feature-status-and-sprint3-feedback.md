# ServeSync Sprint 4 — Feature status and Sprint 3 feedback

This file answers two questions: which of the features promised in the Sprint document are actually built, and what the Sprint 3 grading feedback means for Sprint 4. Status was checked against the code on 9 November 2026 (`main` at commit 9f4b357).

## 1. Short answer

Of the features listed in the Discord conversation:

| Feature | Requirement in the Sprint document | Built? |
| :--- | :--- | :--- |
| Supplier ordering | 5.2.1 (FR-1), UC-05 | **Yes**, working end to end. One part of the use case is missing: cancelling an order. |
| AI inventory prediction | 5.2.10 (FR-10), UC-06 | **No.** There is a "Demand (FR-10)" tab, but every number on it is fixed text typed into the code. No AI and no real data. |
| Customer reviews | 5.2.8 (FR-8), UC-07 | **No.** There is no reviews table and no Google reviews connection. |
| AI customer review summary | 5.2.8 (FR-8), UC-07 | **No.** There is a "Reviews (FR-08)" tab, but its rating, review count, and summaries are fixed text. |
| Reservation management | 5.2.7 (FR-7), UC-03 | **Mostly no.** The database table exists and the API can list reservations. Nothing can create or change one, and the app has no reservations screen. |
| Hiring | 5.2.12 (FR-12), UC-10 | **Mostly no.** The database table exists and the API can list and add applicants. The app has no hiring screen, and hiring statuses cannot be changed through the API. |

So four of the six are not built, one is half built on the server only, and one works. The full list of all 15 requirements is in part 2.

## 2. Feature list (all requirements from Sprint 1 onward)

The Sprint 4 brief asks the team to "print all the features as a list (which you have mentioned from sprint 1)". This table can be used for that. The section numbers are the ones in the Sprint 3 table of contents.

Status meanings:

- **Complete**: works in the app and is stored in the cloud database.
- **Partial**: some of the requirement works; the "What is missing" column says what does not.
- **Server only**: the database table and API exist, but the app has no screen for it.
- **Demo only**: a screen exists but shows fixed sample text.
- **Not started**: nothing exists.

| No. | Section | Requirement | Use case | Status | What exists | What is missing |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| FR-1 | 5.2.1 | Incoming inventory and supplier management | UC-05 | Partial (main flow complete) | Create a purchase order, receive a full or partial delivery, stock updated, receipts and audit records saved. In the app under Inventory → Supplier Orders. | Cancelling an order ("Remove Order" in UC-05). Editing supplier contact details. Supplier invoices. Search and sort. |
| FR-2 | 5.2.2 | User management and authentication | UC-01, UC-08 | Partial | PIN login in the app. Full account management in the API: create, deactivate, reactivate, change role, reset PIN, end a session. | An administrator screen in the app for managing accounts. |
| FR-3 | 5.2.3 | Supply database and access permissions | UC-04 | Partial | Inventory table and list. Role checks on every protected API operation. | Adding or editing inventory items. Manual stock adjustment. |
| FR-4 | 5.2.4 | Payroll management | UC-09 | Partial | Shifts screen with hours, pay rate editing, and weekly payroll estimate. API can list payroll records. | Pay rate edits are not saved to the database. Payroll adjustments with a recorded reason. Pay-period summary. |
| FR-5 | 5.2.5 | Employee management and time tracking | UC-01 | Complete for time tracking | Clock in and clock out, separate from login and logout, stored in the Payroll table. Duplicate shifts prevented. | Employee profile editing. Clock-in records a fixed $15.00 rate instead of the employee's own rate. |
| FR-6 | 5.2.6 | Spoilage tracking | UC-11 | Complete | Record spoilage with item, quantity, reason, and notes. Stock deducted once. Audit log shown in the app. | "Standard freshness data entry" from the requirement text (for example an expiry date field). |
| FR-7 | 5.2.7 | Reservation management | UC-03 | Server only (read) | Reservations table. API can list reservations. | Create, update, cancel, complete, mark no-show. Any app screen. |
| FR-8 | 5.2.8 | AI-powered review summaries | UC-07 | Demo only | "Reviews (FR-08)" tab with fixed sample text. | Reviews table. Google reviews connection. AI summarisation. "Unavailable" status. |
| FR-9 | 5.2.9 | Customer order management | UC-02 | Partial | Floor plan, seating with party size, ordering by seat, totals with tax, kitchen display, live sync between devices through Firestore. | Orders are not saved to the MySQL tables. No "complete order" or payment step. No order search or history. |
| FR-10 | 5.2.10 | AI-powered consumption analytics | UC-06 | Demo only | "Demand (FR-10)" tab and "AI Copilot" chat with fixed sample answers. | Any real analysis. Use of real consumption data. Reporting period selection. Link from a recommendation to a purchase order. |
| FR-11 | 5.2.11 | Customer service administration | UC-12 | Server only | Service issues table. API can list, create, and resolve issues. | Any app screen. Search. |
| FR-12 | 5.2.12 | Applications, hiring, and onboarding | UC-10 | Server only | Applicants table. API can list and add applicants. | Changing a hiring status through the API (the code exists but is not connected to a route). Document upload. Onboarding tracking. Creating an account from a hired applicant. Any app screen. |
| FR-13 | Section 2 only | Menu management (client addition) | none yet | Not started | A Menu_Items table exists and is seeded. | Add, edit, and remove menu items. The app's menu is built into the code. |
| FR-14 | Section 2 only | Price management (client addition) | none yet | Not started | — | Price editing and a price change history. |
| FR-15 | Section 2 only | Third-party delivery platform integration (client addition) | none yet | Not started | — | Everything. |

Count: 1 complete, 1 complete for its main part, 5 partial, 3 server only, 2 demo only, 3 not started.

### What "demo only" means for the two AI features

The app has an AI sheet with three tabs. All three show text that is written directly in the file `mobile/lib/screens/ai/ai_insights_sheet.dart`:

- **Demand (FR-10):** "128 covers tonight", three forecast cards (tomatoes, beef, salmon) with fixed stock and usage figures. The figures do not come from the inventory data, so they do not change when stock changes.
- **Reviews (FR-08):** a 4.8 rating, "94% Positive Sentiment (48 Reviews Analyzed)", and three fixed insight cards.
- **AI Copilot:** a chat box that picks one of a few prepared answers by looking for words such as "profit" or "reorder" in the question.

If these tabs are shown in the demo, they should be described as a mock-up of the planned feature. Presenting them as working AI would be inaccurate.

## 3. Corrections needed in Section 5 of the document

These are places where the Sprint 3 text no longer matches the system. They are in Section 5, so whoever owns that section should make them.

| Where | Problem | Suggested change |
| :--- | :--- | :--- |
| FR-5 (Section 2 and 5.2.5) | The text says "Upon successful login, the system shall record the employee's clock-in timestamp … and record a clock-out timestamp upon session termination." The same document says the client asked for clock-in and clock-out to be explicit and separate from login. The system follows the client. | Reword to: "The system shall record a clock-in timestamp when the employee chooses to clock in and a clock-out timestamp when the employee chooses to clock out. Logging in or out shall not start or end a shift." |
| 5.1 Use cases | UC-11 (Record Inventory Spoilage) and UC-12 (Manage Customer Service Issues) are called "proposed" inside 5.2.6 and 5.2.11, but they are not written out in 5.1, which stops at UC-10. UC-11 is one of the five tested use cases. | Add UC-11 and UC-12 to 5.1 as full use cases (name, actors, description, alternate path, exception path, pre-condition, post-condition). |
| UC-09 name | 5.1 calls it "Audit & Disburse Employee Payroll"; 5.2.4 says it was revised to "Review & Adjust Employee Payroll". | Use the revised name in 5.1. |
| FR-13, FR-14, FR-15 | Listed in Section 2 but have no 5.2.x requirement section and no use case. | Add 5.2.13 to 5.2.15, or state in Section 2 that they are planned for a later sprint. |
| Every requirement in 5.2 | The Sprint 4 brief asks each requirement to list its test cases, for example "Test cases: 3.1, 3.2, 3.5". | Copy the lists from 10.1.8 in the testing draft (file 02). |
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

## 5. What can realistically be done before the deadline

The document is due on 10 November before class. Building the missing features properly is not possible in that time, and the brief grades the document sections, so the document should come first.

1. **Document (required):** Sections 6 and 7 from file 01, Sections 10 and 11 from file 02, the Section 5 corrections in part 3 above, new use case diagrams, and redrawn sequence diagrams.
2. **Be accurate about scope:** in Section 9, list what is implemented and what is planned, using the table in part 2. This is safer than leaving the reader to assume everything in Section 5 works.
3. **If there is time for code, in order of value for effort:**
   - Connect the hiring status update to a route in the API (the function already exists; it needs a few lines).
   - Add a cancel action for purchase orders (finishes UC-05).
   - Add create and update for reservations in the API (the table already exists).
   - Make the "Demand (FR-10)" tab read real inventory quantities and reorder levels instead of fixed text. This would be a rule-based forecast, not AI, and should be described that way.
4. **Leave for Sprint 5:** real AI features (FR-8, FR-10), app screens for reservations, hiring, user management and customer service, saving orders to MySQL, and FR-13 to FR-15.
