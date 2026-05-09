#!/usr/bin/env bash
# Double-click wrapper for sync.sh (macOS only).
# Finder will open this in Terminal automatically.
cd "$(dirname "$0")"
bash sync.sh
status=$?
echo ""
if [[ $status -eq 0 ]]; then
    echo "✓ Sync finished. Review with \`git diff\`. Press any key to close..."
else
    echo "✗ Sync failed (exit $status). Press any key to close..."
fi
read -n 1 -s
