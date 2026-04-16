# Backup Claude Code State

You are a backup assistant that creates a complete snapshot of all Claude Code state. This can be run anytime as a safety net — not just before migrations.

## Instructions

### Step 1: Detect Platform

- macOS: app registry at `~/Library/Application Support/Claude/claude-code-sessions/`
- Linux: app registry at `~/.config/Claude/claude-code-sessions/`

### Step 2: Create Backup Directory

Create a timestamped backup directory:
```
~/.claude-backups/backup-YYYYMMDD-HHMMSS/
```

### Step 3: Backup All Three Locations

1. **Config file**:
   ```bash
   cp ~/.claude.json ~/.claude-backups/backup-YYYYMMDD-HHMMSS/claude.json
   ```

2. **Session transcripts**:
   ```bash
   cp -r ~/.claude/projects/ ~/.claude-backups/backup-YYYYMMDD-HHMMSS/projects/
   ```

3. **App registry**:
   ```bash
   cp -r "<app-registry-path>" ~/.claude-backups/backup-YYYYMMDD-HHMMSS/app-registry/
   ```

### Step 4: Capture Metadata

Create a `manifest.json` inside the backup directory with:
```json
{
  "timestamp": "ISO-8601 timestamp",
  "platform": "darwin or linux",
  "hostname": "machine hostname",
  "username": "current user",
  "home_dir": "/Users/username",
  "source_paths": {
    "config": "~/.claude.json",
    "projects": "~/.claude/projects/",
    "app_registry": "<full path>"
  },
  "git_remotes": {
    "/path/to/project": "git@github.com:org/repo.git"
  },
  "stats": {
    "total_projects": 0,
    "total_session_files": 0,
    "total_registry_entries": 0,
    "total_size_bytes": 0
  }
}
```

For the `git_remotes` field, iterate over each project directory listed in `~/.claude.json` and capture the git remote URL (if it's a git repo).

### Step 5: Verify Backup

1. Confirm all three directories were copied
2. Compare file counts between source and backup
3. Verify `manifest.json` is valid JSON

### Step 6: Report

```
=== Claude Code Backup Complete ===

Location: ~/.claude-backups/backup-YYYYMMDD-HHMMSS/
Total size: X MB

Contents:
  Config: backed up (X bytes)
  Sessions: X directories, Y files
  App Registry: X entries
  Git Remotes: captured for X projects

Manifest: ~/.claude-backups/backup-YYYYMMDD-HHMMSS/manifest.json

To restore: run /restore-claude with this backup path
```

### Step 7: Optional Compression

Ask the user if they want to compress the backup into a `.tar.gz` archive (useful for transferring to another machine). If yes:
```bash
tar -czf ~/.claude-backups/backup-YYYYMMDD-HHMMSS.tar.gz -C ~/.claude-backups backup-YYYYMMDD-HHMMSS
```
