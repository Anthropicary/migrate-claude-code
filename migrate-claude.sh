#!/usr/bin/env bash
set -uo pipefail

# migrate-claude.sh — Move a Claude Code project folder without orphaning its
# sessions, sidebar entries, worktrees, or config.
#
# Every place Claude stores an absolute project path gets rewritten. Paths
# *inside* the project (worktrees, plan files) are remapped too, not just
# exact matches:
#   1. ~/.claude.json                    project keys (incl. worktree keys)
#   2. ~/.claude/projects/<encoded>/     session transcripts, one dir per path
#   3. App registry  local_*.json        cwd / originCwd / worktreePath / planPath
#   4. App git-worktrees.json            worktree path / baseRepo / GC state
#   5. git's own worktree links          via `git worktree repair`

VERSION="2.0.0"

# ─── Colors & Formatting ─────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

check_mark="${GREEN}✓${RESET}"
cross_mark="${RED}✗${RESET}"
warn_mark="${YELLOW}!${RESET}"

# ─── Globals ──────────────────────────────────────────────────────────────────

DRY_RUN=false
ASSUME_YES=false
SOURCE=""
DEST=""
APP_DIR=""
BACKUP_DIR=""
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
PROJECTS_DIR="$HOME/.claude/projects"
CONFIG="$HOME/.claude.json"

# ─── Helpers ──────────────────────────────────────────────────────────────────

info()    { echo -e "  ${BLUE}info${RESET}  $*"; }
success() { echo -e "  ${check_mark}  $*"; }
warn()    { echo -e "  ${warn_mark}  $*"; }
fail()    { echo -e "  ${cross_mark}  $*"; }
step()    { echo -e "\n${BOLD}${CYAN}$*${RESET}"; }

die() {
    echo -e "\n${RED}Error:${RESET} $*" >&2
    exit 1
}

confirm() {
    if $ASSUME_YES; then return 0; fi
    local prompt="$1"
    echo -en "\n  ${YELLOW}?${RESET} ${prompt} ${DIM}[y/N]${RESET} "
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

# ─── Path engine ─────────────────────────────────────────────────────────────
# All JSON reading/writing lives in one Python program so every store uses the
# same matching rule: a path is affected if it equals SOURCE or starts with
# SOURCE + "/". (Plain prefix matching would wrongly catch "/a/app-old" when
# moving "/a/app".)

engine() {
    python3 - "$@" <<'PYEOF'
import json, os, re, shutil, sys, glob

cmd, source, dest, config, projects_dir, app_dir = sys.argv[1:7]
registry_dir = os.path.join(app_dir, "claude-code-sessions")
worktrees_json = os.path.join(app_dir, "git-worktrees.json")

def affected(p):
    return isinstance(p, str) and (p == source or p.startswith(source + "/"))

def remap(p):
    return dest + p[len(source):]

def encode(p):
    # Claude Code names session dirs by replacing every non-alphanumeric
    # character with "-" (spaces, dots and underscores included, not just "/").
    return re.sub(r"[^A-Za-z0-9]", "-", p)

def rewrite(obj, hits):
    """Return obj with every affected string key/value remapped."""
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            nk = k
            if affected(k):
                nk = remap(k); hits.append(k)
            out[nk] = rewrite(v, hits)
        return out
    if isinstance(obj, list):
        return [rewrite(v, hits) for v in obj]
    if affected(obj):
        hits.append(obj)
        return remap(obj)
    return obj

def json_stores():
    stores = [config]
    if os.path.isfile(worktrees_json):
        stores.append(worktrees_json)
    stores += sorted(glob.glob(os.path.join(registry_dir, "*", "*", "local_*.json")))
    return [s for s in stores if os.path.isfile(s)]

def indent_of(text):
    m = re.match(r"\{\s*\n(\s+)", text)
    return m.group(1) if m else 2

def affected_paths():
    """Every distinct path under SOURCE that any store knows about, plus
    worktree dirs on disk — these are the session dirs we need to carry over."""
    paths = {source}
    for s in json_stores():
        try:
            hits = []
            rewrite(json.load(open(s)), hits)
            paths.update(hits)
        except Exception:
            pass
    wt_root = os.path.join(source, ".claude", "worktrees")
    if os.path.isdir(wt_root):
        paths.update(os.path.join(wt_root, d) for d in os.listdir(wt_root))
    return sorted(paths)

def session_pairs():
    """(old_dir, new_dir, path) for each affected path that has transcripts."""
    pairs = []
    for p in affected_paths():
        old = os.path.join(projects_dir, encode(p))
        if os.path.isdir(old):
            pairs.append((old, os.path.join(projects_dir, encode(remap(p))), p))
    return pairs

if cmd == "plan":
    for s in json_stores():
        try:
            hits = []
            rewrite(json.load(open(s)), hits)
        except Exception as e:
            print(f"BAD\t{s}\t{e}"); continue
        if hits:
            print(f"JSON\t{s}\t{len(hits)}")
    for old, new, p in session_pairs():
        n = len(glob.glob(os.path.join(old, "*.jsonl")))
        print(f"SESS\t{old}\t{new}\t{n}")
    for p in affected_paths():
        if len(encode(p)) > 200 or len(encode(remap(p))) > 200:
            print(f"LONG\t{p}")

elif cmd == "backup":
    bdir = sys.argv[7]
    os.makedirs(bdir, exist_ok=True)
    manifest = []
    for s in json_stores():
        rel = os.path.relpath(s, "/")
        target = os.path.join(bdir, "files", rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copy2(s, target); manifest.append(s)
    with open(os.path.join(bdir, "SESSIONS.tsv"), "w") as f:
        for old, new, _ in session_pairs():
            target = os.path.join(bdir, "projects", os.path.basename(old))
            shutil.copytree(old, target, dirs_exist_ok=True)
            f.write(f"{old}\t{new}\n")
    with open(os.path.join(bdir, "MANIFEST.txt"), "w") as f:
        f.write(f"source\t{source}\ndest\t{dest}\n")
        f.write("\n".join(manifest) + "\n")
    print(len(manifest))

elif cmd == "sessions":
    # Copy, never move: old dirs are removed only in cleanup, after verify.
    for old, new, _ in session_pairs():
        shutil.copytree(old, new, dirs_exist_ok=True)
        print(f"{os.path.basename(old)} -> {os.path.basename(new)}")

elif cmd == "apply":
    changed = 0
    for s in json_stores():
        text = open(s).read()
        try:
            data = json.loads(text)
        except Exception as e:
            print(f"SKIP invalid JSON: {s} ({e})", file=sys.stderr); continue
        hits = []
        new = rewrite(data, hits)
        if not hits:
            continue
        tmp = s + ".migrate-tmp"
        with open(tmp, "w") as f:
            json.dump(new, f, indent=indent_of(text), ensure_ascii=False)
            if text.endswith("\n"):
                f.write("\n")
        json.load(open(tmp))  # refuse to install anything that doesn't parse
        os.replace(tmp, s)
        changed += 1
    print(changed)

elif cmd == "verify":
    ok = True
    for s in json_stores():
        hits = []
        try:
            rewrite(json.load(open(s)), hits)
        except Exception as e:
            print(f"FAIL\tinvalid JSON: {s}"); ok = False; continue
        if hits:
            print(f"FAIL\t{len(hits)} stale path(s) in {s}"); ok = False
    if ok:
        print(f"OK\tno stale references in {len(json_stores())} JSON files")
    sys.exit(0 if ok else 1)
PYEOF
}

# ─── Platform Detection ──────────────────────────────────────────────────────

detect_platform() {
    case "$(uname -s)" in
        Darwin) APP_DIR="$HOME/Library/Application Support/Claude" ;;
        Linux)  APP_DIR="$HOME/.config/Claude" ;;
        *)      die "Unsupported platform: $(uname -s). Only macOS and Linux are supported." ;;
    esac
}

claude_app_running() {
    # Ask Launch Services by bundle id: the app's main process isn't reliably
    # visible to pgrep (and "claude" also matches Claude Code CLI binaries).
    if [[ "$(uname -s)" == Darwin ]]; then
        [[ "$(osascript -e 'application id "com.anthropic.claudefordesktop" is running' 2>/dev/null)" == true ]]
    else
        pgrep -x claude-desktop > /dev/null 2>&1
    fi
}

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
migrate-claude v${VERSION} — Move a Claude Code project folder safely

Usage:
  migrate-claude.sh [options] <source> <destination>

Options:
  --dry-run   Show exactly what would change; modify nothing
  --yes       Don't prompt (still backs up and verifies)
  --help      Show this help
  --version   Show version

Quit the Claude desktop app before a real run: it keeps session state in
memory and may write the old paths back when it quits.
EOF
    exit 0
}

# ─── Phase 1: Pre-Flight ─────────────────────────────────────────────────────

preflight() {
    step "Phase 1: Pre-Flight Check"

    [[ -d "$SOURCE" ]] || die "Source directory does not exist: $SOURCE"
    success "Source exists: ${DIM}$SOURCE${RESET}"
    [[ -L "$SOURCE" ]] && die "Source is a symlink — pass the real path: $(readlink "$SOURCE")"

    [[ -d "$(dirname "$DEST")" ]] || die "Destination parent does not exist: $(dirname "$DEST")"
    [[ -e "$DEST" ]] && die "Destination already exists: $DEST"
    case "$DEST/" in "$SOURCE"/*) die "Destination is inside the source folder" ;; esac
    success "Destination is free: ${DIM}$DEST${RESET}"

    [[ -f "$CONFIG" ]] || die "$CONFIG not found"
    python3 -m json.tool "$CONFIG" > /dev/null 2>&1 || die "$CONFIG is not valid JSON — fix it first"
    success "~/.claude.json is valid JSON"

    if claude_app_running; then
        warn "The Claude desktop app is running. It may write old paths back on quit."
        warn "Quit it (⌘Q) and run this from Terminal for a clean result."
        RUNNING_APP=true
    else
        success "Claude desktop app is not running"
        RUNNING_APP=false
    fi

    echo -e "\n  ${BOLD}What will change:${RESET}"
    local plan found_any=false reg_files=0 reg_paths=0
    plan=$(engine plan "$SOURCE" "$DEST" "$CONFIG" "$PROJECTS_DIR" "$APP_DIR") || die "Planning failed"
    while IFS=$'\t' read -r kind a b c; do
        [[ -z "$kind" ]] && continue
        found_any=true
        case "$kind" in
            JSON)
                if [[ "$a" == */claude-code-sessions/* ]]; then
                    ((reg_files++)); ((reg_paths += b))
                else
                    info "rewrite ${BOLD}$b${RESET} path(s) in ${DIM}${a/#$HOME/~}${RESET}"
                fi ;;
            SESS) info "copy ${BOLD}$c${RESET} transcript(s): ${DIM}$(basename "$a")${RESET} → ${DIM}$(basename "$b")${RESET}" ;;
            BAD)  warn "unreadable JSON, will be skipped: ${a/#$HOME/~}" ;;
            LONG) warn "path too long for a reliable session-dir name, check sessions by hand: $a" ;;
        esac
    done <<< "$plan"
    [[ $reg_files -gt 0 ]] && info "rewrite ${BOLD}$reg_paths${RESET} path(s) across ${BOLD}$reg_files${RESET} app session record(s) (sidebar)"
    $found_any || warn "Claude has no stored references to this folder — only the folder will move"

    if git -C "$SOURCE" rev-parse --git-dir > /dev/null 2>&1 \
       && [[ $(git -C "$SOURCE" worktree list --porcelain 2>/dev/null | grep -c '^worktree ') -gt 1 ]]; then
        info "git worktrees found — will run ${BOLD}git worktree repair${RESET} after the move"
    fi

    echo ""
    info "${BOLD}Source:${RESET}      $SOURCE"
    info "${BOLD}Destination:${RESET} $DEST"
}

# ─── Phase 2: Backup ─────────────────────────────────────────────────────────

backup() {
    step "Phase 2: Backup"
    BACKUP_DIR="$HOME/.claude-backups/pre-migration-$TIMESTAMP"
    local count
    count=$(engine backup "$SOURCE" "$DEST" "$CONFIG" "$PROJECTS_DIR" "$APP_DIR" "$BACKUP_DIR") \
        || die "Backup failed — nothing has been changed"
    success "Backed up $count JSON files + affected session dirs"
    info "Backup: ${DIM}$BACKUP_DIR${RESET} ($(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1))"
}

# ─── Phase 3: Migration ──────────────────────────────────────────────────────

migrate() {
    step "Phase 3: Migration"

    echo -e "\n  ${BOLD}3.1${RESET} Copying session transcripts"
    # Before the folder move: session_pairs() also discovers worktree dirs on disk.
    local copied
    copied=$(engine sessions "$SOURCE" "$DEST" "$CONFIG" "$PROJECTS_DIR" "$APP_DIR") \
        || die "Session copy failed — nothing else has been changed. Backup: $BACKUP_DIR"
    if [[ -n "$copied" ]]; then
        while IFS= read -r line; do success "$line"; done <<< "$copied"
    else
        info "No session transcripts to copy"
    fi

    echo -e "\n  ${BOLD}3.2${RESET} Moving project folder"
    mv "$SOURCE" "$DEST" || die "mv failed. Session copies were made but nothing else changed."
    success "Moved to: $DEST"

    echo -e "\n  ${BOLD}3.3${RESET} Rewriting stored paths"
    local changed
    if changed=$(engine apply "$SOURCE" "$DEST" "$CONFIG" "$PROJECTS_DIR" "$APP_DIR"); then
        success "Updated $changed JSON file(s)"
    else
        fail "Path rewrite failed. Restore: $0 --restore $BACKUP_DIR"
    fi

    echo -e "\n  ${BOLD}3.4${RESET} Repairing git worktree links"
    if git -C "$DEST" rev-parse --git-dir > /dev/null 2>&1; then
        local wts=()
        while IFS= read -r wt; do wts+=("$wt"); done < <(
            find "$DEST/.claude/worktrees" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
        if [[ ${#wts[@]} -gt 0 ]]; then
            if git -C "$DEST" worktree repair "${wts[@]}" > /dev/null 2>&1; then
                success "Repaired ${#wts[@]} worktree link(s)"
            else
                fail "git worktree repair failed — run it by hand in $DEST"
            fi
        else
            info "No worktrees inside the project"
        fi
    else
        info "Not a git repo"
    fi
}

# ─── Phase 4: Verification ───────────────────────────────────────────────────

verify() {
    step "Phase 4: Verification"
    local all_passed=true

    [[ -d "$DEST" && ! -e "$SOURCE" ]] && success "Folder: only at the new location" \
        || { fail "Folder: expected at $DEST and gone from $SOURCE"; all_passed=false; }

    local stale
    stale=$(engine verify "$SOURCE" "$DEST" "$CONFIG" "$PROJECTS_DIR" "$APP_DIR" 2>&1) || true
    while IFS=$'\t' read -r kind msg; do
        [[ -z "$kind" ]] && continue
        [[ "$kind" == OK ]] && success "$msg" || { fail "$msg"; all_passed=false; }
    done <<< "$stale"

    # Every transcript dir recorded at backup time must exist at its new name.
    local old new a b
    while IFS=$'\t' read -r old new; do
        [[ -z "$old" ]] && continue
        a=$(find "$BACKUP_DIR/projects/$(basename "$old")" -maxdepth 1 -name '*.jsonl' | wc -l | tr -d ' ')
        b=$(find "$new" -maxdepth 1 -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$b" -ge "$a" ]]; then
            success "Sessions: $a transcript(s) in ${DIM}$(basename "$new")${RESET}"
        else
            fail "Sessions: only $b/$a transcript(s) in $(basename "$new")"; all_passed=false
        fi
    done < "$BACKUP_DIR/SESSIONS.tsv"

    if git -C "$DEST" rev-parse --git-dir > /dev/null 2>&1; then
        if git -C "$DEST" worktree list --porcelain 2>/dev/null | grep -q '^prunable'; then
            fail "git: some worktrees are marked prunable (links still broken)"; all_passed=false
        else
            success "git: worktree links healthy"
        fi
    fi

    echo ""
    if $all_passed; then
        echo -e "  ${GREEN}${BOLD}All checks passed.${RESET}"
    else
        echo -e "  ${RED}${BOLD}Some checks failed.${RESET} Undo everything with:"
        echo -e "  ${DIM}$0 --restore \"$BACKUP_DIR\"${RESET}"
    fi
    $all_passed
}

# ─── Phase 5: Cleanup ────────────────────────────────────────────────────────

cleanup() {
    step "Phase 5: Cleanup"
    local old_dirs=() old new
    while IFS=$'\t' read -r old new; do
        [[ -n "$old" && -d "$old" ]] && old_dirs+=("$old")
    done < "$BACKUP_DIR/SESSIONS.tsv"

    if [[ ${#old_dirs[@]} -gt 0 ]]; then
        # Keep them unless explicitly confirmed; --yes does not delete history.
        if ! $ASSUME_YES && confirm "Remove ${#old_dirs[@]} old session dir(s)? (copies verified, backup kept)"; then
            rm -rf "${old_dirs[@]}"
            success "Removed old session dirs"
        else
            info "Kept old session dirs (harmless; delete later if you like)"
        fi
    fi
    info "Open the Claude app and check the sidebar shows the project at its new path."
    info "Backup kept at: $BACKUP_DIR"
}

# ─── Restore ─────────────────────────────────────────────────────────────────

restore() {
    local bdir="$1"
    [[ -f "$bdir/MANIFEST.txt" ]] || die "Not a migrate-claude backup: $bdir"
    local src dst
    src=$(awk -F'\t' '$1=="source"{print $2}' "$bdir/MANIFEST.txt")
    dst=$(awk -F'\t' '$1=="dest"{print $2}' "$bdir/MANIFEST.txt")
    step "Restoring from $bdir"
    info "This puts JSON files back and moves ${DIM}$dst${RESET} → ${DIM}$src${RESET}"
    confirm "Continue?" || exit 0
    (cd "$bdir/files" && find . -type f) | while IFS= read -r rel; do
        cp -p "$bdir/files/$rel" "/${rel#./}" && success "restored /${rel#./}"
    done
    # Put back any original session dirs that cleanup removed.
    local d
    for d in "$bdir"/projects/*; do
        [[ -d "$d" ]] || continue
        if [[ ! -d "$PROJECTS_DIR/$(basename "$d")" ]]; then
            cp -Rp "$d" "$PROJECTS_DIR/" && success "restored session dir $(basename "$d")"
        fi
    done
    if [[ -d "$dst" && ! -e "$src" ]]; then
        mv "$dst" "$src" && success "Moved folder back to $src"
        local wts=()
        while IFS= read -r wt; do wts+=("$wt"); done < <(
            find "$src/.claude/worktrees" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
        if [[ ${#wts[@]} -gt 0 ]]; then
            git -C "$src" worktree repair "${wts[@]}" > /dev/null 2>&1 \
                && success "Repaired ${#wts[@]} worktree link(s)" \
                || fail "git worktree repair failed — run it by hand in $src"
        fi
    fi
    info "Copies at the new session-dir names were left in place (harmless)."
    exit 0
}

# ─── Main ─────────────────────────────────────────────────────────────────────

abs_path() {
    # Absolute path without requiring the leaf to exist.
    local parent
    parent=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) || { echo "$1"; return; }
    echo "$parent/$(basename "$1")"
}

main() {
    echo -e "\n${BOLD}${CYAN}migrate-claude${RESET} v${VERSION}\n"
    detect_platform

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=true; shift ;;
            --yes|-y)  ASSUME_YES=true; shift ;;
            --restore) [[ -n "${2:-}" ]] || die "--restore needs a backup dir"; restore "$2" ;;
            --help|-h) usage ;;
            --version) echo "$VERSION"; exit 0 ;;
            -*)        die "Unknown option: $1" ;;
            *)
                if   [[ -z "$SOURCE" ]]; then SOURCE="$1"
                elif [[ -z "$DEST" ]];   then DEST="$1"
                else die "Too many arguments"; fi
                shift ;;
        esac
    done

    [[ -n "$SOURCE" && -n "$DEST" ]] || usage
    SOURCE=$(abs_path "${SOURCE%/}")
    DEST=$(abs_path "${DEST%/}")

    preflight

    if $DRY_RUN; then
        echo -e "\n  ${DIM}Dry run — nothing was changed.${RESET}"
        exit 0
    fi

    if [[ "${RUNNING_APP:-false}" == true ]] && ! $ASSUME_YES; then
        confirm "Claude app is running. Continue anyway?" || exit 0
    fi
    confirm "Proceed with migration?" || { echo -e "\n  ${DIM}Cancelled${RESET}"; exit 0; }

    backup
    migrate
    if verify; then
        cleanup
    else
        exit 1
    fi
}

main "$@"
