#!/usr/bin/env bash
set -euo pipefail

# migrate-claude.sh — Migrate a Claude Code project to a new directory
# Updates all 3 locations: ~/.claude.json, ~/.claude/projects/, and the app registry

VERSION="1.0.0"

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
FULL_BACKUP=false
SOURCE=""
DEST=""
APP_REGISTRY=""
BACKUP_DIR=""
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# ─── Helpers ──────────────────────────────────────────────────────────────────

info()    { echo -e "  ${BLUE}info${RESET}  $*"; }
success() { echo -e "  ${check_mark}  $*"; }
warn()    { echo -e "  ${warn_mark}  $*"; }
fail()    { echo -e "  ${cross_mark}  $*"; }
step()    { echo -e "\n${BOLD}${CYAN}$*${RESET}"; }
dry()     { if $DRY_RUN; then echo -e "  ${DIM}[dry-run]${RESET} $*"; fi; }

die() {
    echo -e "\n${RED}Error:${RESET} $*" >&2
    exit 1
}

confirm() {
    if $DRY_RUN; then return 0; fi
    local prompt="$1"
    echo -en "\n  ${YELLOW}?${RESET} ${prompt} ${DIM}[y/N]${RESET} "
    read -r response
    [[ "$response" =~ ^[Yy]$ ]]
}

encode_path() {
    echo "${1//\//-}"
}

# ─── Platform Detection ──────────────────────────────────────────────────────

detect_platform() {
    case "$(uname -s)" in
        Darwin)
            APP_REGISTRY="$HOME/Library/Application Support/Claude/claude-code-sessions"
            ;;
        Linux)
            APP_REGISTRY="$HOME/.config/Claude/claude-code-sessions"
            ;;
        *)
            die "Unsupported platform: $(uname -s). Only macOS and Linux are supported."
            ;;
    esac
}

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat <<EOF
${BOLD}migrate-claude${RESET} v${VERSION} — Migrate a Claude Code project directory

${BOLD}Usage:${RESET}
  migrate-claude.sh [options] <source> <destination>

${BOLD}Options:${RESET}
  --dry-run       Preview all changes without modifying anything
  --full-backup   Back up all sessions and registry (not just the migrated project)
  --help          Show this help message
  --version       Show version

${BOLD}Examples:${RESET}
  migrate-claude.sh ~/Projects/my-app ~/Developer/my-app
  migrate-claude.sh --dry-run ~/old-path ~/new-path

${BOLD}What it does:${RESET}
  Updates all 3 locations where Claude Code stores project data:
  1. ~/.claude.json (project entries)
  2. ~/.claude/projects/ (session transcripts)
  3. App registry (sidebar state)

EOF
    exit 0
}

# ─── Phase 1: Pre-Flight ─────────────────────────────────────────────────────

preflight() {
    step "Phase 1: Pre-Flight Check"

    # Source exists
    if [[ -d "$SOURCE" ]]; then
        success "Source exists: ${DIM}$SOURCE${RESET}"
    else
        die "Source directory does not exist: $SOURCE"
    fi

    # Source has .claude
    if [[ -d "$SOURCE/.claude" ]]; then
        success "Source has .claude/ subdirectory"
    else
        warn "Source has no .claude/ subdirectory (may not be a Claude Code project)"
    fi

    # Destination parent exists
    local dest_parent
    dest_parent=$(dirname "$DEST")
    if [[ -d "$dest_parent" ]]; then
        success "Destination parent exists: ${DIM}$dest_parent${RESET}"
    else
        die "Destination parent directory does not exist: $dest_parent"
    fi

    # Destination doesn't already exist
    if [[ -e "$DEST" ]]; then
        die "Destination already exists: $DEST"
    fi

    # No running Claude Code sessions (desktop app is fine)
    if pgrep -fl "claude" 2>/dev/null | grep -v -E "(grep|Claude\.app|pgrep)" | grep -q .; then
        warn "Claude Code processes detected. Recommended to close active sessions before migrating."
    else
        success "No active Claude Code sessions running"
    fi

    # Config file
    if [[ -f "$HOME/.claude.json" ]]; then
        success "Config file exists: ${DIM}~/.claude.json${RESET}"
        if python3 -m json.tool "$HOME/.claude.json" > /dev/null 2>&1; then
            success "Config file is valid JSON"
        else
            die "$HOME/.claude.json is not valid JSON — fix this before migrating"
        fi
    else
        die "$HOME/.claude.json not found"
    fi

    # Check config has source project
    if python3 - "$HOME/.claude.json" "$SOURCE" << 'PYEOF' 2>/dev/null
import json, sys
config_path, source = sys.argv[1], sys.argv[2]
with open(config_path) as f:
    data = json.load(f)
sys.exit(0 if source in data.get('projects', {}) else 1)
PYEOF
    then
        success "Project entry found in config for source path"
    else
        warn "No project entry in ~/.claude.json for: $SOURCE"
    fi

    # Session files
    local encoded_source
    encoded_source=$(encode_path "$SOURCE")
    local session_dir="$HOME/.claude/projects/$encoded_source"
    if [[ -d "$session_dir" ]]; then
        local session_count
        session_count=$(find "$session_dir" -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
        success "Session directory found with ${BOLD}$session_count${RESET} transcript files"
    else
        warn "No session directory found at: $session_dir"
    fi

    # App registry
    if [[ -d "$APP_REGISTRY" ]]; then
        local registry_matches
        registry_matches=$(grep -rl "\"$SOURCE\"" "$APP_REGISTRY" 2>/dev/null | wc -l | tr -d ' ') || registry_matches=0
        success "App registry found with ${BOLD}$registry_matches${RESET} matching entries"
    else
        warn "App registry not found at: $APP_REGISTRY"
    fi

    echo ""
    info "${BOLD}Source:${RESET}      $SOURCE"
    info "${BOLD}Destination:${RESET} $DEST"
}

# ─── Phase 2: Backup ─────────────────────────────────────────────────────────

backup() {
    step "Phase 2: Backup"

    BACKUP_DIR="$HOME/.claude-backups/pre-migration-$TIMESTAMP"

    if $DRY_RUN; then
        dry "Would create backup at: $BACKUP_DIR"
        dry "Would copy ~/.claude.json"
        dry "Would copy ~/.claude/projects/"
        dry "Would copy app registry"
        return
    fi

    mkdir -p "$BACKUP_DIR"

    # Config
    cp "$HOME/.claude.json" "$BACKUP_DIR/claude.json"
    success "Backed up ~/.claude.json"

    # Session transcripts
    if $FULL_BACKUP; then
        if [[ -d "$HOME/.claude/projects" ]]; then
            cp -r "$HOME/.claude/projects" "$BACKUP_DIR/projects"
            success "Backed up ALL session transcripts (full backup)"
        fi
    else
        local old_encoded
        old_encoded=$(encode_path "$SOURCE")
        local old_session_dir="$HOME/.claude/projects/$old_encoded"
        if [[ -d "$old_session_dir" ]]; then
            mkdir -p "$BACKUP_DIR/projects/$old_encoded"
            cp -r "$old_session_dir"/* "$BACKUP_DIR/projects/$old_encoded"/ 2>/dev/null || true
            success "Backed up session transcripts (project only)"
        fi
    fi

    # App registry
    if [[ -d "$APP_REGISTRY" ]]; then
        if $FULL_BACKUP; then
            cp -r "$APP_REGISTRY" "$BACKUP_DIR/app-registry"
            success "Backed up ALL app registry entries (full backup)"
        else
            mkdir -p "$BACKUP_DIR/app-registry"
            local backup_registry_files
            backup_registry_files=$(grep -rl "\"$SOURCE\"" "$APP_REGISTRY" 2>/dev/null) || true
            if [[ -n "$backup_registry_files" ]]; then
                while IFS= read -r f; do
                    cp "$f" "$BACKUP_DIR/app-registry/"
                done <<< "$backup_registry_files"
            fi
            success "Backed up matching app registry entries"
        fi
    fi

    local backup_size
    backup_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    info "Backup location: ${DIM}$BACKUP_DIR${RESET} ($backup_size)"
}

# ─── Phase 3: Migration ──────────────────────────────────────────────────────

migrate() {
    step "Phase 3: Migration"

    # 3.1 Move project folder
    echo -e "\n  ${BOLD}3.1${RESET} Moving project folder"
    if $DRY_RUN; then
        dry "mv \"$SOURCE\" \"$DEST\""
    else
        mv "$SOURCE" "$DEST"
        if [[ -d "$DEST" ]]; then
            success "Moved project to: $DEST"
        else
            die "Failed to move project folder"
        fi
    fi

    # 3.2 Update ~/.claude.json
    echo -e "\n  ${BOLD}3.2${RESET} Updating ~/.claude.json"
    if $DRY_RUN; then
        dry "Would replace \"$SOURCE\" with \"$DEST\" in project keys"
    else
        python3 - "$HOME/.claude.json" "$SOURCE" "$DEST" << 'PYEOF'
import json, sys
config_path, old_path, new_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(config_path, 'r') as f:
    data = json.load(f)
projects = data.get('projects', {})
if old_path in projects:
    projects[new_path] = projects.pop(old_path)
    data['projects'] = projects
with open(config_path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PYEOF
        if python3 -m json.tool "$HOME/.claude.json" > /dev/null 2>&1; then
            success "Updated config (valid JSON)"
        else
            die "Config file corrupted after edit — restore from backup: $BACKUP_DIR/claude.json"
        fi
    fi

    # 3.3 Copy session transcripts
    echo -e "\n  ${BOLD}3.3${RESET} Copying session transcripts"
    local old_encoded new_encoded
    old_encoded=$(encode_path "$SOURCE")
    new_encoded=$(encode_path "$DEST")
    local old_session_dir="$HOME/.claude/projects/$old_encoded"
    local new_session_dir="$HOME/.claude/projects/$new_encoded"

    if [[ -d "$old_session_dir" ]]; then
        if $DRY_RUN; then
            dry "Would copy $old_session_dir → $new_session_dir"
        else
            mkdir -p "$new_session_dir"
            cp -r "$old_session_dir"/* "$new_session_dir"/ 2>/dev/null || true
            local count
            count=$(find "$new_session_dir" -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ')
            success "Copied $count session files to new location"
        fi
    else
        warn "No session directory to copy"
    fi

    # 3.4 Update app registry
    echo -e "\n  ${BOLD}3.4${RESET} Updating app registry"
    if [[ -d "$APP_REGISTRY" ]]; then
        local updated=0
        local registry_files
        registry_files=$(grep -rl "\"$SOURCE\"" "$APP_REGISTRY" 2>/dev/null || true)
        if [[ -n "$registry_files" ]]; then
            while IFS= read -r file; do
                if $DRY_RUN; then
                    dry "Would update: $(basename "$file")"
                else
                    python3 - "$file" "$SOURCE" "$DEST" << 'PYEOF'
import json, sys
fpath, old_path, new_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(fpath, 'r') as f:
    data = json.load(f)
changed = False
for key in ['cwd', 'originCwd']:
    if key in data and data[key] == old_path:
        data[key] = new_path
        changed = True
if changed:
    with open(fpath, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
PYEOF
                    if python3 -m json.tool "$file" > /dev/null 2>&1; then
                        ((updated++)) || true
                    else
                        fail "Corrupted after edit: $(basename "$file")"
                    fi
                fi
            done <<< "$registry_files"
            if ! $DRY_RUN; then
                success "Updated $updated app registry entries"
            fi
        else
            warn "No matching entries in app registry"
        fi
    else
        warn "App registry not found"
    fi
}

# ─── Phase 4: Verification ───────────────────────────────────────────────────

verify() {
    step "Phase 4: Verification"
    local all_passed=true

    # Config check
    if python3 - "$HOME/.claude.json" "$SOURCE" "$DEST" << 'PYEOF' 2>/dev/null
import json, sys
config_path, old_path, new_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(config_path) as f:
    data = json.load(f)
projects = data.get('projects', {})
sys.exit(0 if new_path in projects and old_path not in projects else 1)
PYEOF
    then
        success "Config: new path present, old path removed"
    else
        fail "Config: path mismatch"
        all_passed=false
    fi

    # JSON validity
    if python3 -m json.tool "$HOME/.claude.json" > /dev/null 2>&1; then
        success "Config: valid JSON"
    else
        fail "Config: invalid JSON"
        all_passed=false
    fi

    # Session files
    local new_encoded
    new_encoded=$(encode_path "$DEST")
    if [[ -d "$HOME/.claude/projects/$new_encoded" ]]; then
        success "Sessions: new directory exists"
    else
        fail "Sessions: new directory missing"
        all_passed=false
    fi

    # App registry
    if [[ -d "$APP_REGISTRY" ]]; then
        local old_refs
        old_refs=$(grep -rl "\"$SOURCE\"" "$APP_REGISTRY" 2>/dev/null | wc -l | tr -d ' ') || old_refs=0
        if [[ "$old_refs" -eq 0 ]]; then
            success "Registry: no stale references to old path"
        else
            fail "Registry: $old_refs files still reference old path"
            all_passed=false
        fi
    fi

    # Destination exists
    if [[ -d "$DEST" ]]; then
        success "Destination: project folder exists"
    else
        fail "Destination: project folder missing"
        all_passed=false
    fi

    if $DRY_RUN; then
        info "Dry run — verification checks are against current (unmodified) state"
    fi

    echo ""
    if $all_passed && ! $DRY_RUN; then
        echo -e "  ${GREEN}${BOLD}All checks passed!${RESET}"
    elif $DRY_RUN; then
        echo -e "  ${DIM}Dry run complete — no changes were made${RESET}"
    else
        echo -e "  ${RED}${BOLD}Some checks failed.${RESET} Restore from backup:"
        echo -e "  ${DIM}cp $BACKUP_DIR/claude.json ~/.claude.json${RESET}"
    fi
}

# ─── Phase 5: Cleanup ────────────────────────────────────────────────────────

cleanup() {
    if $DRY_RUN; then return; fi

    step "Phase 5: Cleanup"

    local old_encoded
    old_encoded=$(encode_path "$SOURCE")
    local old_session_dir="$HOME/.claude/projects/$old_encoded"

    if [[ -d "$old_session_dir" ]]; then
        if confirm "Remove old session directory? ($old_session_dir)"; then
            rm -rf "$old_session_dir"
            success "Removed old session directory"
        else
            info "Kept old session directory"
        fi
    fi

    echo ""
    info "Restart the Claude app to verify the sidebar shows the updated project."
    info "Once confirmed, you can delete the backup at: $BACKUP_DIR"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

main() {
    echo -e "\n${BOLD}${CYAN}migrate-claude${RESET} v${VERSION}\n"

    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)      DRY_RUN=true; shift ;;
            --full-backup)  FULL_BACKUP=true; shift ;;
            --help)         usage ;;
            --version)      echo "$VERSION"; exit 0 ;;
            -*)         die "Unknown option: $1" ;;
            *)
                if [[ -z "$SOURCE" ]]; then
                    SOURCE="$1"
                elif [[ -z "$DEST" ]]; then
                    DEST="$1"
                else
                    die "Too many arguments"
                fi
                shift
                ;;
        esac
    done

    # Resolve to absolute paths
    if [[ -n "$SOURCE" ]]; then
        SOURCE=$(cd "$SOURCE" 2>/dev/null && pwd || echo "$SOURCE")
    fi
    if [[ -n "$DEST" ]]; then
        # Dest might not exist yet, resolve parent
        local dest_parent dest_name
        dest_parent=$(cd "$(dirname "$DEST")" 2>/dev/null && pwd || dirname "$DEST")
        dest_name=$(basename "$DEST")
        DEST="$dest_parent/$dest_name"
    fi

    # Interactive mode if no args
    if [[ -z "$SOURCE" ]]; then
        echo -en "  ${YELLOW}?${RESET} Source project directory: "
        read -r SOURCE
        SOURCE=$(cd "$SOURCE" 2>/dev/null && pwd || echo "$SOURCE")
    fi
    if [[ -z "$DEST" ]]; then
        echo -en "  ${YELLOW}?${RESET} Destination directory: "
        read -r DEST
        local dest_parent dest_name
        dest_parent=$(cd "$(dirname "$DEST")" 2>/dev/null && pwd || dirname "$DEST")
        dest_name=$(basename "$DEST")
        DEST="$dest_parent/$dest_name"
    fi

    [[ -z "$SOURCE" ]] && die "Source path is required"
    [[ -z "$DEST" ]] && die "Destination path is required"

    if $DRY_RUN; then
        echo -e "  ${DIM}Running in dry-run mode — no changes will be made${RESET}\n"
    fi

    detect_platform
    preflight

    if ! $DRY_RUN; then
        if ! confirm "Proceed with migration?"; then
            echo -e "\n  ${DIM}Migration cancelled${RESET}"
            exit 0
        fi
    fi

    backup
    migrate
    verify
    cleanup
}

main "$@"
