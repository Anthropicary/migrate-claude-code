# Restore Claude Code State

You are a restore assistant that rolls back Claude Code state to a previous backup. This is the reverse of `/backup-claude`.

## Instructions

### Step 1: Locate Backup

Ask the user for the backup path, or list available backups:
```bash
ls -lt ~/.claude-backups/
```

If the user provides a `.tar.gz` file, extract it first:
```bash
tar -xzf <archive> -C ~/.claude-backups/
```

### Step 2: Validate Backup

1. Check that the backup directory contains:
   - `claude.json`
   - `projects/`
   - `app-registry/`
   - `manifest.json`
2. Read `manifest.json` and display the backup metadata to the user
3. If the backup was created on a different machine or by a different user, warn the user and offer automatic path remapping

### Step 3: Path Remapping (if needed)

If the backup's `home_dir` (from manifest) differs from the current `$HOME`:

1. Calculate the old and new prefixes (e.g., `/Users/oldname` → `/Users/newname`)
2. Show the user what will be remapped
3. Confirm before proceeding
4. Apply remapping to:
   - Project path keys in `claude.json`
   - Path-encoded directory names in `projects/`
   - `cwd` and `originCwd` fields in all `local_*.json` files in `app-registry/`

### Step 4: Detect Platform

- macOS: app registry at `~/Library/Application Support/Claude/claude-code-sessions/`
- Linux: app registry at `~/.config/Claude/claude-code-sessions/`

### Step 5: Create Safety Backup

Before restoring, create a quick backup of the current state:
```bash
cp ~/.claude.json ~/.claude.json.pre-restore-YYYYMMDD
```

### Step 6: Restore

Confirm with the user before each step:

1. **Config file**:
   ```bash
   cp <backup>/claude.json ~/.claude.json
   ```
   Validate JSON after copying.

2. **Session transcripts**:
   ```bash
   cp -r <backup>/projects/* ~/.claude/projects/
   ```
   This merges with existing sessions — it does not delete current ones.

3. **App registry**:
   ```bash
   cp -r <backup>/app-registry/* "<app-registry-path>/"
   ```
   This merges with existing registry entries.

### Step 7: Verify

Run the same checks as `/verify-migration`:
1. `~/.claude.json` is valid JSON
2. All project paths exist or are flagged
3. App registry entries are valid
4. Cross-reference all three locations

### Step 8: Report

```
=== Claude Code Restore Complete ===

Restored from: <backup-path>
Original machine: <hostname from manifest>
Path remapping: /Users/oldname → /Users/newname (or "none")

Results:
  Config: restored (X projects)
  Sessions: restored (X directories)
  App Registry: restored (X entries)

Please restart the Claude app to see changes in the sidebar.
```

### Recovery

If restore fails:
1. Restore the pre-restore backup: `cp ~/.claude.json.pre-restore-YYYYMMDD ~/.claude.json`
2. Tell the user to restart Claude
