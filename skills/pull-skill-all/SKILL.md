---
name: pull-skill-all
description: Install ALL skills from the user's local my-claude-skills repo into the appropriate scope based on the current working directory — project-local `.claude/skills/` if invoked inside a project, otherwise global `~/.claude/skills/`. Does NOT do `git pull`; the local repo is treated as the source of truth. The four meta-skills (pull-skill-all, pull-skill-select, push-skill-all, push-skill-select) are excluded from reports since they manage themselves. After the skill install, also offers to pull guideline files (지침 — CLAUDE.md, convention docs, etc.) with a multi-select picker. Use when the user wants to bulk-install their entire personal skill collection in the current context. For selecting only a subset, use `pull-skill-select` instead.
---

# pull-skill-all

Install **every** skill from the local `my-claude-skills` repo into the right scope for the current working directory. **No `git pull`** — the local repo is the source. If the user wants to refresh from GitHub, that's a separate step they'll ask for explicitly.

For installing only some skills (not all), use `pull-skill-select` instead.

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
- `[warn] <target> exists and is not a symlink; skipping` — there's a real directory at the target with the same name as a repo skill. Show the user the conflict and ask:
  - **Replace with repo's version** — delete the local directory and re-run install (let the symlink win).
  - **Keep local, ignore repo** — do nothing.
  - **Adopt local into repo** — move the existing skill into `<repo>/skills/<name>` (`SKILLS_TARGET=<scope-dir> bash sync.sh` handles this), then re-run install.
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

**Self-exclusion** — the four meta-skills (`pull-skill-all`, `pull-skill-select`, `push-skill-all`, `push-skill-select`) manage themselves: `install.sh` will list them as `[skip]` if already linked or `[ok]` on first install, but you should NOT highlight them in the "newly linked" report — they're plumbing, not the user-visible payload. Mention them only if the user asks explicitly or something unexpected happens (e.g., one of them was missing and just got installed).

## 7. 지침 (guideline files) — follow-up

After the skill install completes, ask the user whether to also pull 지침 (Korean for "guidelines" — standalone markdown files like `CLAUDE.md`, `CodeConvention.md`, `Architecture.md` that document conventions or context, but are NOT skills with their own `SKILL.md`):

> "지침 파일도 같이 가져올까요?"

If the user declines, you're done. If they accept, follow the flow below.

### Identify candidates in the repo

Scan the repo for guideline-like files. Look in (in order):

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

  Parse the user's reply: `all` → every candidate, `none` → cancel, comma-separated numbers → that subset. Be lenient about whitespace and trailing punctuation.

### Decide where each selected file lands at the destination

For each selected file, the default destination is one of:
- Project scope, project markers exist: `<cwd>/.claude/<filename>` (or `<cwd>/<filename>` for `CLAUDE.md` if the project keeps it at the root)
- Global scope: `~/.claude/<filename>`

Confirm with the user if the default is non-obvious (e.g., the file is namespaced under `guidelines/foo/bar.md` — ask whether to flatten or preserve the subdirectory).

Copy (don't symlink) — guideline files are usually edited per-project and shouldn't be tied back to the repo. The user can manually re-sync later via `push-skill-*` if they want.

### Conflicts

If the destination already has a file with the same name:
- **Different contents** → ask: overwrite / keep destination / save as `<name>.from-repo.md` / skip
- **Same contents** → silent skip with a `[skip]` log line

Never silently overwrite a guideline file — they often hold project-specific tweaks.

### Report

After 지침 follow-up, summarize: which files copied, which skipped, which had conflicts and how they were resolved.

## When NOT to fire

- User wants to install **only some** skills, not all → use `pull-skill-select`.
- User wants to **create** a new skill → use `skill-creator`.
- User wants to **push** local changes back to the repo → use `push-skill-all` (or `push-skill-select` for a subset).
- User wants to refresh the local repo from GitHub → that's a `git pull` they should ask for explicitly; don't do it as part of this skill.
- User asks general questions about Claude Code skills → answer directly.
