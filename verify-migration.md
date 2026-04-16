# Verify Claude Code Migration

You are a verification assistant that performs a deep health check on Claude Code's data integrity. This can be run anytime — not just after a migration.

## Instructions

Run every check below and produce a summary report. Do not ask for user input — just run everything.

### Step 1: Detect Platform

- macOS: app registry at `~/Library/Application Support/Claude/claude-code-sessions/`
- Linux: app registry at `~/.config/Claude/claude-code-sessions/`

### Step 2: Check `~/.claude.json`

1. Verify the file exists and is valid JSON (`python3 -m json.tool`)
2. For each project entry in `projects`:
   - Check if the directory actually exists on disk
   - Flag any entries pointing to non-existent directories as **orphaned**
3. Report total projects, valid projects, orphaned projects

### Step 3: Check `~/.claude/projects/`

1. List all path-encoded project directories
2. For each directory:
   - Decode the path (dashes → slashes)
   - Check if the decoded path exists on disk
   - Check if there's a matching entry in `~/.claude.json`
   - Count `.jsonl` files and total size
3. Flag directories with no matching config entry or no existing project folder

### Step 4: Check App Registry

1. Find all `local_*.json` files in the app registry
2. For each file:
   - Verify it's valid JSON
   - Extract the `cwd` field
   - Check if the `cwd` directory exists on disk
   - Check if there's a matching entry in `~/.claude.json`
3. Flag entries pointing to non-existent directories
4. Flag duplicate entries (multiple `local_*.json` files with the same `cwd`)

### Step 5: Cross-Reference

1. For each project in `~/.claude.json`:
   - Verify there's a matching session dir in `~/.claude/projects/`
   - Verify there's at least one matching `local_*.json` in the app registry
2. Report any projects that are in one location but not the others

### Step 6: Report

Output a structured report:

```
=== Claude Code Health Check ===

Config (~/.claude.json):
  Total projects: X
  Valid: X
  Orphaned: X (list paths)

Sessions (~/.claude/projects/):
  Total dirs: X
  With matching config: X
  Orphaned: X (list dirs)

App Registry:
  Total entries: X
  Valid: X
  Orphaned: X (list entries)
  Duplicates: X

Cross-Reference:
  Fully consistent projects: X
  Inconsistent: X (list details)

Overall: HEALTHY / NEEDS ATTENTION
```

If anything is flagged, offer to fix it (remove orphans, clean duplicates) but always confirm with the user first.
