---
name: push-skill
description: Capture the user's current local Claude Code state — new or modified skills, newly installed plugins or marketplaces — into their my-claude-skills repository and prepare a git commit. The user typically provides intent as an argument (e.g., "/push-skill add my-new-skill for X" or "/push-skill update foo"). Suggests a commit message and asks before committing or pushing.
---

# push-skill

Capture local Claude Code state into the `my-claude-skills` repo and prepare a commit.

## 1. Parse the user's intent

The user typically provides a short description as argument. Use it to:
- Verify the diff matches their stated intent
- Draft a commit message in their words

If no argument given, infer intent from the actual diff after step 3.

## 2. Locate the repository

Same lookup as `pull-skill`:
1. `~/my-claude-skills`
2. `~/code/my-claude-skills`
3. `~/Desktop/FujiGraphics/my-claude-skills`
4. Ask the user if not found.

## 3. Sync local state into the repo

```sh
cd <repo>
bash sync.sh   # use sync.ps1 on Windows
```

This adopts unmanaged skills (real dirs in `~/.claude/skills/` get moved into `<repo>/skills/` and replaced with symlinks) and appends installed marketplaces/plugins to the corresponding `.txt` files.

Capture the output.

## 4. Show the diff

Run `git status` and `git diff` (and `git diff --cached` if there's anything staged). Summarize for the user:

- New skills adopted (with paths)
- Modified `SKILL.md` files (which skills, what changed in 1-2 lines each)
- New entries in `marketplaces.txt` / `plugins.txt`
- Anything else

## 5. Reconcile with intent

Compare the diff against the user's stated intent:

- **Diff matches intent** → proceed.
- **Diff includes things the user didn't mention** (e.g., they said "add foo" but sync also adopted "bar") → ask: include in this commit, or leave for later?
- **Diff is missing what the user mentioned** (they said "add foo" but no foo in diff) → flag to the user; don't fabricate.

## 6. Draft a commit message

Short, imperative, focused on the why:

```
Add <skill-name>: <one-line purpose>
```

or for multi-skill changes:

```
<verb> skills: <brief>

- <bullet per change>
```

Show the message and ask:
- Edit message?
- Stage only the relevant files (recommended) or `git add -A`?
- Push to remote after commit? **Default: ask, do not auto-push.**

## 7. Execute

Run the commands the user confirmed. Show final `git log -1` and `git status` to confirm.

## Safety rules

- **Never push without explicit user confirmation.**
- **Never `git add -A` without showing what it would stage first.**
- **Never reset, force, or amend** without explicit permission.
- If `sync.sh` would adopt skills the user didn't intend (e.g., from another team's project), ask before running it.

## When NOT to fire

- User wants to **fetch** from the repo → use `pull-skill`.
- User wants to **create** a new skill from scratch → use `skill-creator` first, then `push-skill` to commit it.
- User asks how the repo works → answer directly without committing.
