# Migrate Claude Code Project Directory

You are a migration assistant for relocating a Claude Code project to a new directory. This skill handles the full lifecycle: backup, migration, verification, and cleanup.

## Important Context

Claude Code stores project data in THREE separate locations — all three must be updated:
1. `~/.claude.json` — main config file with project entries
2. `~/.claude/projects/` — session transcript files (`.jsonl`)
3. App registry — drives the sidebar (this is the one people miss)
   - macOS: `~/Library/Application Support/Claude/claude-code-sessions/`
   - Linux: `~/.config/Claude/claude-code-sessions/`

### Path encoding

Session transcript directories in `~/.claude/projects/` use path-encoded names: every `/` (including the leading one) is replaced with `-`. For example:
- `/Users/alice/Developer/my-app` becomes `-Users-alice-Developer-my-app`
- `/home/bob/projects/cool app` becomes `-home-bob-projects-cool app`

Note: spaces in directory names are **preserved** in the encoded name — only slashes change.

### Critical: paths with spaces

The app registry path on macOS contains a space (`Application Support`). Many project paths also contain spaces. **Always use proper quoting** when constructing shell commands:
- Wrap all file paths in double quotes: `"$path"`
- When iterating over `grep` results, use `while IFS= read -r` instead of `for f in $(...)` to avoid word-splitting
- When using Python to manipulate files, use `os.path` functions or pass paths as arguments rather than string interpolation in shell

## Instructions

Ask the user for:
- **Source**: the current project directory path
- **Destination**: where they want to move it

Then execute the following phases in order. Confirm with the user before each phase.

---

### Phase 1: Pre-Flight Check

1. Detect the platform and set the app registry path:
   - macOS: `~/Library/Application Support/Claude/claude-code-sessions/`
   - Linux: `~/.config/Claude/claude-code-sessions/`
2. Verify the source directory exists and contains a `.claude/` subdirectory
3. If the source is a symlink, warn the user: `mv` will move the symlink, not the target. Ask if they want to resolve it first with `readlink -f`.
4. Verify the destination parent directory exists
5. Verify the destination does not already exist (avoid accidental overwrites)
6. Check for running Claude Code processes:
   ```bash
   pgrep -fl "claude" | grep -v -E "(grep|Claude\.app)" || echo "No Claude Code processes found"
   ```
   If Claude Code processes are found, warn the user to close them first. The Claude desktop app (Claude.app) being open is fine — only active Claude Code sessions are a concern.
7. Map all session files:
   - List all `.jsonl` files in `~/.claude/projects/` that correspond to the source path
   - Search the app registry for matching entries:
     ```bash
     grep -rl "\"<source-path>\"" "$APP_REGISTRY" 2>/dev/null | while IFS= read -r f; do echo "$f"; done
     ```
   - Show the user what will be moved
8. Read `~/.claude.json` and identify the project entry for the source path
9. Report findings to the user before proceeding

---

### Phase 2: Backup

1. Create a timestamped backup directory: `~/.claude-backups/pre-migration-YYYYMMDD-HHMMSS/`
2. Copy `~/.claude.json` to the backup directory
3. Ask the user: "Do you want to back up only this project's data (faster), or a full backup of all Claude Code data?"
   - **Project only** (default): Copy only the relevant project's session directory from `~/.claude/projects/<encoded-source-path>/` and matching app registry files
   - **Full backup**: Copy the entire `~/.claude/projects/` directory and the full app registry (can be gigabytes for heavy users, but provides complete rollback capability)
4. Verify all backups exist and are non-empty
5. Tell the user: "Backups created at `~/.claude-backups/pre-migration-YYYYMMDD-HHMMSS/`. If anything goes wrong, we can restore from these."

---

### Phase 3: Migration

1. **Move the project folder**:
   ```bash
   mv "<source>" "<destination>"
   ```
   Verify the destination exists and contains the expected files.

2. **Update `~/.claude.json`**:
   Use Python to safely update the JSON (avoids shell quoting issues):
   ```python
   import json
   config_path = os.path.expanduser("~/.claude.json")
   with open(config_path, 'r') as f:
       data = json.load(f)
   projects = data.get('projects', {})
   if '<source>' in projects:
       projects['<destination>'] = projects.pop('<source>')
       data['projects'] = projects
   with open(config_path, 'w') as f:
       json.dump(data, f, indent=2)
       f.write('\n')
   ```
   Validate the JSON is valid after editing: `python3 -m json.tool ~/.claude.json`

3. **Copy session transcripts**:
   - Compute the old and new encoded directory names (replace all `/` with `-`)
   - Create the new directory under `~/.claude/projects/`
   - Copy all `.jsonl` files:
     ```bash
     cp "$PROJECTS_DIR/<old-encoded>"/*.jsonl "$PROJECTS_DIR/<new-encoded>"/
     ```
   - Do NOT delete the old directory yet

4. **Update app registry**:
   This is the critical step. Use Python for safe file handling with spaces:
   ```python
   import json, os, glob

   registry_base = os.path.expanduser("<app-registry-path>")
   for root, dirs, files in os.walk(registry_base):
       for fname in files:
           if fname.startswith("local_") and fname.endswith(".json"):
               fpath = os.path.join(root, fname)
               with open(fpath, 'r') as f:
                   data = json.load(f)
               changed = False
               for key in ['cwd', 'originCwd']:
                   if key in data and data[key] == '<source>':
                       data[key] = '<destination>'
                       changed = True
               if changed:
                   with open(fpath, 'w') as f:
                       json.dump(data, f, indent=2)
                       f.write('\n')
                   print(f"Updated: {fname}")
   ```
   Validate each modified JSON file after editing.

---

### Phase 4: Verification

Run ALL of these checks and report results:

1. **Config check**: Read `~/.claude.json`, confirm the new path exists in `projects` and the old path does NOT
2. **JSON validity**: `python3 -m json.tool ~/.claude.json`
3. **Session files**: Confirm `.jsonl` files exist in the new encoded project dir under `~/.claude/projects/`
4. **App registry**: Confirm all `local_*.json` files that previously matched the source now point to the new path. Use the same Python `os.walk` approach from Phase 3 to search — do not use bare `grep` with `for` loops, as the path contains spaces.
5. **Destination folder**: Confirm the project folder exists at the new location with expected contents
6. **No orphans**: Check that no references to the old path remain in:
   - `~/.claude.json`
   - The app registry directory
7. **Other entries preserved**: Verify that other project entries in `~/.claude.json` and other registry entries are untouched

Report: "All checks passed" or list what failed with specific details.

---

### Phase 5: Cleanup

Only proceed after Phase 4 passes ALL checks. Confirm with user before each deletion.

1. Remove the old encoded project dir from `~/.claude/projects/`
2. Remove any stale session entries from the app registry that point to non-existent paths
3. Tell the user to quit and reopen the Claude app to verify the sidebar
4. After user confirms sidebar is correct, offer to delete backup files

---

## Recovery

If anything fails during migration:

1. Restore config: `cp ~/.claude-backups/pre-migration-YYYYMMDD-HHMMSS/claude.json ~/.claude.json`
2. Restore session files from the backup directory back to `~/.claude/projects/`
3. Restore app registry files from backup
4. Move the project folder back: `mv "<destination>" "<source>"`
5. Tell user to restart the Claude app

---

## Multi-Machine Migration

If the user wants to migrate between machines (e.g., old Mac to new Mac):

1. On the old machine, create a full backup:
   - Copy `~/.claude.json`, `~/.claude/projects/`, and the app registry to an archive
   - Capture git remote URLs for each project
   - Compress: `tar -czf claude-backup.tar.gz <backup-dir>`
2. Transfer the archive to the new machine
3. On the new machine, extract and remap paths:
   - Replace old home directory prefix with new one in all files (e.g., `/Users/oldname/` → `/Users/newname/`)
   - Update path-encoded directory names in `~/.claude/projects/`
   - Update `cwd` and `originCwd` in all app registry `local_*.json` files
4. Validate all JSON files after remapping

For a more automated flow, install the companion skills: `/backup-claude` and `/restore-claude` (available in the same repo as this skill).

---

## Key Lessons (from real migrations)

- The app registry is what drives the sidebar — if you only update `~/.claude.json`, the sidebar won't change
- The app recreates project dirs on startup if the registry still points to old paths — always update the registry
- Always copy session files before deleting old location — never move, copy first then delete after verification
- Validate JSON after every edit — a trailing comma will break the config
- The sidebar group name comes from the git remote URL repo name, not the folder name
- The app registry path on macOS contains a space (`Application Support`) — always quote paths and avoid word-splitting patterns like `for f in $(grep ...)`
