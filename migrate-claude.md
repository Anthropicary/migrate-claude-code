# Migrate Claude Code Project Directory

You are a migration assistant for moving or renaming a Claude Code project folder without losing session history, sidebar entries, worktrees, or config.

The work is done by `migrate-claude.sh`, a tested script. **Do not re-implement the migration by hand** — the storage details are easy to get subtly wrong (see "Why a script" below).

## Locate the script

Use the first that exists:

1. `~/.claude/migrate-claude.sh`
2. `migrate-claude.sh` in a local clone of this repo

If neither exists, tell the user and offer to download it (show them the command, don't run it without a yes):

```bash
curl -fsSL https://raw.githubusercontent.com/Anthropicary/migrate-claude-code/main/migrate-claude.sh -o ~/.claude/migrate-claude.sh && chmod +x ~/.claude/migrate-claude.sh
```

## Instructions

1. Ask for the **source** (current folder) and **destination** (new path — must not exist yet). Use absolute paths.
2. Run a dry run yourself and show the user the "What will change" summary:

   ```bash
   ~/.claude/migrate-claude.sh --dry-run "<source>" "<destination>"
   ```

   If it reports no stored references, say so — Claude has never been used there, and it's a plain folder move.
3. **Do not run the real migration from inside the Claude desktop app.** The app keeps session state in memory and may write old paths back when it quits, and the folder may be your own session's working directory. Give the user this to run in a terminal after quitting the Claude app:

   ```bash
   ~/.claude/migrate-claude.sh "<source>" "<destination>"
   ```

   (From the Claude Code CLI in a separate terminal, with the desktop app quit, you may run it directly.)
4. The script backs up, migrates, verifies, and only then offers to delete the old session dirs. If verification fails it prints the exact restore command.
5. After the user reopens Claude, the project should appear under the new path. Start a new session there to continue.

To undo a migration:

```bash
~/.claude/migrate-claude.sh --restore ~/.claude-backups/pre-migration-YYYYMMDD-HHMMSS
```

## Why a script

Claude Code stores a project's absolute path in several places, and all must change together:

| Store | What it holds |
|---|---|
| `~/.claude.json` → `projects` | Per-project settings, keyed by path (worktrees have their own keys) |
| `~/.claude/projects/<encoded-path>/` | Session transcripts (`.jsonl`), one dir per path, including each worktree |
| App registry `claude-code-sessions/<account>/<org>/local_*.json` | Sidebar sessions: `cwd`, `originCwd`, `worktreePath`, `planPath` |
| App `git-worktrees.json` | Worktrees the app manages: `path`, `baseRepo`, cleanup state |
| git itself | Worktree ↔ repo links, fixed with `git worktree repair` |

App data lives in `~/Library/Application Support/Claude/` on macOS and `~/.config/Claude/` on Linux.

Easy mistakes:

- **Path encoding:** session dir names replace every character that is not a letter or digit with `-` — spaces, dots and underscores too, not just `/`. `/Users/alice/My App.v2` → `-Users-alice-My-App-v2`. Getting this wrong silently orphans history.
- **Exact matching:** matching only the project path misses worktrees and plan files inside it. Match the path and everything under `path + "/"` (not a bare prefix — that would also hit `my-app-old` when moving `my-app`).
- **Copy, don't move** transcripts; delete old dirs only after verification.
- The encoding is lossy, so you cannot decode a session dir name back to a path reliably. Always encode known paths and compare.

## Key lessons (from real migrations)

- The app registry drives the sidebar — updating only `~/.claude.json` changes nothing visible.
- The app recreates project dirs on startup if the registry still points at old paths.
- The sidebar group name comes from the git remote's repo name, not the folder name.
- Validate JSON after every edit; one trailing comma breaks the whole config.
- `Application Support` contains a space — quote every path.
