# ServeSync Section 7 submission

The report, source code, schema, sample data, verification queries, automated tests and observed demo evidence are included.

Open xcode/ServeSyncLocal/ServeSyncLocal.xcodeproj to use the included working app. The source matches the demonstrated implementation. This project preserves its iOS 27.0 deployment target and Swift 5 language mode; use the matching simulator/Xcode environment. No fresh Xcode build was run while packaging.

The package excludes local Git history and Xcode user interface state. Do not include .venv, database passwords, or backend/pin_lookup.secret in a shared submission. Preserve your local secret for your existing database.

The original README describes setup from scratch. Your demonstrated setup uses MySQL port 3307 and API port 8000. Do not rerun the schema or seed scripts against the already configured demonstration database.

Manual checks passed on October 5, 2026; see the report and evidence/mysql_results.txt. Full integration into the team's restaurant app remains separate.
