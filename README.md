<p align="center">
  <h1 align="center">migrate-claude-code</h1>
  <p align="center">
    Move Claude Code projects without breaking your sidebar, sessions, or config.
    <br />
    The only migration tool that updates <strong>all 3 data locations</strong> — including the app registry that actually drives the sidebar.
  </p>
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> &nbsp;&bull;&nbsp;
  <a href="#the-3-locations-explained">How It Works</a> &nbsp;&bull;&nbsp;
  <a href="#troubleshooting">Troubleshooting</a> &nbsp;&bull;&nbsp;
  <a href="#multi-machine-migration">Multi-Machine</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License" />
  <img src="https://img.shields.io/badge/claude--code-slash%20command-blueviolet" alt="Claude Code slash command" />
  <img src="https://img.shields.io/badge/shell-bash-lightgrey" alt="Bash" />
  <img src="https://img.shields.io/github/stars/Anthropicary/migrate-claude-code?style=social" alt="GitHub Stars" />
</p>

---

```bash
mkdir -p ~/.claude/commands && curl -sL https://raw.githubusercontent.com/Anthropicary/migrate-claude-code/main/migrate-claude.md -o ~/.claude/commands/migrate-claude.md
```

Then type `/migrate-claude` in Claude Code. Install the [full toolkit](#option-a-one-command-install-recommended) for backup, restore, verify, and diagnostics.

---

## The Problem

You moved a project folder. Now:

- The sidebar shows ghost projects that won't go away
- Deleted groups keep reappearing after every restart
- Sessions won't resume — Claude doesn't remember your context
- The wrong project name shows up in the sidebar group

Every existing migration tool misses the root cause.

## Why Existing Tools Don't Fix It

Claude Code stores data in **three separate locations**. Update only one or two and the sidebar breaks.

| | This tool | [hcz1/migrate-claude-code](https://github.com/hcz1/migrate-claude-code) | [FarisHijazi/claude-migrate](https://github.com/FarisHijazi/claude-migrate) | [ukogan/claude-migration-assistant](https://github.com/ukogan/claude-migration-assistant) |
|:---|:---:|:---:|:---:|:---:|
| Updates `~/.claude.json` | ✅ | ✅ | ✅ | ✅ |
| Moves session transcripts | ✅ | ✅ | ✅ | ✅ |
| **Updates app registry (sidebar)** | ✅ | ❌ | ❌ | ❌ |
| Cross-platform (macOS + Linux) | ✅ | ❌ | ❌ | ❌ |
| Multi-machine migration | ✅ | ❌ | ❌ | ❌ |
| `--dry-run` preview mode | ✅ | ❌ | ❌ | ❌ |
| Backup & restore | ✅ | Partial | ❌ | ❌ |
| Diagnostics & health check | ✅ | ❌ | ❌ | ❌ |
| Tested against edge cases | ✅ | ❌ | ❌ | ❌ |

## The 3 Locations

Every migration must update **all three** or the sidebar breaks:

```
1. ~/.claude.json                     ← project entries & settings
2. ~/.claude/projects/                ← session transcripts (.jsonl)
3. App registry                       ← sidebar state (THE ONE EVERYONE MISSES)
   macOS: ~/Library/Application Support/Claude/claude-code-sessions/
   Linux: ~/.config/Claude/claude-code-sessions/
```

The app registry is what drives the sidebar. If it still points to old paths, the app will **recreate directories at the old location on every startup** — making it look like your changes never happened.

## Quick Start

### Option A: One command install (recommended)

```bash
# Install everything — all 5 slash commands
mkdir -p ~/.claude/commands && for f in migrate-claude verify-migration backup-claude restore-claude diagnose-claude; do curl -sL "https://raw.githubusercontent.com/Anthropicary/migrate-claude-code/main/$f.md" -o "$HOME/.claude/commands/$f.md"; done
```

Then in Claude Code:

```
/migrate-claude
```

Claude walks you through 5 phases: pre-flight check → backup → migration → verification → cleanup. It confirms before each destructive step.

<details>
<summary><strong>Install individual commands</strong></summary>
<br />

Pick only what you need:

```bash
mkdir -p ~/.claude/commands

# Migration (move a project to a new directory)
curl -sL https://raw.githubusercontent.com/Anthropicary/migrate-claude-code/main/migrate-claude.md -o ~/.claude/commands/migrate-claude.md

# Verification (health check across all 3 locations)
curl -sL https://raw.githubusercontent.com/Anthropicary/migrate-claude-code/main/verify-migration.md -o ~/.claude/commands/verify-migration.md

# Backup (snapshot all Claude Code state)
curl -sL https://raw.githubusercontent.com/Anthropicary/migrate-claude-code/main/backup-claude.md -o ~/.claude/commands/backup-claude.md

# Restore (roll back from a snapshot)
curl -sL https://raw.githubusercontent.com/Anthropicary/migrate-claude-code/main/restore-claude.md -o ~/.claude/commands/restore-claude.md

# Diagnostics (find orphans, duplicates, secrets, bloat)
curl -sL https://raw.githubusercontent.com/Anthropicary/migrate-claude-code/main/diagnose-claude.md -o ~/.claude/commands/diagnose-claude.md
```

</details>

### Option B: Bash script

```bash
# Preview what will change — no files modified
./migrate-claude.sh --dry-run ~/old/path ~/new/path

# Run the migration
./migrate-claude.sh ~/old/path ~/new/path

# Full backup before migrating (backs up all sessions, not just this project)
./migrate-claude.sh --full-backup ~/old/path ~/new/path
```

## Full Toolkit

| Slash Command | File | What it does |
|:---|:---|:---|
| `/migrate-claude` | `migrate-claude.md` | Full project migration — backup, update all 3 locations, verify, clean up |
| `/verify-migration` | `verify-migration.md` | Deep health check across all 3 locations — run anytime |
| `/backup-claude` | `backup-claude.md` | Snapshot all Claude Code state to a timestamped archive |
| `/restore-claude` | `restore-claude.md` | Roll back to a snapshot — with automatic path remapping for cross-machine |
| `/diagnose-claude` | `diagnose-claude.md` | Find orphans, duplicate entries, exposed secrets in git remotes, bloated session files |

## The 3 Locations Explained

<details>
<summary><strong>1. <code>~/.claude.json</code> — Project config</strong></summary>
<br />

The main config file. Keys are absolute directory paths:

```json
{
  "projects": {
    "/Users/alice/Developer/my-app": {
      "allowedTools": ["Bash", "Read"],
      "mcpContextUris": []
    }
  }
}
```

If you miss this: project-level settings (allowed tools, MCP configs) are lost.

</details>

<details>
<summary><strong>2. <code>~/.claude/projects/</code> — Session transcripts</strong></summary>
<br />

Session history stored as `.jsonl` files in path-encoded directories.

Encoding rule: every `/` becomes `-` (spaces are preserved as-is).

```
/Users/alice/Developer/my-app  →  -Users-alice-Developer-my-app
/Users/alice/My Projects/app   →  -Users-alice-My Projects-app
```

If you miss this: session history and conversation context are lost.

</details>

<details>
<summary><strong>3. App registry — Sidebar state (the one everyone misses)</strong></summary>
<br />

The Claude desktop app keeps its own registry of sessions:

```
# macOS
~/Library/Application Support/Claude/claude-code-sessions/<account-uuid>/<org-uuid>/local_*.json

# Linux
~/.config/Claude/claude-code-sessions/<account-uuid>/<org-uuid>/local_*.json
```

Each `local_*.json` contains a `cwd` field pointing to the project directory. This is what the sidebar reads.

**If you don't update these files:**
- The sidebar keeps showing the old path
- The app recreates directories at the old location on startup
- Ghost projects reappear after every restart

</details>

## Multi-Machine Migration

Moving to a new computer (old Mac → new Mac, Mac → Linux):

**On the old machine:**
```
/backup-claude
```
Compress to `.tar.gz` when prompted.

**Transfer** via AirDrop, USB, scp, rsync, etc.

**On the new machine:**
```
/restore-claude
```

The restore process automatically remaps all paths — `/Users/oldname/` → `/Users/newname/` — across all three locations.

## Troubleshooting

<details>
<summary><strong>"Sidebar shows wrong project name"</strong></summary>
<br />

The sidebar group name comes from the **git remote URL repo name**, not the folder name.

```bash
cd /path/to/project && git remote -v
```

Fix:
```bash
git remote set-url origin git@github.com:org/correct-repo.git
```

</details>

<details>
<summary><strong>"Deleted project keeps reappearing after restart"</strong></summary>
<br />

The app registry still has an entry for the old path. The app recreates it on startup.

```
/diagnose-claude
```

This finds the orphan entry and offers to remove it.

</details>

<details>
<summary><strong>"Session won't resume after move"</strong></summary>
<br />

The path-encoded folder in `~/.claude/projects/` doesn't match the new location.

```
/verify-migration
```

This identifies the mismatch and shows exactly what to fix.

</details>

<details>
<summary><strong>"Config file corrupted after editing"</strong></summary>
<br />

Usually a trailing comma in the JSON (invalid in JSON, valid in JS — easy to accidentally add).

```bash
python3 -m json.tool ~/.claude.json
```

Restore from backup:
```bash
cp ~/.claude-backups/<latest>/claude.json ~/.claude.json
```

</details>

<details>
<summary><strong>"Projects missing after macOS update"</strong></summary>
<br />

macOS updates can reset app data. Restore from a backup:

```
/restore-claude
```

</details>

## Key Lessons

Hard-won from real migrations that went wrong before this tool existed:

- **The app registry drives the sidebar** — updating only `~/.claude.json` does nothing to the UI
- **The app recreates project dirs on startup** if the registry still points to old paths
- **Always copy session files before deleting** — never `mv` directly; copy, verify, then delete
- **Validate JSON after every edit** — a single trailing comma breaks the entire config
- **Sidebar group name = git remote URL repo name**, not the folder name
- **The macOS app registry path contains a space** (`Application Support`) — scripts must quote all paths

## License

MIT
