#!/bin/bash
set -e
echo "Running ServeSync Automated Verification Test Suite..."
PYTHON="${PYTHON:-/usr/bin/python3}"
"$PYTHON" tests/test_sprint3_backend.py
