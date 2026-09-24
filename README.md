<p align="center">
  <h1 align="center">migrate-claude-code</h1>
  <p align="center">
    Move or rename a Claude Code project folder without losing session history, sidebar entries, worktrees, or config.
  </p>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-blue" alt="Platform" />
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License" />
  <img src="https://img.shields.io/badge/shell-bash-lightgrey" alt="Bash" />
  <img src="https://img.shields.io/badge/status-archived-lightgrey" alt="Archived" />
</p>

> [!WARNING]
> **Archived — not maintained.** Claude Code's on-disk storage is undocumented and changes without notice. v2.0.0 was tested against Claude Code 2.1.x in September 2026. Always run `--dry-run` first and read what it plans to change.
>
> **If you used v1.x:** it encoded session folder names wrongly for paths containing spaces, dots or underscores, and ignored worktrees. Moves made with v1 may have left session history under the old folder name in `~/.claude/projects/`. The history is still there, not deleted.

---

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/Anthropicary/migrate-claude-code/main/migrate-claude.sh -o ~/.claude/migrate-claude.sh
chmod +x ~/.claude/migrate-claude.sh

# 1. Preview — changes nothing
~/.claude/migrate-claude.sh --dry-run ~/old/my-app ~/Developer/my-app

# 2. Quit the Claude desktop app (⌘Q), then run for real from a terminal
~/.claude/migrate-claude.sh ~/old/my-app ~/Developer/my-app

# Undo, if needed
~/.claude/migrate-claude.sh --restore ~/.claude-backups/pre-migration-YYYYMMDD-HHMMSS
```

Read the script before running it — it's one file, ~550 lines of bash + embedded Python, no dependencies beyond `python3` and `git`.

## The problem

You move a project folder and then:

- the sidebar shows ghost projects that keep coming back
- sessions won't resume; Claude has lost your history
- worktrees break, both in the app and in git

Claude Code writes the project's **absolute path** into several places. Change one and miss another, and things break.

## Where the path lives

| Store | What holds the path |
|---|---|
| `~/.claude.json` → `projects` | Keys: the project, plus one per worktree |
| `~/.claude/projects/<encoded-path>/` | Session transcripts. One folder per path, including each worktree |
| App registry `claude-code-sessions/<account>/<org>/local_*.json` | `cwd`, `originCwd`, `worktreePath`, `planPath`. The sidebar reads these |
| App `git-worktrees.json` | Worktrees the app manages: `path`, `baseRepo`, cleanup state |
| git | Links between worktree and repo |

App data lives in `~/Library/Application Support/Claude/` on macOS and `~/.config/Claude/` on Linux.

## What the script does

1. **Pre-flight.** Checks the source, the destination and the config, then prints exactly what will change.
2. **Backup.** Copies every JSON store it will touch, plus the affected transcript folders, to `~/.claude-backups/pre-migration-<timestamp>/`.
3. **Migrate:**
   - copies transcript folders to their new encoded names (it never moves them)
   - moves the project folder
   - rewrites every stored path equal to or under the source
   - runs `git worktree repair`
4. **Verify.** Checks that no stale paths remain, the transcript counts match, and the git worktrees are healthy.
5. **Cleanup.** Only after verification passes, it asks before deleting the old transcript folders.

| Option | |
|---|---|
| `--dry-run` | Show the plan and change nothing |
| `--yes` | Skip prompts. Still backs up and verifies, and never deletes old transcripts |
| `--restore <dir>` | Undo a migration from its backup |

The `.md` files are optional Claude Code slash commands (`/migrate-claude`, `/verify-migration`, `/backup-claude`, `/restore-claude`, `/diagnose-claude`). Copy them into `~/.claude/commands/`. `/migrate-claude` drives the script.

## Traps (why hand-edits go wrong)

- **Path encoding.** Every character that isn't a letter or digit becomes `-`: spaces, dots and underscores too, not just `/`. So `/Users/alice/My App.v2` becomes `-Users-alice-My-App-v2`. The encoding is lossy, so encode the known paths and compare. Don't try to decode folder names.
- **Exact matching misses worktrees.** Match the path and everything under `path + "/"`. A bare prefix match wrongly catches `my-app-old` when you move `my-app`.
- **The desktop app holds state in memory.** Quit it before migrating, or it may write the old paths back.
- **The sidebar group name comes from the git remote's repo name,** not the folder name.
- **`Application Support` contains a space.** Quote every path.

## Limitations

- Transcript contents (`.jsonl`) still mention the old path inside the file. That's history, not config, and resuming works without changing it.
- Paths whose encoded name is longer than 200 characters get truncated and hashed by Claude. The script warns you, and you'll need to check those by hand.
- `--restore` puts JSON files back whole, so any session activity after the migration disappears from the sidebar. The transcripts are kept.
- Machine-to-machine moves aren't automated by the script. See `backup-claude.md` / `restore-claude.md` for the manual flow.
- Tested on macOS. The Linux paths follow the same layout but haven't been checked.

## License

MIT
