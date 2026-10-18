@echo off
REM ============================================================================
REM ServeSync Sprint 3: Start Local API Backend Server
REM Runs on Windows / macOS with Python 3 without requiring any IDE.
REM ============================================================================
echo Starting ServeSync API Backend on port 8000...
set PIN_LOOKUP_SECRET=servesync-super-secret-lookup-key-2026-sprint3
set DB_NAME=database\servesync_dev.db
set PORT=8000
python backend\server.py
