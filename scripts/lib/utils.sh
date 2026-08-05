#!/bin/bash

# --- Colors and output helpers ---
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
CYAN=$'\033[0;36m'
BLUE=$'\033[0;34m'
NC=$'\033[0m'

safe_echo() {
    printf '%s\n' "$1"
}

# Send logs to stderr so $(...) does not consume them; keep data on stdout.
info() { safe_echo "${GREEN}[INFO] $1${NC}" >&2; }
step() { safe_echo "${BLUE}[INFO] $1${NC}" >&2; }
backup_info() { safe_echo "${CYAN}[INFO] $1${NC}" >&2; }
warn() { safe_echo "${YELLOW}[WARN] $1${NC}" >&2; }
error() { safe_echo "${RED}[ERROR] $1${NC}" >&2; exit 1; }

# Global step counter shared across child processes.
#   USE_STEP_CHAIN=1  Continue progress started by the installer.
#   USE_STEP_TOTAL    Total steps.
#   USE_STEP_CURRENT  Completed steps.
_use_step_is_uint() {
    case "${1:-}" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

# Usage: next_step "Creating directory structure..."
next_step() {
    local current=0
    if _use_step_is_uint "${USE_STEP_CURRENT:-}"; then
        current=$USE_STEP_CURRENT
    fi
    current=$((current + 1))
    export USE_STEP_CURRENT=$current

    if _use_step_is_uint "${USE_STEP_TOTAL:-}" && [ "$USE_STEP_TOTAL" -gt 0 ]; then
        step "Step ${current}/${USE_STEP_TOTAL}: $1"
    else
        step "$1"
    fi
}

# Usage: init_step_progress 4
# Without USE_STEP_CHAIN=1, reset to this script's step count.
# With chaining, total = completed + this script's steps.
init_step_progress() {
    local local_steps="${1:?}"
    if [ "${USE_STEP_CHAIN:-}" = "1" ]; then
        local current=0
        if _use_step_is_uint "${USE_STEP_CURRENT:-}"; then
            current=$USE_STEP_CURRENT
        fi
        export USE_STEP_CURRENT=$current
        export USE_STEP_TOTAL=$((current + local_steps))
        return
    fi
    export USE_STEP_TOTAL=$local_steps
    export USE_STEP_CURRENT=0
}

# Check for a usable controlling terminal.
has_tty() {
    [ -t 0 ] && return 0
    { true </dev/tty; } 2>/dev/null
}

# Normalize Git remotes for repository comparison.
normalize_repo_url() {
    local u
    u=$(strip_github_accel_prefix "$1")
    while [ "${u%/}" != "$u" ]; do u="${u%/}"; done
    case "$u" in
        *.git) u="${u%.git}" ;;
    esac
    u="${u#https://}"
    u="${u#http://}"
    u="${u#ssh://git@}"
    u="${u#git@}"
    u="${u//://}"
    printf '%s' "$u"
}

_github_accel_load() {
    if [ -n "${GITHUB_ACCEL_LOADED:-}" ]; then
        return 0
    fi
    GITHUB_ACCEL_LOADED=1
    GITHUB_ACCEL_DEFAULT_PREFIX=""
    GITHUB_ACCEL_PREFIXES=()

    local common_manifest="${PROJECT_ROOT}/scripts/common/_manifest.json"
    [ -f "$common_manifest" ] || return 0

    local data
    data=$(node -e "
        const m = require(process.argv[1]);
        const cfg = m.githubAccel || {};
        const mirrors = Array.isArray(cfg.mirrors) ? cfg.mirrors : [];
        const def = String(cfg.default || '');
        let defaultPrefix = '';
        const prefixes = [];
        for (const item of mirrors) {
            let p = String(item?.prefix || '');
            if (!p) continue;
            if (!p.endsWith('/')) p += '/';
            prefixes.push(p);
            if (def && String(item?.id || '') === def) defaultPrefix = p;
        }
        if (!defaultPrefix && prefixes.length) defaultPrefix = prefixes[0];
        process.stdout.write(defaultPrefix + '\n' + prefixes.join('\n'));
    " "$common_manifest" 2>/dev/null) || return 0

    local line i=0
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$i" -eq 0 ]; then
            GITHUB_ACCEL_DEFAULT_PREFIX="$line"
        elif [ -n "$line" ]; then
            GITHUB_ACCEL_PREFIXES+=("$line")
        fi
        i=$((i + 1))
    done <<< "$data"
}

strip_github_accel_prefix() {
    _github_accel_load
    local url="$1"
    local p
    for p in "${GITHUB_ACCEL_PREFIXES[@]}"; do
        [ -n "$p" ] || continue
        case "$url" in
            "$p"*) printf '%s' "${url#"$p"}"; return 0 ;;
        esac
    done
    printf '%s' "$url"
}

is_github_http_url() {
    local bare
    bare=$(strip_github_accel_prefix "$1")
    case "$bare" in
        https://github.com/*|https://raw.githubusercontent.com/*) return 0 ;;
        *) return 1 ;;
    esac
}

github_accel_url() {
    local url="$1"
    if ! is_github_http_url "$url"; then
        printf '%s' "$url"
        return 0
    fi
    _github_accel_load
    local bare
    bare=$(strip_github_accel_prefix "$url")
    if [ -n "$GITHUB_ACCEL_DEFAULT_PREFIX" ]; then
        printf '%s%s' "$GITHUB_ACCEL_DEFAULT_PREFIX" "$bare"
    else
        printf '%s' "$bare"
    fi
}

# Print candidate URLs: default mirror, other mirrors, then upstream.
github_accel_url_candidates() {
    local url="$1"
    if ! is_github_http_url "$url"; then
        printf '%s\n' "$url"
        return 0
    fi
    _github_accel_load
    local bare
    bare=$(strip_github_accel_prefix "$url")
    local seen=$'\n'
    local p candidate
    if [ -n "$GITHUB_ACCEL_DEFAULT_PREFIX" ]; then
        candidate="${GITHUB_ACCEL_DEFAULT_PREFIX}${bare}"
        printf '%s\n' "$candidate"
        seen="${seen}${candidate}"$'\n'
    fi
    for p in "${GITHUB_ACCEL_PREFIXES[@]}"; do
        [ -n "$p" ] || continue
        candidate="${p}${bare}"
        case "$seen" in
            *$'\n'"$candidate"$'\n'*) continue ;;
        esac
        printf '%s\n' "$candidate"
        seen="${seen}${candidate}"$'\n'
    done
    case "$seen" in
        *$'\n'"$bare"$'\n'*) ;;
        *) printf '%s\n' "$bare" ;;
    esac
}

# Usage: is_same_remote_repo <dir> <expected-url>
is_same_remote_repo() {
    local dir="$1"
    local expected="$2"
    [ -d "$dir/.git" ] || return 1
    local remote
    remote=$(git -C "$dir" remote get-url origin 2>/dev/null) || return 1
    [ "$(normalize_repo_url "$remote")" = "$(normalize_repo_url "$expected")" ]
}

# Install or update a Git-based plugin.
# Usage: sync_git_repo_plugin <repo> <target_dir> <name> [1]
# Pass 1 as the fourth argument to update an existing plugin.
update_git_repo_to_latest() {
    local dir="$1"
    git -C "$dir" fetch --prune origin || return 1

    local branch
    branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
    if [ "$branch" = "HEAD" ]; then
        branch=$(git -C "$dir" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
        branch="${branch#origin/}"
        [ -n "$branch" ] || return 1
    fi

    git -C "$dir" reset --hard "origin/$branch"
}

install_git_repo_clone() {
    local repo="$1"
    local target_dir="$2"
    local plugin_name="$3"
    local url ok=0

    info "Downloading plugin: $plugin_name..."
    while IFS= read -r url; do
        [ -n "$url" ] || continue
        rm -rf "$target_dir"
        if git clone "$url" "$target_dir"; then
            ok=1
            break
        fi
    done < <(github_accel_url_candidates "$repo")

    if [ "$ok" -ne 1 ]; then
        warn "Failed to download $plugin_name; skipping"
        return 1
    fi
    info "$plugin_name download complete"
}

sync_git_repo_plugin() {
    local repo="$1"
    local target_dir="$2"
    local plugin_name="$3"
    local update="${4:-0}"

    if [ ! -d "$target_dir" ]; then
        install_git_repo_clone "$repo" "$target_dir" "$plugin_name"
        return
    fi

    if [ "$update" != "1" ]; then
        info "Plugin $plugin_name already exists; skipping"
        return
    fi

    if is_same_remote_repo "$target_dir" "$repo"; then
        info "Plugin $plugin_name is linked to the remote repository; updating..."
        local accel
        accel=$(github_accel_url "$repo")
        local current
        current=$(git -C "$target_dir" remote get-url origin 2>/dev/null || true)
        if [ -n "$accel" ] && [ "$current" != "$accel" ]; then
            git -C "$target_dir" remote set-url origin "$accel" 2>/dev/null || true
        fi
        if update_git_repo_to_latest "$target_dir"; then
            info "$plugin_name is up to date"
        else
            local bare
            bare=$(strip_github_accel_prefix "$repo")
            git -C "$target_dir" remote set-url origin "$bare" 2>/dev/null || true
            if update_git_repo_to_latest "$target_dir"; then
                info "$plugin_name is up to date (upstream)"
            else
                warn "Failed to update $plugin_name; skipping"
            fi
        fi
        return
    fi

    info "Plugin $plugin_name is not the expected repository; reinstalling..."
    rm -rf "$target_dir"
    install_git_repo_clone "$repo" "$target_dir" "$plugin_name"
}

# Read a line from the controlling terminal when stdin is piped.
# Usage: answer=$(read_tty "Prompt: ") || error "Non-interactive environment"
read_tty() {
    local prompt="${1:-}"
    local line=""

    if [ -n "$prompt" ]; then
        printf '%s' "$prompt" >&2
    fi

    if { read -r line < /dev/tty; } 2>/dev/null; then
        printf '%s\n' "$line"
        return 0
    fi

    if [ -t 0 ] && read -r line; then
        printf '%s\n' "$line"
        return 0
    fi

    return 1
}

# --- OS detection ---
detect_os() {
    local uname_s
    uname_s="$(uname -s 2>/dev/null || true)"
    case "$uname_s" in
        Darwin)  echo "macos" ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        Linux)   echo "linux" ;;
        *)
            case "${OSTYPE:-}" in
                msys*|cygwin*) echo "windows" ;;
                darwin*) echo "macos" ;;
                linux*) echo "linux" ;;
                *)
                    if [ "${OS:-}" = "Windows_NT" ] || [ -n "${WINDIR:-}" ]; then
                        echo "windows"
                    else
                        echo "unknown"
                    fi
                    ;;
            esac
            ;;
    esac
}

# Expected value: macos, windows, or linux.
check_target_os() {
    local current
    current=$(detect_os)
    [[ "$current" != "$1" ]] && error "This script supports only $1; detected $current"
}

# --- Backups with custom paths and dated sequence numbers ---
# Usage: backup_file <target-file> [backup-directory]
backup_file() {
    # Print the backup filename relative to backup_dir; print nothing on failure.
    local target_file="$1"
    local backup_dir="${2:-$(dirname "$target_file")}"

    if [ ! -f "$target_file" ]; then
        return 0
    fi

    if ! mkdir -p "$backup_dir"; then
        warn "Could not create backup directory: $backup_dir"
        return 0
    fi

    local file_name=$(basename "$target_file")
    local date_str=$(date +%Y%m%d)
    local backup_base="${backup_dir}/${file_name}.bak.${date_str}"

    local next_num=0
    while [ -f "${backup_base}.${next_num}" ]; do
        ((next_num++))
    done

    local backup_file="${backup_base}.${next_num}"

    if cp "$target_file" "$backup_file" 2>/dev/null; then
        echo "${file_name}.bak.${date_str}.${next_num}"
    else
        warn "Backup failed: $file_name"
    fi
}

# --- Parse config-sync direction ---
# Usage: direction=$(prompt_sync_direction "$1" "Example: vpr sync 2")
prompt_sync_direction() {
    local arg="$1"
    local example="${2:-Example: vpr sync 2}"
    local hint

    if [ "$arg" = "1" ] || [ "$arg" = "2" ]; then
        echo "$arg"
        return 0
    fi

    if [ -n "$arg" ]; then
        # Do not use error(): this function runs in $(...), so exit affects only the subshell.
        safe_echo "${RED}[ERROR] Invalid sync direction; use 1 or 2
$example${NC}" >&2
        return 1
    fi

    local choice=""
    choice=$(node "${SCRIPT_DIR}/lib/sync-direction.mjs") || choice=""
    choice=${choice//$'\r'/}
    choice=${choice//$'\n'/}

    if [ "$choice" != "1" ] && [ "$choice" != "2" ]; then
        hint=$(node "${SCRIPT_DIR}/lib/sync-direction.mjs" --hint 2>/dev/null) || hint="1=back up config to repository, 2=restore config locally"
        safe_echo "${RED}[ERROR] Pass a direction in non-interactive environments: ${hint}
$example${NC}" >&2
        return 1
    fi

    echo "$choice"
}

# --- Read manifest.json ---
expand_path() {
    local path="$1"
    case "$path" in
        "~/"*) echo "$HOME/${path#\~/}" ;;
        "~")    echo "$HOME" ;;
        *)      echo "$path" ;;
    esac
}

format_repo_display() {
    local path="$1"
    case "$path" in
        ./*) echo "$path" ;;
        *)   echo "./$path" ;;
    esac
}

format_local_display() {
    local path="${1//\\//}"
    case "$path" in
        ~) echo "~"; return ;;
        ~/*) echo "$path"; return ;;
    esac
    local home="${HOME%/}"
    if [ "$path" = "$home" ]; then
        echo "~"
    elif [[ "$path" == "$home/"* ]]; then
        echo "~/${path#$home/}"
    else
        echo "$path"
    fi
}

sync_select_run() {
    local direction="$1"
    local pairs_file="$2"
    local filtered_file="$3"
    local node_script="${SCRIPT_DIR}/lib/sync-select.mjs"
    local rc=0

    if has_tty; then
        SYNC_INTERACTIVE=1 node "$node_script" "$direction" "$pairs_file" "$filtered_file" || rc=$?
    else
        node "$node_script" "$direction" "$pairs_file" "$filtered_file" || rc=$?
    fi

    if [ "$rc" -ne 0 ]; then
        rm -f "$pairs_file" "$filtered_file"
        if [ "$rc" -eq 130 ]; then
            error "File selection canceled"
        fi
        error "File selection failed; retry or run through vpr sync"
    fi
}

init_manifest() {
    local scope="$1"
    if [[ -z "$scope" ]]; then
        error "init_manifest requires a scope: macos|windows|common"
    fi
    local manifest_path="${PROJECT_ROOT}/scripts/${scope}/_manifest.json"
    if [[ ! -f "$manifest_path" ]]; then
        error "Manifest not found: $manifest_path"
    fi
    MANIFEST_SCOPE="$scope"
    MANIFEST_PATH="$manifest_path"
}

manifest_get() {
    local key="$1"
    local scope="${2:-}"
    local manifest_path="$MANIFEST_PATH"

    if [[ -n "$scope" ]]; then
        manifest_path="${PROJECT_ROOT}/scripts/${scope}/_manifest.json"
        if [[ ! -f "$manifest_path" ]]; then
            error "Manifest not found: $manifest_path"
        fi
    elif [[ -z "$manifest_path" ]]; then
        error "Call init_manifest first"
    fi

    node -e "
        const m = require(process.argv[1]);
        let v = m;
        for (const k of process.argv[2].split('.')) {
            v = v?.[k];
        }
        if (v === undefined || v === null) {
            process.stderr.write('Manifest setting missing: ' + process.argv[2] + '\n');
            process.exit(1);
        }
        if (typeof v === 'object') console.log(JSON.stringify(v));
        else console.log(String(v));
    " "$manifest_path" "$key"
}

manifest_directories() {
    local scopes=("$@")
    if [[ ${#scopes[@]} -eq 0 ]]; then
        if [[ -z "$MANIFEST_SCOPE" ]]; then
            error "Call init_manifest first"
        fi
        scopes=("$MANIFEST_SCOPE")
        if [[ "$MANIFEST_SCOPE" == macos || "$MANIFEST_SCOPE" == windows ]]; then
            scopes=("common" "$MANIFEST_SCOPE")
        fi
    fi

    node -e "
        const path = require('path');
        const projectRoot = process.argv[1];
        const scopes = process.argv.slice(2);
        const seen = new Set();
        for (const scope of scopes) {
            const m = require(path.join(projectRoot, 'scripts', scope, '_manifest.json'));
            for (const d of m.directories ?? []) {
                if (!seen.has(d)) {
                    seen.add(d);
                    console.log(d);
                }
            }
        }
    " "$PROJECT_ROOT" "${scopes[@]}"
}

manifest_sync_pairs() {
    local direction="$1"
    shift
    local scopes=("$@")
    if [[ ${#scopes[@]} -eq 0 ]]; then
        if [[ -z "$MANIFEST_SCOPE" ]]; then
            error "Call init_manifest first"
        fi
        scopes=("$MANIFEST_SCOPE")
    fi

    node -e "
        const fs = require('fs');
        const path = require('path');
        const projectRoot = process.argv[1];
        const direction = process.argv[2];
        const scopes = process.argv.slice(3);
        for (const scope of scopes) {
            const manifestPath = path.join(projectRoot, 'scripts', scope, '_manifest.json');
            if (!fs.existsSync(manifestPath)) {
                process.stderr.write('Manifest not found: ' + manifestPath + '\n');
                process.exit(1);
            }
            const m = require(manifestPath);
            const liteOnly = process.env.SYNC_PROFILE === 'lite';
            for (const item of m.sync.toRepo) {
                if (liteOnly && item.lite === false) continue;
                if (direction === '1' && item.restoreOnly === true) continue;
                process.stdout.write(item.local + '\t' + item.repo + '\t' + (item.backup ? '1' : '0') + '\t' + (item.encoding || '') + '\t' + (item.defaultSelected === false ? '0' : '1') + '\n');
            }
        }
    " "$PROJECT_ROOT" "$direction" "${scopes[@]}"
}

should_skip_sync_select() {
    [ "$SYNC_SELECT_ALL" = "1" ] && return 0
    has_tty && return 1
    return 0
}

is_sync_dispatch_mode() {
    [ "$SYNC_FROM_DISPATCH" = "1" ]
}

sync_progress_hint() {
    local direction="$1"
    local total="$2"

    [ "$total" -gt 0 ] || return 0
    is_sync_dispatch_mode && return 0

    if [ "$direction" = "1" ]; then
        step "Backing up $total files to the repository..."
    else
        step "Restoring $total files locally..."
    fi
}

manifest_sync_pairs_filtered() {
    local direction="$1"
    shift
    local scopes=("$@")
    local pairs_file filtered_file

    if [ -n "$SYNC_FILTERED_PAIRS" ] && [ -f "$SYNC_FILTERED_PAIRS" ]; then
        cat "$SYNC_FILTERED_PAIRS"
        rm -f "$SYNC_FILTERED_PAIRS"
        unset SYNC_FILTERED_PAIRS
        return
    fi

    if is_sync_dispatch_mode; then
        if should_skip_sync_select; then
            manifest_sync_pairs "$direction" "${scopes[@]}"
            return
        fi
        error "Selected-file list missing; run through vpr sync"
    fi

    pairs_file=$(mktemp) || error "Could not create temporary file"
    manifest_sync_pairs "$direction" "${scopes[@]}" > "$pairs_file"

    if should_skip_sync_select; then
        cat "$pairs_file"
        rm -f "$pairs_file"
        return
    fi

    filtered_file=$(mktemp) || { rm -f "$pairs_file"; error "Could not create temporary file"; }
    sync_select_run "$direction" "$pairs_file" "$filtered_file"
    cat "$filtered_file"
    rm -f "$pairs_file" "$filtered_file"
}

run_config_sync() {
    local scope="$1"
    shift
    local direction_arg=""
    local invalid_direction_arg=""
    local sync_scopes=("$scope")

    if [[ "$scope" == "macos" || "$scope" == "windows" ]]; then
        sync_scopes+=("common")
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            1|2) direction_arg="$1" ;;
            --) ;;
            *)
                [ -n "$1" ] && invalid_direction_arg="$1"
                ;;
        esac
        shift
    done

    local direction_input="$direction_arg"
    [ -z "$direction_input" ] && direction_input="$invalid_direction_arg"

    local example="Example: vpr sync 2"
    if is_sync_dispatch_mode && [ "$direction_input" != "1" ] && [ "$direction_input" != "2" ]; then
        error "Sync direction missing: $example"
    fi

    direction=$(prompt_sync_direction "$direction_input" "$example") || exit 1

    sync_pairs=()
    while IFS= read -r line; do
        [ -n "$line" ] && sync_pairs+=("$line")
    done < <(manifest_sync_pairs_filtered "$direction" "${sync_scopes[@]}")
    total=${#sync_pairs[@]}
    [ "$total" -gt 0 ] || error "No configuration items to sync"
    sync_progress_hint "$direction" "$total"
    i=0

    case $direction in
        1)
            for pair in "${sync_pairs[@]}"; do
                IFS=$'\t' read -r local_path repo_path _backup_flag <<< "$pair"
                local_abs=$(expand_path "$local_path")
                repo_abs="${PROJECT_ROOT}/${repo_path}"
                repo_display=$(format_repo_display "$repo_path")
                mkdir -p "$(dirname "$repo_abs")" || error "Could not create directory: $(format_repo_display "$(dirname "$repo_path")")"
                cp "$local_abs" "$repo_abs" || error "Backup failed: $local_path -> $repo_display"
                i=$((i + 1))
                backup_info "[$i/$total] Backed up $repo_display"
            done

            info "Configuration backed up to the repository"
            ;;
        2)
            for pair in "${sync_pairs[@]}"; do
                IFS=$'\t' read -r local_path repo_path backup_flag <<< "$pair"
                local_abs=$(expand_path "$local_path")
                repo_abs="${PROJECT_ROOT}/${repo_path}"
                repo_display=$(format_repo_display "$repo_path")
                i=$((i + 1))
                if [ "$backup_flag" = "1" ]; then
                    bak_name=$(backup_file "$local_abs" ~/.backup)
                    if [ -n "$bak_name" ]; then
                        backup_info "[$i/$total] Backed up $(format_local_display "$local_path") -> ~/.backup/$bak_name"
                    fi
                fi
                mkdir -p "$(dirname "$local_abs")" || error "Could not create directory: $(dirname "$local_path")"
                cp "$repo_abs" "$local_abs" || error "Restore failed: $repo_display -> $local_path"
                backup_info "[$i/$total] Restored $(format_local_display "$local_path")"
            done

            info "Configuration restored locally"
            ;;
        *)
            error "Invalid selection"
            ;;
    esac
}
