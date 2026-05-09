---
name: push-skill-all
description: Adopt ALL skills currently installed in the active Claude Code scope (project-local `.claude/skills/` if invoked inside a project, otherwise global `~/.claude/skills/`) into the user's my-claude-skills repo, replacing real directories with symlinks pointing back to the repo. This is NOT `git push` — it's the inverse of `pull-skill-all`: source = current scope, destination = my-claude-skills repo. The four meta-skills (pull-skill-all, pull-skill-select, push-skill-all, push-skill-select) are excluded from the adoption since they're already managed via the repo's symlinks. After adoption, also offers to push guideline files (지침 — CLAUDE.md, convention docs, etc.) with a multi-select picker. Optionally drafts a commit at the end. Use when the user wants to bulk-capture local skill changes into their personal repo. For selecting only a subset, use `push-skill-select` instead.
---

# push-skill-all

Adopt **every** skill in the active Claude Code scope into the `my-claude-skills` repo, then optionally prepare a commit.

This is the inverse of `pull-skill-all`:

- `pull-skill-all`: my-claude-skills repo → current scope (project or global)
- `push-skill-all`: current scope (project or global) → my-claude-skills repo

It is **not** a git push. The "push" refers to pushing skills from the live Claude Code scope into the repo. A subsequent `git commit` / `git push` is offered separately at the end and never runs without explicit confirmation.

For pushing only some skills (not all), use `push-skill-select` instead.

## 1. Parse the user's intent

The user may provide a short description as argument. Use it to:
- Verify the diff matches their stated intent at step 4
- Draft a commit message in their words

If no argument, infer intent from the actual diff after sync.

## 2. Locate the repository

Same lookup as `pull-skill-all`:

1. `~/my-claude-skills`
2. `~/code/my-claude-skills`
3. `~/Desktop/FujiGraphics/my-claude-skills`
4. Ask the user if not found.

## 3. Decide source scope (project vs global)

Inspect the **current working directory** (cwd, not the repo path) using the same rules as `pull-skill-all`:

- **Global scope** (source = `~/.claude/skills/`) when cwd is `$HOME` or has no project markers (`.claude/`, `.git/`, `CLAUDE.md`, `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, etc.).
- **Project scope** (source = `<cwd>/.claude/skills/`) when cwd is a project directory.
- **Ambiguous** — ask the user which scope to push from.

Tell the user the chosen source scope in one short sentence before sync.

## 4. Run sync.sh against the chosen scope

`sync.sh` adopts unmanaged skills (real dirs in the source scope get **moved** into `<repo>/skills/<name>` and replaced with symlinks pointing back). It also syncs `marketplaces.txt` / `plugins.txt` (these only make sense for global scope — `claude plugin list` is global, not per-project).

```sh
cd <repo>
SKILLS_TARGET="<chosen-source-dir>" bash sync.sh
```

Where `<chosen-source-dir>` is the scope dir resolved at step 3 (e.g., `~/.claude/skills` or `<cwd>/.claude/skills`).

Capture the output. Watch for these markers:

- `[adopt] <name> -> skills/<name>` — successfully moved into the repo
- `[skip] <name> (already symlinked)` — already managed, no change
- `[warn] skills/<name> already exists; resolve manually` — **conflict**: the repo already has a skill with that name AND there's also a real local dir with the same name. **Stop and ask the user** before going further. Options:
  - **Keep repo version, discard local** — delete the local dir; re-run install via `pull-skill-all` to symlink back.
  - **Replace repo version with local** — back up the existing repo skill (e.g., rename to `<name>.bak/`), then move local in.
  - **Rename local before adopting** — pick a new name, rename the local dir, re-run sync.
  - **Skip this one for now** — leave both as-is.
- `[warn] <name> is not a directory; skipping` — surface to user.

Never silently overwrite or merge. The user must explicitly choose for any conflict.

**Self-exclusion** — the four meta-skills (`pull-skill-all`, `pull-skill-select`, `push-skill-all`, `push-skill-select`) should naturally show up as `[skip] (already symlinked)` since they're already managed by this repo. If for some reason `sync.sh` reports `[adopt]` for one of them (it shouldn't — that would mean the symlink got broken and a real dir replaced it), pause and ask the user before continuing. Don't surface them in the user-facing diff/report unless the user asks — they're plumbing, not the payload.

## 5. Show the diff

Run `git status` and `git diff` (and `git diff --cached` if anything is staged). Summarize for the user:

- New skills adopted (with paths)
- Modified `SKILL.md` files (which skills, what changed in 1-2 lines each)
- New entries in `marketplaces.txt` / `plugins.txt` (global scope only — flag if these appear during a project-scope push, since plugin/marketplace state is global)
- Anything else

## 6. Reconcile with intent

Compare the diff against the user's stated intent:

- **Diff matches intent** → proceed.
- **Diff includes things the user didn't mention** (e.g., they said "add foo" but sync also adopted "bar") → ask: include in this commit, or leave for later?
- **Diff is missing what the user mentioned** (they said "add foo" but no foo in diff) → flag to the user; don't fabricate.

## 7. Offer to commit (optional, opt-in)

This step is separate from the sync itself. Sync alone is the "skill push" — git operations are a convenience.

Show a draft commit message, short and imperative:

```
Add <skill-name>: <one-line purpose>
```

or for multi-skill changes:

```
<verb> skills: <brief>

- <bullet per change>
```

Ask the user:
- Edit message?
- Stage only the relevant files (recommended) or `git add -A`?
- Commit now? **Default: yes if user says go, no otherwise.**
- Push to remote after commit? **Default: ask, do not auto-push.**

## 8. Execute and verify

If the user opted to commit, run the commands they confirmed. Show final `git log -1` and `git status`.

If they declined, just leave the working tree dirty for them to inspect — they may want to commit manually with `/commit`.

## 9. 지침 (guideline files) — follow-up

After the sync (and optional commit), ask the user whether to also push 지침 (Korean for "guidelines" — standalone markdown files like `CLAUDE.md`, `CodeConvention.md`, `Architecture.md` that document conventions or context, but are NOT skills with their own `SKILL.md`):

> "지침 파일도 같이 [my-claude-skills 레포로] 옮길까요?"

If they decline, you're done. If they accept, follow the flow below.

### Identify candidates in the source scope

For project scope (cwd is a project dir), candidates include:

1. `<cwd>/CLAUDE.md` — project-level instructions at the repo root
2. `<cwd>/.claude/CLAUDE.md` — Claude-specific project instructions
3. Flat `.md` files directly under `<cwd>/.claude/skills/` (NOT subdirectories — those are skills with their own `SKILL.md`)
4. Flat `.md` files under `<cwd>/.claude/commands/` ONLY if the user explicitly asks to include slash commands (those are typically a separate concern; ask before listing)

For global scope (cwd is `$HOME` or no project markers), candidates include:

1. `~/.claude/CLAUDE.md` — global Claude instructions
2. Flat `.md` files directly under `~/.claude/skills/`

If no candidates exist, tell the user and stop.

### Present a multi-select with as many options as there are real candidates

The user wants all candidates visible at once.

- **4 or fewer candidates** — `AskUserQuestion` with `multiSelect: true`. Each option's label is the relative path; description includes file size and a short preview (first non-empty line, ~80 chars).
- **More than 4 candidates** — present a numbered text list and parse the user's reply. Example:

  ```
  옮길 수 있는 지침 파일:
   1. CLAUDE.md (1.2 KB — "프로젝트 개요")
   2. .claude/CLAUDE.md (8.3 KB — "참조 문서, 주요 패키지")
   3. .claude/skills/Architecture.md (12 KB — "엔티티 계층 참조")
   4. .claude/skills/CodeConvention.md (7.9 KB — "변수명·접두사 규칙")
   5. .claude/skills/SpecData.md (4.4 KB — "스펙 데이터 파이프라인")
   6. .claude/skills/UserData.md (3.5 KB — "유저 데이터 구조")

  옮길 항목을 골라주세요 (예: "1,3,4" 또는 "all" 또는 "none"):
  ```

  Parse: `all` / `none` / comma-separated numbers. Lenient about whitespace/punctuation.

### Decide where each selected file lands in the repo

Default destination structure:

- `<repo>/guidelines/<filename>` — preferred flat layout
- `<repo>/guidelines/<project-name>/<filename>` — when pushing from a project and the user wants per-project namespacing

Ask the user which layout they prefer if they have project-scope guidelines that might collide across projects (e.g., two different projects each have a `CodeConvention.md`).

Create the destination directory with `mkdir -p` if it doesn't exist.

### Copy or move?

For 지침, **copy** by default (don't move). The local copy stays where Claude Code expects it; the repo gets a snapshot.

If the user explicitly wants the repo to be the single source of truth (so future edits land in the repo and projects pick up via `pull-skill-*`), offer to replace the local file with a symlink to the repo's copy after the copy completes. Confirm before making this change.

### Conflicts

If the destination already has a file with the same name:
- **Different contents** → ask: overwrite / keep destination / save as `<name>.from-<project>.md` / skip
- **Same contents** → silent skip

Never silently overwrite a guideline file in the repo — it may have edits from another project.

### Report and optional re-commit

After 지침 follow-up, summarize: which files copied (with destinations), which skipped, conflicts resolved.

If you committed at step 7 and the 지침 follow-up added new repo files, ask whether to amend the commit (only with explicit confirmation), make a follow-up commit, or leave the new files unstaged.

## Safety rules

- **Never push to remote without explicit user confirmation.**
- **Never `git add -A` without showing what it would stage first.**
- **Never reset, force, or amend** without explicit permission.
- **Never resolve a `[warn] skills/<name> already exists` conflict silently** — the user must pick.
- If `sync.sh` would adopt skills the user didn't intend (e.g., from another team's project that happens to be in the same scope), ask before running it.

## When NOT to fire

- User wants to push only **some** skills, not all → use `push-skill-select`.
- User wants to **fetch** from the repo into the current scope → use `pull-skill-all` (or `pull-skill-select`).
- User wants to **create** a new skill from scratch → use `skill-creator` first, then `push-skill-all` to capture it into the repo.
- User just wants to commit the repo's working tree (no sync needed) → use `/commit` directly.
- User asks how the repo works → answer directly without running anything.
