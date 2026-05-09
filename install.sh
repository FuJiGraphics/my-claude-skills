#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_TARGET="$HOME/.claude/skills"
EXTERNALS_DIR="$REPO_DIR/_externals"

mkdir -p "$SKILLS_TARGET" "$EXTERNALS_DIR"

link_dir() {
    local src="$1" target="$2"
    if [[ -L "$target" ]]; then
        local cur
        cur="$(readlink "$target")"
        if [[ "$cur" == "$src" ]]; then
            echo "  [skip]  $(basename "$target") (already linked)"
            return
        fi
        echo "  [warn]  $target -> $cur (mismatch); skipping"
        return
    fi
    if [[ -e "$target" ]]; then
        echo "  [warn]  $target exists and is not a symlink; skipping"
        return
    fi
    ln -s "$src" "$target"
    echo "  [ok]    $(basename "$target")"
}

# 1. Local skills
echo "==> Linking local skills..."
shopt -s nullglob
for skill in "$REPO_DIR/skills"/*/; do
    link_dir "${skill%/}" "$SKILLS_TARGET/$(basename "$skill")"
done

# 2. External skills
EXT_FILE="$REPO_DIR/externals.txt"
if [[ -f "$EXT_FILE" ]]; then
    echo "==> Installing external skills..."
    while IFS='|' read -r repo path name || [[ -n "$repo" ]]; do
        repo="${repo%$'\r'}"; path="${path:-}"; name="${name%$'\r'}"
        [[ -z "${repo// /}" || "${repo:0:1}" == "#" ]] && continue
        repo_basename="$(basename "${repo%.git}")"
        repo_dir="$EXTERNALS_DIR/$repo_basename"
        if [[ ! -d "$repo_dir/.git" ]]; then
            echo "  [clone] $repo"
            git clone --depth 1 "$repo" "$repo_dir" >/dev/null 2>&1 || {
                echo "  [error] clone failed: $repo"; continue;
            }
        else
            (cd "$repo_dir" && git pull --ff-only --quiet) 2>/dev/null \
                && echo "  [pull]  $repo_basename" \
                || echo "  [warn]  pull failed: $repo_basename"
        fi
        src="$repo_dir/$path"
        if [[ ! -d "$src" ]]; then
            echo "  [error] missing path: $src"; continue
        fi
        link_dir "$src" "$SKILLS_TARGET/$name"
    done < "$EXT_FILE"
fi

# 3. Plugin marketplaces
MKT_FILE="$REPO_DIR/marketplaces.txt"
if [[ -f "$MKT_FILE" ]]; then
    if command -v claude >/dev/null 2>&1; then
        echo "==> Registering plugin marketplaces..."
        while read -r source || [[ -n "$source" ]]; do
            source="${source%$'\r'}"
            [[ -z "${source// /}" || "${source:0:1}" == "#" ]] && continue
            output="$(claude plugin marketplace add "$source" 2>&1 || true)"
            if echo "$output" | grep -qiE "already|exists"; then
                echo "  [skip]  $source"
            else
                echo "  [ok]    $source"
            fi
        done < "$MKT_FILE"
    else
        echo "==> Skipping marketplaces ('claude' CLI not found)"
    fi
fi

# 4. Plugins
PLG_FILE="$REPO_DIR/plugins.txt"
if [[ -f "$PLG_FILE" ]]; then
    if command -v claude >/dev/null 2>&1; then
        echo "==> Installing plugins..."
        while read -r spec || [[ -n "$spec" ]]; do
            spec="${spec%$'\r'}"
            [[ -z "${spec// /}" || "${spec:0:1}" == "#" ]] && continue
            output="$(claude plugin install "$spec" 2>&1 || true)"
            if echo "$output" | grep -qiE "already"; then
                echo "  [skip]  $spec"
            else
                echo "  [ok]    $spec"
            fi
        done < "$PLG_FILE"
    else
        echo "==> Skipping plugins ('claude' CLI not found)"
    fi
fi

echo "==> Done. Skills: $SKILLS_TARGET"
