#!/bin/bash
# ==============================================================================
# ServeSync Sprint 3: Start Local API Backend Server
# Runs on macOS / Linux terminal without requiring any IDE.
# ==============================================================================
set -e
echo "Starting ServeSync API Backend on port 8000..."
export PIN_LOOKUP_SECRET="servesync-super-secret-lookup-key-2026-sprint3"
export DB_NAME="database/servesync_dev.db"
export API_HOST="0.0.0.0"
export PORT=8000
PYTHON="${PYTHON:-/usr/bin/python3}"
"$PYTHON" backend/server.py
