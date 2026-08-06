# Homebrew mirror switcher. Loaded from ~/.zsh/functions/brew-mirror.zsh.

_brew_mirror_config_file() {
    printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/homebrew/mirror.zsh"
}

_brew_mirror_ensure_profile() {
    local profile="${HOME}/.zprofile"
    local begin='# >>> use-homebrew'
    local end='# <<< use-homebrew'
    local source_line='[[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/homebrew/mirror.zsh" ]] && . "${XDG_CONFIG_HOME:-$HOME/.config}/homebrew/mirror.zsh"'
    local brew_path
    brew_path=$(command -v brew 2>/dev/null) || brew_path=''
    local tmp
    tmp=$(mktemp "${TMPDIR:-/tmp}/use-zprofile.XXXXXX") || return 1

    if [[ -f "$profile" ]]; then
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
        printf '%s\n%s\n' "$source_line" "$end"
    } >> "$tmp"
    mv "$tmp" "$profile"
}

_brew_mirror_write_config() {
    local mirror="$1"
    local config
    config=$(_brew_mirror_config_file) || return 1
    mkdir -p "${config%/*}" || return 1

    local tmp
    tmp=$(mktemp "${config}.XXXXXX") || return 1
    {
        printf '# Managed by brew-mirror. Do not edit.\n'
        printf 'export USE_HOMEBREW_MIRROR=%q\n' "$mirror"
        case "$mirror" in
            ustc)
                printf '%s\n' \
                    'export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"' \
                    'export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"' \
                    'export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"'
                ;;
            tuna)
                printf '%s\n' \
                    'export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"' \
                    'export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"' \
                    'export HOMEBREW_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"'
                ;;
            official)
                printf '%s\n' \
                    'unset HOMEBREW_BREW_GIT_REMOTE' \
                    'unset HOMEBREW_BOTTLE_DOMAIN' \
                    'unset HOMEBREW_API_DOMAIN'
                ;;
            *)
                rm -f "$tmp"
                printf 'Unknown Homebrew mirror: %s\n' "$mirror" >&2
                return 1
                ;;
        esac
    } > "$tmp"
    mv "$tmp" "$config"
}

_brew_mirror_status() {
    printf 'Active Homebrew mirror: %s\n' "${USE_HOMEBREW_MIRROR:-official}"
    printf '  API:    %s\n' "${HOMEBREW_API_DOMAIN:-https://formulae.brew.sh/api}"
    printf '  Bottle: %s\n' "${HOMEBREW_BOTTLE_DOMAIN:-https://ghcr.io/v2/homebrew/core}"
    printf '  Brew:   %s\n' "${HOMEBREW_BREW_GIT_REMOTE:-https://github.com/Homebrew/brew}"
}

brew-mirror() {
    local choice="${1:-}"
    if [[ "$choice" == "status" ]]; then
        _brew_mirror_status
        return
    fi
    if [[ "$choice" == "-h" || "$choice" == "--help" || "$choice" == "help" ]]; then
        printf '%s\n' \
            'Usage: brew-mirror [ustc|tuna|official|status]' \
            '       brew-mirror          # interactive selection'
        return
    fi
    if (( $# > 1 )); then
        printf 'Usage: brew-mirror [ustc|tuna|official|status]\n' >&2
        return 1
    fi

    if [[ -z "$choice" ]]; then
        if [[ ! -t 0 || ! -t 1 ]]; then
            printf 'brew-mirror: interactive selection requires a terminal\n' >&2
            return 1
        fi
        if ! command -v fzf >/dev/null 2>&1; then
            printf 'brew-mirror: fzf is required for interactive selection\n' >&2
            return 1
        fi
        local selected
        selected=$(printf '%s\n' \
            $'ustc\t中科大镜像' \
            $'tuna\t清华镜像' \
            $'official\t官方源' |
            fzf --height=40% --reverse --border --prompt='Homebrew mirror > ') || return 130
        choice="${selected%%$'\t'*}"
    fi

    case "$choice" in
        ustc|tuna|official) ;;
        *)
            printf 'Unknown Homebrew mirror: %s\n' "$choice" >&2
            return 1
            ;;
    esac

    _brew_mirror_write_config "$choice" || return 1
    _brew_mirror_ensure_profile || return 1
    . "$(_brew_mirror_config_file)" || return 1
    printf 'Homebrew mirror switched to %s\n' "$choice"
    _brew_mirror_status
}
