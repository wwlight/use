# Homebrew mirror switcher (bash/zsh). Provides `brew mirror` and a brew() wrapper.

_brew_mirror_root() {
    printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/homebrew"
}

_brew_mirror_catalog_file() {
    printf '%s/mirrors.tsv\n' "$(_brew_mirror_root)"
}

_brew_mirror_config_file() {
    printf '%s/mirror.zsh\n' "$(_brew_mirror_root)"
}

_brew_mirror_helper_file() {
    printf '%s/manage.zsh\n' "$(_brew_mirror_root)"
}

# Remove obsolete helper copies that would shadow this file.
_brew_mirror_remove_legacy() {
    local path
    for path in \
        "${HOME}/.zsh/functions/brew-mirror.zsh" \
        "$(_brew_mirror_root)/brew-mirror.zsh"
    do
        [[ -e "$path" ]] || continue
        rm -f "$path" 2>/dev/null || return 1
    done
    return 0
}

_brew_mirror_quote() {
    printf '%q' "$1"
}

_brew_mirror_find_brew() {
    # Resolve the real Homebrew binary; ignore the brew() mirror wrapper.
    local candidate=""
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        candidate=$(whence -p brew 2>/dev/null || true)
    elif [[ -n "${BASH_VERSION:-}" ]]; then
        candidate=$(type -P brew 2>/dev/null || true)
    else
        candidate=$(command -v brew 2>/dev/null || true)
    fi
    if [[ -n "$candidate" && "$candidate" != "brew" && -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

_brew_mirror_apply_shellenv() {
    local brew_path
    brew_path=$(_brew_mirror_find_brew) || return 0
    eval "$("$brew_path" shellenv)"
}

_brew_mirror_apply_env() {
    local config
    config=$(_brew_mirror_config_file) || return 1
    # shellenv first, then mirror exports.
    _brew_mirror_apply_shellenv
    [[ -r "$config" ]] || return 0
    # shellcheck disable=SC1090
    . "$config"
}

_brew_mirror_ensure_catalog() {
    local catalog header
    catalog=$(_brew_mirror_catalog_file) || return 1
    if [[ ! -r "$catalog" ]]; then
        printf 'brew mirror: catalog not found at %s\n' "$catalog" >&2
        return 1
    fi
    IFS= read -r header < "$catalog" || true
    if [[ "$header" != '# use-homebrew-mirrors-v1' ]]; then
        printf 'brew mirror: unsupported catalog header in %s\n' "$catalog" >&2
        return 1
    fi
}

_brew_mirror_rows() {
    local catalog
    catalog=$(_brew_mirror_catalog_file) || return 1
    tail -n +2 "$catalog"
}

_brew_mirror_lookup() {
    local target="$1" id label api bottle git
    _brew_mirror_ensure_catalog || return 1
    while IFS=$'\t' read -r id label api bottle git || [[ -n "${id:-}" ]]; do
        [[ -z "${id:-}" || "$id" == \#* ]] && continue
        if [[ "$id" == "$target" ]]; then
            if [[ -z "$label" || -z "$api" || -z "$bottle" || -z "$git" ]]; then
                printf 'brew mirror: invalid catalog row for %s\n' "$id" >&2
                return 1
            fi
            printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$label" "$api" "$bottle" "$git"
            return 0
        fi
    done < <(_brew_mirror_rows)
    return 1
}

_brew_mirror_ensure_profile() {
    local profile="${HOME}/.zprofile"
    local begin='# >>> use-homebrew'
    local end='# <<< use-homebrew'
    local helper config brew_path
    helper=$(_brew_mirror_helper_file)
    config=$(_brew_mirror_config_file)
    brew_path=$(_brew_mirror_find_brew) || brew_path=''

    _brew_mirror_remove_legacy || true

    local tmp
    tmp=$(mktemp "${TMPDIR:-/tmp}/use-zprofile.XXXXXX") || return 1

    if [[ -f "$profile" ]]; then
        local begin_count end_count
        begin_count=$(grep -cF "$begin" "$profile" || true)
        end_count=$(grep -cF "$end" "$profile" || true)
        if [[ "$begin_count" -ne "$end_count" ]]; then
            rm -f "$tmp"
            printf 'brew mirror: incomplete %s markers in %s; refusing to modify\n' "$begin" "$profile" >&2
            return 1
        fi
        if [[ "$begin_count" -gt 1 ]]; then
            rm -f "$tmp"
            printf 'brew mirror: duplicate %s markers in %s; refusing to modify\n' "$begin" "$profile" >&2
            return 1
        fi

        awk -v begin="$begin" -v end="$end" '
            $0 == begin { managed = 1; next }
            $0 == end { managed = 0; next }
            !managed { print }
        ' "$profile" > "$tmp" || {
            rm -f "$tmp"
            return 1
        }
    fi

    {
        [[ ! -s "$tmp" ]] || printf '\n'
        printf '%s\n' "$begin"
        [[ -z "$brew_path" ]] || printf 'eval "$(%s shellenv)"\n' "$brew_path"
        printf '[[ -r %s ]] && . %s\n' "$(_brew_mirror_quote "$config")" "$(_brew_mirror_quote "$config")"
        printf '[[ -r %s ]] && . %s\n' "$(_brew_mirror_quote "$helper")" "$(_brew_mirror_quote "$helper")"
        printf '%s\n' "$end"
    } >> "$tmp"
    mv "$tmp" "$profile"
}

_brew_mirror_write_config() {
    local mirror="$1"
    local row id label api bottle git config tmp
    row=$(_brew_mirror_lookup "$mirror") || {
        printf 'Unknown Homebrew mirror: %s\n' "$mirror" >&2
        return 1
    }
    IFS=$'\t' read -r id label api bottle git <<< "$row"

    config=$(_brew_mirror_config_file) || return 1
    mkdir -p "${config%/*}" || return 1

    tmp=$(mktemp "${config}.XXXXXX") || return 1
    {
        printf '# Managed by brew mirror. Do not edit.\n'
        printf 'export USE_HOMEBREW_MIRROR=%q\n' "$id"
        if [[ "$id" == "official" || "$api" == "-" ]]; then
            printf '%s\n' \
                'unset HOMEBREW_API_DOMAIN' \
                'unset HOMEBREW_BOTTLE_DOMAIN' \
                'unset HOMEBREW_BREW_GIT_REMOTE'
        else
            printf 'export HOMEBREW_API_DOMAIN=%q\n' "$api"
            printf 'export HOMEBREW_BOTTLE_DOMAIN=%q\n' "$bottle"
            printf 'export HOMEBREW_BREW_GIT_REMOTE=%q\n' "$git"
        fi
    } > "$tmp"
    mv "$tmp" "$config"
}

_brew_mirror_persisted_id() {
    local config
    config=$(_brew_mirror_config_file) || return 0
    [[ -r "$config" ]] || return 0
    # shellcheck disable=SC1090
    (
        unset USE_HOMEBREW_MIRROR
        . "$config"
        printf '%s' "${USE_HOMEBREW_MIRROR:-}"
    )
}

_brew_mirror_status() {
    printf 'Active Homebrew mirror: %s\n' "${USE_HOMEBREW_MIRROR:-official}"
    printf '  API:    %s\n' "${HOMEBREW_API_DOMAIN:-https://formulae.brew.sh/api}"
    printf '  Bottle: %s\n' "${HOMEBREW_BOTTLE_DOMAIN:-https://ghcr.io/v2/homebrew/core}"
    printf '  Brew:   %s\n' "${HOMEBREW_BREW_GIT_REMOTE:-https://github.com/Homebrew/brew}"
}

_brew_mirror_can_prompt() {
    [[ -t 0 && -t 1 ]] && return 0
    { true </dev/tty; } 2>/dev/null
}

_brew_mirror_menu_script() {
    local candidate
    for candidate in \
        "$(_brew_mirror_root)/lib/menu-select.mjs" \
        "${USE_HOMEBREW_MENU_SELECT:-}"; do
        [[ -n "$candidate" && -f "$candidate" ]] || continue
        printf '%s\n' "$candidate"
        return 0
    done
    return 1
}

# Build menu lines: id) * name ---- detail
_brew_mirror_aligned_choices() {
    local active="${1:-}"
    local id label api bottle git detail mark dashes
    local -a ids=()
    local max=0 pad dash_base=10

    while IFS=$'\t' read -r id label api bottle git || [[ -n "${id:-}" ]]; do
        [[ -z "${id:-}" || "$id" == \#* ]] && continue
        ids+=("$id")
        (( ${#id} > max )) && max=${#id}
    done < <(_brew_mirror_rows)

    (( ${#ids[@]} > 0 )) || return 1

    for id in "${ids[@]}"; do
        IFS=$'\t' read -r _ label api bottle git < <(_brew_mirror_lookup "$id") || continue
        if [[ "$api" != "-" && -n "$api" ]]; then
            detail="$api"
        elif [[ "$git" != "-" && -n "$git" ]]; then
            detail="$git"
        else
            detail="$label"
        fi
        mark=' '
        [[ "$id" == "$active" ]] && mark='*'
        pad=$((max - ${#id}))
        (( pad < 0 )) && pad=0
        dashes=$(printf '%*s' $((pad + dash_base)) '' | tr ' ' '-')
        printf '%s) %s %s %s %s\n' "$id" "$mark" "$id" "$dashes" "$detail"
    done
}

_brew_mirror_select_interactive() {
    local selected choice n=0 line menu_js
    local active="${USE_HOMEBREW_MIRROR:-}"
    [[ -n "$active" ]] || active=$(_brew_mirror_persisted_id)

    _brew_mirror_ensure_catalog || return 1

    local -a choices=()
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
        [[ -z "$line" ]] && continue
        choices+=("$line")
        n=$((n + 1))
    done < <(_brew_mirror_aligned_choices "$active")

    if (( n == 0 )); then
        printf 'brew mirror: catalog is empty\n' >&2
        return 1
    fi

    if ! _brew_mirror_can_prompt; then
        printf 'brew mirror: interactive selection requires a terminal\n' >&2
        return 1
    fi

    if command -v node >/dev/null 2>&1 && menu_js=$(_brew_mirror_menu_script); then
        local out
        out=$(mktemp "${TMPDIR:-/tmp}/brew-mirror-menu.XXXXXX") || return 1
        MENU_SELECT_OUT="$out" MENU_SELECT_INITIAL="$active" \
            node "$menu_js" 'Choose a Homebrew mirror' "${choices[@]}" || {
                local ec=$?
                rm -f "$out"
                return "$ec"
            }
        choice=$(tr -d '\r\n' < "$out")
        rm -f "$out"
        [[ -n "$choice" ]] || return 130
        printf '%s\n' "$choice"
        return 0
    fi

    if command -v fzf >/dev/null 2>&1; then
        local items="" id rest
        for line in "${choices[@]}"; do
            id="${line%%)*}"
            rest="${line#*) }"
            items+="${id}"$'\t'"${rest}"$'\n'
        done
        if [[ -t 0 ]]; then
            selected=$(printf '%s' "$items" |
                fzf --height=40% --reverse --border --prompt='Homebrew mirror > ') || return 130
        else
            selected=$(printf '%s' "$items" |
                fzf --height=40% --reverse --border --prompt='Homebrew mirror > ' </dev/tty) || return 130
        fi
        choice="${selected%%$'\t'*}"
        printf '%s\n' "$choice"
        return 0
    fi

    {
        printf 'Choose a Homebrew mirror:\n'
        local i=0
        for line in "${choices[@]}"; do
            i=$((i + 1))
            printf '  %d) %s\n' "$i" "${line#*) }"
        done
        printf 'Selection [1-%d]: ' "$n"
    } >/dev/tty

    if [[ -t 0 ]]; then
        IFS= read -r line || return 130
    else
        IFS= read -r line </dev/tty || return 130
    fi
    [[ "$line" =~ ^[0-9]+$ ]] || {
        printf 'brew mirror: invalid selection\n' >&2
        return 1
    }
    if (( line < 1 || line > n )); then
        printf 'brew mirror: invalid selection\n' >&2
        return 1
    fi
    # bash 0-based; zsh 1-based arrays
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        choice="${choices[$line]}"
    else
        choice="${choices[$((line - 1))]}"
    fi
    printf '%s\n' "${choice%%)*}"
    return 0
}

_brew_mirror_apply() {
    local mirror="$1"
    _brew_mirror_remove_legacy || true
    _brew_mirror_write_config "$mirror" || return 1
    _brew_mirror_ensure_profile || return 1
    _brew_mirror_apply_env || return 1
}

_brew_mirror_cli() {
    local choice="${1:-}"
    if [[ "$choice" == "status" ]]; then
        _brew_mirror_status
        return
    fi
    if [[ "$choice" == "-h" || "$choice" == "--help" || "$choice" == "help" ]]; then
        printf '%s\n' \
            'Usage: brew mirror [<name>|official|status]' \
            '       brew mirror          # interactive ↑↓ select (Esc/Ctrl+C cancel; Enter on * exits; * = active)'
        return
    fi
    if (( $# > 1 )); then
        printf 'Usage: brew mirror [<name>|official|status]\n' >&2
        return 1
    fi

    if [[ -z "$choice" ]]; then
        if ! choice=$(_brew_mirror_select_interactive); then
            local ec=$?
            if (( ec == 130 )); then
                printf 'Canceled\n'
            fi
            return "$ec"
        fi
        local active
        active="${USE_HOMEBREW_MIRROR:-}"
        [[ -n "$active" ]] || active=$(_brew_mirror_persisted_id)
        # Already active: skip rewrite, still refresh profile/env.
        if [[ -n "$active" && "$choice" == "$active" ]]; then
            _brew_mirror_remove_legacy || true
            _brew_mirror_ensure_profile || return 1
            _brew_mirror_apply_env || return 1
            return 0
        fi
    fi

    _brew_mirror_lookup "$choice" >/dev/null || {
        printf 'Unknown Homebrew mirror: %s\n' "$choice" >&2
        return 1
    }

    _brew_mirror_apply "$choice" || return 1
    printf 'Homebrew mirror switched to %s\n' "$choice"
    _brew_mirror_status
}

# Intercept `brew mirror`; other subcommands call the real brew binary.
brew() {
    if [[ "${1:-}" == "mirror" ]]; then
        if (( $# > 2 )); then
            printf 'Usage: brew mirror [<name>|official|status]\n' >&2
            return 1
        fi
        _brew_mirror_cli "${2:-}"
        return $?
    fi
    local brew_bin
    brew_bin=$(_brew_mirror_find_brew) || {
        printf 'brew: Homebrew not found\n' >&2
        return 127
    }
    "$brew_bin" "$@"
}

# When this helper is sourced from .zprofile before .zshrc_core, drop the legacy
# override so the functions glob cannot reload the old implementation.
_brew_mirror_remove_legacy || true
