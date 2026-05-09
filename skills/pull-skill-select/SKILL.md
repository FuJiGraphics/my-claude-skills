---
name: pull-skill-select
description: Install a USER-SELECTED SUBSET of skills from the local my-claude-skills repo into the appropriate scope (project-local `.claude/skills/` if invoked inside a project, otherwise global `~/.claude/skills/`). Same mechanism as `pull-skill-all` but presents the available skill list first and asks the user which ones to install. The four meta-skills (pull-skill-all, pull-skill-select, push-skill-all, push-skill-select) are filtered out of the picker since they manage themselves. After the skill install, also offers to pull guideline files (지침 — CLAUDE.md, convention docs, etc.) with a multi-select picker. Does NOT do `git pull`. Use when the user wants to cherry-pick which skills to install in the current context — phrases like "pull some skills", "install just X and Y", "which skills should I add".
---

# pull-skill-select

Install a **chosen subset** of skills from the local `my-claude-skills` repo into the right scope for the current working directory. Same overall mechanism as `pull-skill-all`, but with a selection step up front.

For installing **all** skills, use `pull-skill-all` instead.

## 1. Locate the repository

Same lookup as `pull-skill-all`:

1. `~/my-claude-skills`
2. `~/code/my-claude-skills`
3. `~/Desktop/FujiGraphics/my-claude-skills`
4. Ask the user if not found; offer to clone (`https://github.com/FuJiGraphics/my-claude-skills.git`) only after confirming.

## 2. Decide install scope (project vs global)

Same rules as `pull-skill-all`:

- **Global** (`~/.claude/skills/`) when cwd is `$HOME` or has no project markers.
- **Project** (`<cwd>/.claude/skills/`) when cwd is a project directory.
- **Ambiguous** → ask the user.

Tell the user the chosen scope in one short sentence.

## 3. List available skills and ask the user to pick

List every skill directory directly under `<repo>/skills/`:

```sh
ls -1 <repo>/skills/
```

**Filter out the four meta-skills** before presenting: `pull-skill-all`, `pull-skill-select`, `push-skill-all`, `push-skill-select`. These manage themselves — listing them in the picker is confusing (the user would have to use one of them to install another) and can lead to self-referential breakage if the symlink they're running from gets replaced mid-operation. If the user explicitly asks for them by name, install them with a one-off `ln -s` outside this skill.

For each remaining candidate, read the `description` field from `<repo>/skills/<name>/SKILL.md` frontmatter (if present) so the user has context.

For each candidate, also check whether it's already linked in the chosen scope:

- If `<scope-dir>/<name>` is a symlink pointing into the repo → mark as **already installed** (still listable, but pre-flag).
- If `<scope-dir>/<name>` exists as a real dir → mark as **conflict** (skill name collides with a local non-symlinked dir).
- Otherwise → **available**.

Present the list to the user via `AskUserQuestion` with `multiSelect: true`. Each option's label is the skill name; the description includes:
- A short summary (first sentence of the SKILL.md description, trimmed)
- The status flag (already-installed / conflict / available)

If the list is too long for one question (more than 4 options), batch sensibly: first ask the user to filter by status (e.g., "only show available", "include already-installed too"), or split into two questions if there are many candidates. Keep it ergonomic — the user shouldn't have to scroll through 30 toggles.

If the user selects nothing, stop and tell them no changes were made.

## 4. Install the selected subset

For each selected skill name, create a symlink in the scope dir:

```sh
ln -s <repo>/skills/<name> <scope-dir>/<name>
```

(Make sure `<scope-dir>` exists first — create with `mkdir -p` if needed.)

If a skill the user selected is in the **conflict** state from step 3 (real dir at the scope target), don't proceed silently. Ask:
- **Replace with repo's version** — `rm -rf <scope-dir>/<name>` then create the symlink.
- **Adopt local into repo first** — move `<scope-dir>/<name>` into `<repo>/skills/<name>` (only if no repo version exists), then re-run. If a repo version already exists, this is a deeper conflict — surface it and stop.
- **Keep local, skip this one** — drop it from the install list.

If the skill is **already installed** and matches the same target, nothing to do — report `[skip]` and move on.

If the user wants external skills (under `_externals/`) too, point them at `pull-skill-all`, which calls `install.sh` (handles externals/marketplaces/plugins). `pull-skill-select` deliberately stays scoped to the repo's first-party skills under `skills/` to keep selection simple.

## 5. Report

Summarize what changed:

- Scope chosen (project vs global) and the target path
- Skills installed (count + names)
- Skills skipped (already-installed, no change)
- Conflicts resolved (with the user's choice for each)
- Skills the user did not select (still available for a later run)

## 6. 지침 (guideline files) — follow-up

After the skill install, ask the user whether to also pull 지침 (Korean for "guidelines" — standalone markdown files like `CLAUDE.md`, `CodeConvention.md`, `Architecture.md` that document conventions or context, but are NOT skills with their own `SKILL.md`):

> "지침 파일도 같이 가져올까요?"

If they decline, you're done. If they accept, follow the flow below.

### Identify candidates in the repo

Scan the repo for guideline-like files in this order:

1. `<repo>/guidelines/**/*.md` — preferred location if it exists
2. `<repo>/references/**/*.md` — alternative location
3. Any flat `.md` files at the repo root that aren't standard repo files (skip `README.md`, `externals.txt`, etc.)
4. Anywhere else the user mentions when asked

If no guideline files exist anywhere, tell the user there's nothing to pull and stop.

### Present a multi-select with as many options as there are real candidates

The user wants to see all candidates at once, not a tiny subset.

- **4 or fewer candidates** — use `AskUserQuestion` with `multiSelect: true`. Each option's label is the relative path; description includes file size and a short preview (first non-empty line, trimmed to ~80 chars).
- **More than 4 candidates** — `AskUserQuestion` only allows up to 4 options per call, so present a numbered text list instead and ask for selection. Example:

  ```
  가져올 수 있는 지침 파일:
   1. guidelines/CLAUDE.md (1.2 KB — "프로젝트 개요")
   2. guidelines/Architecture.md (12 KB — "엔티티 계층 참조")
   3. guidelines/CodeConvention.md (7.9 KB — "변수명·접두사 규칙")
   4. guidelines/SpecData.md (4.4 KB — "스펙 데이터 파이프라인")
   5. guidelines/UserData.md (3.5 KB — "유저 데이터 구조")
   6. references/StateMachine.md (2.8 KB — "상태 머신 패턴 노트")

  가져올 항목을 골라주세요 (예: "1,3,4" 또는 "all" 또는 "none"):
  ```

  Parse: `all` → every candidate, `none` → cancel, comma-separated numbers → that subset. Be lenient about whitespace and trailing punctuation.

### Decide where each selected file lands at the destination

For each selected file, the default destination is one of:
- Project scope: `<cwd>/.claude/<filename>` (or `<cwd>/<filename>` for `CLAUDE.md` if the project keeps it at the root)
- Global scope: `~/.claude/<filename>`

Confirm with the user if the default is non-obvious.

Copy (don't symlink) — guideline files are usually edited per-project and shouldn't be tied back to the repo. The user can manually re-sync later via `push-skill-*` if they want.

### Conflicts

If the destination already has a file with the same name:
- **Different contents** → ask: overwrite / keep destination / save as `<name>.from-repo.md` / skip
- **Same contents** → silent skip with a `[skip]` log line

Never silently overwrite a guideline file — they often hold project-specific tweaks.

### Report

After 지침 follow-up, summarize: which files copied, which skipped, which had conflicts and how they were resolved.

## When NOT to fire

- User wants to install **all** skills → use `pull-skill-all`.
- User wants to **create** a new skill → use `skill-creator`.
- User wants to **push** local changes back to the repo → use `push-skill-select` (or `push-skill-all`).
- User wants to refresh the local repo from GitHub → that's a `git pull` they should ask for explicitly.
