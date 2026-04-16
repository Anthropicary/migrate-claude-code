# Diagnose Claude Code

You are a diagnostic assistant that performs a comprehensive health check on all Claude Code data. This goes beyond migration verification — it checks for issues that can develop over normal use.

## Instructions

Run every check below and produce a detailed report. Do not ask for user input — just run everything.

### Step 1: Detect Platform

- macOS: app registry at `~/Library/Application Support/Claude/claude-code-sessions/`
- Linux: app registry at `~/.config/Claude/claude-code-sessions/`

### Step 2: Orphan Detection

**Orphan sessions** — session dirs in `~/.claude/projects/` pointing to non-existent project folders:
1. List all path-encoded directories in `~/.claude/projects/`
2. Decode each path (leading dash removed, remaining dashes → slashes)
3. Check if the decoded directory exists on disk
4. Flag any that don't exist as orphans

**Orphan config entries** — projects in `~/.claude.json` whose directories no longer exist:
1. Read `~/.claude.json` and iterate over the `projects` keys
2. Check if each directory exists
3. Flag missing ones

**Orphan registry entries** — app registry entries pointing to non-existent directories:
1. Find all `local_*.json` files in the app registry
2. Extract `cwd` from each
3. Check if each `cwd` exists on disk
4. Flag missing ones

### Step 3: Duplicate Detection

Check for duplicate entries in the app registry:
1. Collect all `cwd` values from `local_*.json` files
2. Flag any `cwd` that appears in more than one file
3. For duplicates, show the file names and last-modified timestamps

### Step 4: Secret Exposure Check

Scan git remote URLs for exposed credentials:
1. For each project directory listed in `~/.claude.json`:
   - If it's a git repo, read `.git/config`
   - Check remote URLs for patterns like:
     - `https://username:password@`
     - `https://ghp_*@` (GitHub PATs)
     - `https://glpat-*@` (GitLab PATs)
     - `https://x-token-auth:*@` (Bitbucket app passwords)
2. Flag any remote URLs containing embedded tokens or passwords
3. Recommend switching to SSH or credential helpers

### Step 5: Session File Analysis

Analyze session file sizes and health:
1. For each `.jsonl` file in `~/.claude/projects/`:
   - Record file size
   - Flag files over 5 MB as "bloated"
   - Flag files over 20 MB as "critical"
2. Check if any `.jsonl` files have corrupted JSON (malformed lines)
3. Calculate total disk usage of all session files

### Step 6: Disk Usage Breakdown

Calculate disk usage for each Claude Code data location:
```bash
du -sh ~/.claude.json
du -sh ~/.claude/
du -sh "<app-registry-path>"
```

Break down `~/.claude/` further:
```bash
du -sh ~/.claude/projects/
du -sh ~/.claude/todos/
du -sh ~/.claude/commands/
```

### Step 7: Config Validation

1. Parse `~/.claude.json` with `python3 -m json.tool`
2. Check for common issues:
   - Trailing commas (invalid JSON)
   - Duplicate keys
   - Empty project entries
   - Unreasonably large file size (> 1 MB)

### Step 8: Report

Output a structured report:

```
=== Claude Code Diagnostic Report ===

Platform: macOS / Linux
Date: YYYY-MM-DD HH:MM:SS

--- Orphans ---
  Session dirs pointing to missing folders: X
    - /decoded/path (session dir: -decoded-path)
  Config entries for missing folders: X
    - /missing/path
  Registry entries for missing folders: X
    - local_abc123.json → /missing/path

--- Duplicates ---
  Duplicate registry entries: X
    - /path/to/project → local_abc.json, local_def.json

--- Security ---
  Git remotes with exposed credentials: X
    - /path/to/project → https://ghp_***@github.com/...
  Recommendation: Switch to SSH keys or git credential helpers

--- Session Health ---
  Total session files: X
  Total size: X MB
  Bloated (>5 MB): X files
  Critical (>20 MB): X files
  Corrupted: X files

--- Disk Usage ---
  ~/.claude.json: X KB
  ~/.claude/projects/: X MB
  ~/.claude/todos/: X MB
  ~/.claude/commands/: X MB
  App registry: X MB
  Total: X MB

--- Config ---
  JSON valid: yes/no
  Projects: X entries
  Issues: none / list issues

Overall: HEALTHY / NEEDS ATTENTION / CRITICAL
```

After the report, offer to fix any issues found:
- Remove orphan session directories
- Remove orphan config entries
- Remove orphan registry entries
- Remove duplicate registry entries (keep newest)
- Alert about bloated session files (offer to back up then truncate)

Always confirm with the user before making any changes.
