#!/usr/bin/env bash
# Pull current local Claude Code state back into the repo:
#   - Adopt unmanaged skills in ~/.claude/skills/ into skills/ + symlink
#   - Sync marketplaces.txt from registered marketplaces
#   - Sync plugins.txt from installed plugins
# Does NOT commit. Review with `git diff` and commit yourself.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$REPO_DIR/skills"
SKILLS_TARGET="${SKILLS_TARGET:-$HOME/.claude/skills}"

mkdir -p "$SKILLS_DIR"

# --- 1. Adopt unmanaged skills ---
echo "==> Scanning $SKILLS_TARGET for unmanaged skills..."
if [[ -d "$SKILLS_TARGET" ]]; then
    shopt -s nullglob
    for entry in "$SKILLS_TARGET"/*; do
        [[ -e "$entry" ]] || continue
        name="$(basename "$entry")"
        if [[ -L "$entry" ]]; then
            echo "  [skip]  $name (already symlinked)"
            continue
        fi
        if [[ ! -d "$entry" ]]; then
            echo "  [warn]  $name is not a directory; skipping"
            continue
        fi
        if [[ -e "$SKILLS_DIR/$name" ]]; then
            echo "  [warn]  skills/$name already exists; resolve manually"
            continue
        fi
        mv "$entry" "$SKILLS_DIR/$name"
        ln -s "$SKILLS_DIR/$name" "$entry"
        echo "  [adopt] $name -> skills/$name"
    done
fi

# --- helpers ---
append_unique() {
    local file="$1" line="$2"
    if [[ -f "$file" ]] && grep -qFx "$line" "$file"; then
        echo "  [skip]  $line"
        return
    fi
    [[ -f "$file" ]] || : > "$file"
    # ensure trailing newline before appending
    [[ -s "$file" && -z "$(tail -c 1 "$file")" ]] || echo "" >> "$file"
    echo "$line" >> "$file"
    echo "  [add]   $line"
}

# --- 2. Sync marketplaces.txt ---
MKT_FILE="$REPO_DIR/marketplaces.txt"
if command -v claude >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    echo "==> Syncing marketplaces.txt from \`claude plugin marketplace list --json\`..."
    mkt_json="$(claude plugin marketplace list --json 2>/dev/null || echo '[]')"
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        append_unique "$MKT_FILE" "$entry"
    done < <(printf '%s' "$mkt_json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for m in data:
    s = m.get('source')
    if s == 'github' and m.get('repo'):
        print(m['repo'])
    elif s == 'git' and m.get('url'):
        print(m['url'])
    elif s == 'local' and m.get('path'):
        print(m['path'])
    elif m.get('url'):
        print(m['url'])
")
fi

# --- 3. Sync plugins.txt ---
PLG_FILE="$REPO_DIR/plugins.txt"
if command -v claude >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    echo "==> Syncing plugins.txt from \`claude plugin list --json\`..."
    plg_json="$(claude plugin list --json 2>/dev/null || echo '[]')"
    count=0
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        append_unique "$PLG_FILE" "$entry"
        count=$((count + 1))
    done < <(printf '%s' "$plg_json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for p in data:
    name = p.get('name') or p.get('plugin')
    if not name:
        continue
    market = p.get('marketplace') or p.get('source')
    print(f'{name}@{market}' if market else name)
")
    [[ $count -eq 0 ]] && echo "  [info]  no plugins installed"
fi

echo "==> Done. Review with \`git diff\` and commit."
