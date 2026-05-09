---
name: push-skill-select
description: Adopt a USER-SELECTED SUBSET of skills from the active Claude Code scope (project-local `.claude/skills/` if invoked inside a project, otherwise global `~/.claude/skills/`) into the user's my-claude-skills repo, replacing the chosen real directories with symlinks back to the repo. Same mechanism as `push-skill-all` but presents the local skill list first and asks the user which ones to push. The four meta-skills (pull-skill-all, pull-skill-select, push-skill-all, push-skill-select) are filtered out of the picker since they manage themselves. After the skill push, also offers to push guideline files (지침 — CLAUDE.md, convention docs, etc.) with a multi-select picker. This is NOT `git push` — it's the inverse of `pull-skill-select`. Use when the user wants to cherry-pick which local skills to capture into their personal repo.
---

# push-skill-select

Adopt a **chosen subset** of skills from the active Claude Code scope into the `my-claude-skills` repo, then optionally prepare a commit. Same overall mechanism as `push-skill-all`, but with a selection step up front.

This is the inverse of `pull-skill-select` and is **not** a git push — see `push-skill-all` for the rationale.

For pushing **all** un-adopted skills, use `push-skill-all` instead.

## 1. Parse the user's intent

Optional argument may describe which skills they want pushed (e.g., "push refactoring and the new linter one"). Use it to:
- Pre-select matching skills in the list at step 4
- Draft the commit message at step 7

If no argument, just present the full list at step 4 and let the user pick.

## 2. Locate the repository

Same lookup as the other variants:

1. `~/my-claude-skills`
2. `~/code/my-claude-skills`
3. `~/Desktop/FujiGraphics/my-claude-skills`
4. Ask if not found.

## 3. Decide source scope (project vs global)

Same rules as `push-skill-all`:

- **Global** (source = `~/.claude/skills/`) when cwd is `$HOME` or has no project markers.
- **Project** (source = `<cwd>/.claude/skills/`) when cwd is a project dir.
- **Ambiguous** → ask the user.

Tell the user the chosen source scope in one short sentence.

## 4. List candidates and ask the user to pick

Walk `<scope-dir>/*` and classify each entry:

- **Adoptable** — real directory (not a symlink), and `<repo>/skills/<name>` does NOT exist. This is the typical push candidate.
- **Conflict** — real directory, AND `<repo>/skills/<name>` already exists. Adoption requires extra resolution (see step 6).
- **Already managed** — already a symlink into `<repo>/skills/`. Nothing to push.
- **Foreign symlink** — symlink pointing somewhere other than this repo. Show but don't auto-include; ask the user explicitly if they want to repoint it.

**Filter out the four meta-skills** before classifying/presenting: `pull-skill-all`, `pull-skill-select`, `push-skill-all`, `push-skill-select`. These should already be `Already managed` (symlinks into the repo) — listing them in the picker is confusing and could lead to self-referential breakage if someone selects the very skill that's running. If the user explicitly names one of them, handle that case manually outside this skill.

For each remaining candidate, read the local `<scope-dir>/<name>/SKILL.md` description (if present) for context.

Present the list via `AskUserQuestion` with `multiSelect: true`. Each option's label is the skill name; the description includes:
- A short summary (first sentence of the local SKILL.md description, trimmed)
- The status flag (adoptable / conflict / already-managed / foreign-symlink)

By default, show only **adoptable** + **conflict** entries (already-managed adds noise; foreign symlinks need explicit acknowledgment). If the user wants to see those too, ask before listing.

If many candidates, batch as in `pull-skill-select` (filter by status first, or split into two questions). Keep it ergonomic.

If the user selects nothing, stop and tell them no changes were made.

## 5. Adopt the selected skills

For each selected skill, do this manually (per-skill, not via `sync.sh` since `sync.sh` is bulk-only):

```sh
mv <scope-dir>/<name> <repo>/skills/<name>
ln -s <repo>/skills/<name> <scope-dir>/<name>
```

Capture which skills moved and which were skipped. Don't touch `marketplaces.txt` / `plugins.txt` from this skill — that's a global-state concern handled by `push-skill-all` via `sync.sh`. If the user wants to capture marketplace/plugin state too, point them at `push-skill-all`.

## 6. Conflict resolution

If a selected skill is in the **conflict** state (both local dir and repo dir exist with the same name), stop and ask the user:

- **Keep repo version, drop local** — `rm -rf <scope-dir>/<name>`, then symlink from the repo (`ln -s <repo>/skills/<name> <scope-dir>/<name>`). The local copy is discarded.
- **Replace repo version with local** — back up the existing repo skill (e.g., `mv <repo>/skills/<name> <repo>/skills/<name>.bak/`), then move local in. The user may want to diff before deciding.
- **Rename local before adopting** — pick a new name, rename the local dir, then proceed as a normal adoption (no longer a conflict).
- **Skip this one for now** — leave both as-is; drop from the push list.

Never silently overwrite. The user must pick for every conflict.

For **foreign-symlink** entries the user explicitly selected, ask whether to repoint at this repo (replace the symlink) or skip.

## 7. Show the diff

Run `git status` and `git diff` in the repo. Summarize for the user:

- Skills newly adopted (paths under `<repo>/skills/`)
- Modified `SKILL.md` files (rare during a select push, but possible if the user picked an already-managed skill that now differs)
- Anything else (which should be nothing — flag if so)

## 8. Reconcile with intent

Compare the diff against the user's stated intent (if they gave one). If something in the diff wasn't on their list, ask whether to include or revert.

## 9. Offer to commit (optional)

Same as `push-skill-all`:

- Show a draft commit message:
  ```
  Add <skill-name>: <one-line purpose>
  ```
  or for multiple:
  ```
  <verb> skills: <brief>

  - <bullet per change>
  ```
- Ask: edit message? stage relevant only or `git add -A`? commit now? push to remote? **Default for "push to remote": ask, never auto-push.**

## 10. Execute and verify

If the user committed, show `git log -1` and `git status`. If not, leave the working tree dirty for them to inspect or commit manually with `/commit`.

## 11. 지침 (guideline files) — follow-up

After the skill push (and optional commit), ask the user whether to also push 지침 (Korean for "guidelines" — standalone markdown files like `CLAUDE.md`, `CodeConvention.md`, `Architecture.md` that document conventions or context, but are NOT skills with their own `SKILL.md`):

> "지침 파일도 같이 [my-claude-skills 레포로] 옮길까요?"

If they decline, you're done. If they accept, follow the flow below.

### Identify candidates in the source scope

For project scope (cwd is a project dir), candidates include:

1. `<cwd>/CLAUDE.md` — project root instructions
2. `<cwd>/.claude/CLAUDE.md` — Claude-specific project instructions
3. Flat `.md` files directly under `<cwd>/.claude/skills/` (NOT subdirectories — those are skills with their own `SKILL.md`)
4. Flat `.md` files under `<cwd>/.claude/commands/` ONLY if the user explicitly wants slash command docs included (ask first)

For global scope (cwd is `$HOME` or no project markers), candidates include:

1. `~/.claude/CLAUDE.md`
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

Ask the user which layout they prefer if collisions are likely (e.g., two projects each have a `CodeConvention.md`).

Create the destination directory with `mkdir -p` if it doesn't exist.

### Copy or move?

For 지침, **copy** by default. The local copy stays where Claude Code expects it; the repo gets a snapshot.

If the user explicitly wants the repo to be the single source of truth (so future edits land in the repo and projects pick up via `pull-skill-*`), offer to replace the local file with a symlink to the repo's copy after the copy completes. Confirm before making this change.

### Conflicts

If the destination already has a file with the same name:
- **Different contents** → ask: overwrite / keep destination / save as `<name>.from-<project>.md` / skip
- **Same contents** → silent skip

Never silently overwrite a guideline file in the repo — it may have edits from another project.

### Report and optional re-commit

Summarize: which files copied (with destinations), which skipped, conflicts resolved.

If you committed at step 9 and the 지침 follow-up added new repo files, ask whether to amend the commit (only with explicit confirmation), make a follow-up commit, or leave the new files unstaged.

## Safety rules

- **Never `git push` to remote without explicit user confirmation.**
- **Never `git add -A` without showing what it would stage.**
- **Never resolve a name conflict silently** — the user picks for every collision.
- **Never repoint a foreign symlink without explicit confirmation.**
- The `mv` step is destructive to the local scope (the original dir is moved). If anything looks wrong before step 5, stop and ask.

## When NOT to fire

- User wants to push **all** un-adopted skills → use `push-skill-all`.
- User wants to **fetch** from the repo → use `pull-skill-select` (or `pull-skill-all`).
- User wants to **create** a new skill → use `skill-creator` first, then push.
- User just wants to commit existing repo changes (no sync) → use `/commit`.
