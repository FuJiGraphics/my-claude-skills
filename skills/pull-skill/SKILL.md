---
name: pull-skill
description: Pull skills, external skills, plugin marketplaces, and plugins from the user's my-claude-skills repository to the current machine. Use when the user wants to sync their personal skill collection — e.g., after working on another machine, after a fresh install, or after editing the repo directly. Resolves conflicts interactively rather than overwriting.
---

# pull-skill

Synchronize this machine with the user's `my-claude-skills` repo.

## 1. Locate the repository

Check these in order. Use the first one that exists and looks like a clone of `my-claude-skills` (has `install.sh` and `skills/` at root):

1. `~/my-claude-skills`
2. `~/code/my-claude-skills`
3. `~/Desktop/FujiGraphics/my-claude-skills`
4. If none found, ask the user where it lives. If they don't have it cloned, offer to clone it from GitHub (`https://github.com/FuJiGraphics/my-claude-skills.git`) into `~/my-claude-skills` after confirming.

Remember the located path for the rest of this session.

## 2. Pull latest

```sh
cd <repo>
git pull --ff-only
```

If pull fails (diverged history, local uncommitted changes, merge conflicts):
- Report the failure clearly.
- Ask the user how to proceed. Don't force, reset, or stash without explicit permission.

## 3. Run install.sh

```sh
bash install.sh
```

(Use `install.ps1` on Windows.) Capture the output.

## 4. Resolve conflicts

Parse the output. For each line:

- `[ok]`, `[skip]`, `[clone]`, `[pull]` — informational, no action needed.
- `[warn] <target> exists and is not a symlink; skipping` — there's a real directory at the target. Show the user:
  - **Replace with repo's version** — delete the local directory and re-run install (let the symlink win).
  - **Keep local, ignore repo** — do nothing.
  - **Adopt local into repo** — move `~/.claude/skills/<name>` into `<repo>/skills/<name>` (`bash sync.sh` handles this), then re-run install. Tell the user they can commit + push afterward.
- `[warn] <target> -> <other path> (mismatch); skipping` — symlink points somewhere unexpected. Show both paths, ask whether to repoint at the repo or keep the existing target.
- `[error] ...` — surface to the user; don't paper over.

Never silently overwrite or delete user content.

## 5. Verify clean state

After resolving conflicts, run `install.sh` once more and confirm the output is all `[ok]` or `[skip]`.

## 6. Report

Summarize what changed:
- Skills newly linked (count + names)
- External skills cloned/updated
- Marketplaces registered
- Plugins installed
- Conflicts resolved (with the user's choice)

## When NOT to fire

- User wants to **create** a new skill → use `skill-creator` instead.
- User wants to **push** local changes to the repo → use `push-skill`.
- User asks general questions about Claude Code skills → answer directly.
