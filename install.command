#!/usr/bin/env bash
# Double-click wrapper for install.sh (macOS only).
# Finder will open this in Terminal automatically.
cd "$(dirname "$0")"
bash install.sh
status=$?
echo ""
if [[ $status -eq 0 ]]; then
    echo "✓ Install finished. Press any key to close..."
else
    echo "✗ Install failed (exit $status). Press any key to close..."
fi
read -n 1 -s
