# my-claude-skills

A personal, portable [Claude Code](https://claude.com/claude-code) setup — skills, external skills, and plugins — installable on any machine with one command.

## What it sets up

1. **Local skills** in `skills/*` → symlinked into `~/.claude/skills/`
   - Includes the **`pull-skill`** and **`push-skill`** command skills (your daily interface)
2. **External skills** listed in `externals.txt` → cloned into `_externals/` and symlinked
3. **Plugin marketplaces** listed in `marketplaces.txt` → registered via `claude plugin marketplace add`
4. **Plugins** listed in `plugins.txt` → installed via `claude plugin install`

All steps are idempotent — re-running is safe.

## Daily use (after install)

Once `install.sh` has run on a machine, you have two natural-language commands inside Claude Code:

| Command | What it does |
|---|---|
| `/pull-skill` | Sync this machine with the latest repo state. Resolves conflicts interactively. |
| `/push-skill <intent>` | Capture local changes (new skills, installed plugins, etc.) into the repo. Drafts a commit message; asks before pushing. |

Examples:

```
/pull-skill
/push-skill add my-new-skill that helps with X
/push-skill update foo and capture the new plugin I just installed
```

Under the hood these call `install.sh` and `sync.sh`. You can still run those scripts directly when you want a deterministic, non-interactive run (CI, cron, scripts).

## Install (one command)

### macOS / Linux

```sh
git clone https://github.com/FuJiGraphics/my-claude-skills.git ~/my-claude-skills \
  && cd ~/my-claude-skills && bash install.sh
```

### Windows (PowerShell)

```powershell
git clone https://github.com/FuJiGraphics/my-claude-skills.git $HOME\my-claude-skills; `
  cd $HOME\my-claude-skills; powershell -ExecutionPolicy Bypass -File .\install.ps1
```

> Windows uses NTFS junctions (no admin required). Don't use `install.sh` from Git Bash on Windows — symlinks won't behave correctly there.

## Adding things

### A new local skill

```
skills/my-skill/SKILL.md
```

with frontmatter:

```markdown
---
name: my-skill
description: When this skill should fire (one line).
---

Skill instructions here.
```

Re-run `install.sh` / `install.ps1` to symlink it.

### An external skill

Add a line to `externals.txt`:

```
<git-repo-url>|<path-in-repo>|<install-as-name>
```

Example:

```
https://github.com/anthropics/skills.git|skills/skill-creator|skill-creator
```

### A plugin marketplace

Add a line to `marketplaces.txt` (anything `claude plugin marketplace add` accepts):

```
anthropics/claude-plugins-official
```

### A plugin

Add a line to `plugins.txt`:

```
<plugin-name>@<marketplace>
```

Example:

```
skill-creator@claude-plugins-official
```

## Direct script use (advanced / non-interactive)

The slash commands above are the recommended interface. The underlying scripts are still available for automation:

```sh
# repo → local (deterministic, non-interactive)
cd ~/my-claude-skills && git pull && bash install.sh   # or install.ps1

# local → repo (deterministic, non-interactive; does NOT commit)
bash sync.sh   # or sync.ps1 — review with `git diff`, commit yourself
```

## Layout

```
my-claude-skills/
├── install.sh             # macOS / Linux  (repo → local)
├── install.ps1            # Windows         (repo → local)
├── sync.sh                # macOS / Linux  (local → repo)
├── sync.ps1               # Windows         (local → repo)
├── externals.txt          # external skills (git+symlink)
├── marketplaces.txt       # plugin marketplaces
├── plugins.txt            # plugins to install
├── skills/
│   ├── pull-skill/        # /pull-skill command (installed by install.sh)
│   ├── push-skill/        # /push-skill command (installed by install.sh)
│   └── <your skills>/
└── _externals/            # cloned external repos (gitignored)
```
