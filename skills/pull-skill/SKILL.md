---
name: pull-skill
description: Install skills from the user's local my-claude-skills repo into the appropriate scope based on the current working directory — project-local `.claude/skills/` if invoked inside a project, otherwise global `~/.claude/skills/`. Does NOT do `git pull`; the local repo is treated as the source of truth. Use when the user wants to make their personal skill collection available in the current context.
---

# pull-skill

Install skills from the local `my-claude-skills` repo into the right scope for the current working directory. **No `git pull`** — the local repo is the source. If the user wants to refresh from GitHub, that's a separate step they'll ask for explicitly.

## 1. Locate the repository

Check these in order. Use the first one that exists and looks like a clone of `my-claude-skills` (has `install.sh` and `skills/` at root):

1. `~/my-claude-skills`
2. `~/code/my-claude-skills`
3. `~/Desktop/FujiGraphics/my-claude-skills`
4. If none found, ask the user where it lives. If they don't have it, offer to clone (`https://github.com/FuJiGraphics/my-claude-skills.git`) — but only after confirming.

Remember the path for the rest of the session.

## 2. Decide install scope (project vs global)

Inspect the **current working directory** (the user's cwd, not the repo path):

- **Global scope** (`~/.claude/skills/`) when ANY of these is true:
  - cwd is `$HOME` itself
  - cwd has no project markers (none of: `.claude/`, `.git/`, `CLAUDE.md`, `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, etc.)
- **Project scope** (`<cwd>/.claude/skills/`) when cwd is a project directory (has at least one of the markers above) and is not `$HOME`.
- **Ambiguous** — if the signals conflict (e.g. cwd is `$HOME` but has `.git/`, or you can't tell), ask the user which scope they want before continuing.

Tell the user which scope you picked and why in one short sentence before running install.

## 3. Run install.sh with the chosen target

Pass the destination via the `SKILLS_TARGET` env var:

```sh
cd <repo>
SKILLS_TARGET="<chosen-skills-dir>" bash install.sh
```

For project scope, `<chosen-skills-dir>` is `<cwd>/.claude/skills` (create the parent `.claude/` if missing — `install.sh` will `mkdir -p` the skills dir itself, but the parent project dir must exist).

Capture the output. (On Windows use `install.ps1`; note the current `install.ps1` does not yet read `SKILLS_TARGET` — flag this to the user if they're on Windows.)

## 4. Resolve conflicts

Parse the output. For each line:

- `[ok]`, `[skip]`, `[clone]`, `[pull]` — informational, no action needed. (`[pull]` here refers to external-skill repos under `_externals/`, not the main repo.)
- `[warn] <target> exists and is not a symlink; skipping` — there's a real directory at the target. Show the user:
  - **Replace with repo's version** — delete the local directory and re-run install (let the symlink win).
  - **Keep local, ignore repo** — do nothing.
  - **Adopt local into repo** — move the existing skill into `<repo>/skills/<name>` (`bash sync.sh` handles this for global scope; for project scope you'll need to move it manually), then re-run install.
- `[warn] <target> -> <other path> (mismatch); skipping` — symlink points somewhere unexpected. Show both paths, ask whether to repoint at the repo or keep the existing target.
- `[error] ...` — surface to the user; don't paper over.

Never silently overwrite or delete user content.

## 5. Verify clean state

After resolving conflicts, run `install.sh` once more (with the same `SKILLS_TARGET`) and confirm the output is all `[ok]` or `[skip]`.

## 6. Report

Summarize what changed:
- Scope chosen (project vs global) and the target path
- Skills newly linked (count + names)
- External skills cloned/updated
- Marketplaces / plugins (only meaningful for global scope)
- Conflicts resolved (with the user's choice)

## When NOT to fire

- User wants to **create** a new skill → use `skill-creator`.
- User wants to **push** local changes back to the repo → use `push-skill`.
- User wants to refresh the local repo from GitHub → that's a `git pull` they should ask for explicitly; don't do it as part of this skill.
- User asks general questions about Claude Code skills → answer directly.
