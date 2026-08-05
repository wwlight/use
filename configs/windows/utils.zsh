function cdl() {
    local dir
    dir="$(zoxide query -l | fzf --reverse --height 40% \
        --preview 'eza -l --icons {}' \
        --preview-window=right:60%)" && cd "${dir}"
}

function cdd() {
    local dir
    dir="$(find . -type d 2>/dev/null | fzf --reverse --height 40% \
        --preview 'eza -l --icons {}' \
        --preview-window=right:60%)" && cd "${dir}"
}

function _win_drive() {
    [[ -d "/e" || -d "/e/" || -d "E:" || -d "E:/" ]] && { echo "E:"; return 0 }
    [[ -d "/d" || -d "/d/" || -d "D:" || -d "D:/" ]] && { echo "D:"; return 0 }
    echo "Error: E: or D: drive not found" >&2
    return 1
}

function _clone() {
    local repo=$1 custom_dir=$2 base_dir=$3 default_user=$4

    if [[ "$repo" == git@* ]]; then
        local repo_name=$(basename "${repo#*:}" .git)
    elif [[ "$repo" == http* ]]; then
        local repo_name=$(basename "$repo" .git)
    else
        repo="https://github.com/${default_user:+$default_user/}${repo%.git}.git"
        local repo_name=$(basename "$repo" .git)
    fi

    [[ -n "$custom_dir" ]] && repo_name="$custom_dir"

    local target_dir="$base_dir/$repo_name" counter=1
    while [[ -d "$target_dir" ]]; do
        target_dir="$base_dir/${repo_name}_$((counter++))"
    done

    [[ $counter -gt 1 ]] && echo "Note: the original directory exists; cloning to: $target_dir"

    mkdir -p "$base_dir" || { echo "Could not create directory: $base_dir"; return 1; }

    echo "Cloning to: $target_dir"
    if _git_clone_accel "$repo" "$target_dir"; then
        echo "✅ Cloned to: $target_dir"
    else
        echo "Failed to clone repository: $repo"
        if [[ -d "$target_dir" ]]; then
            echo "Removing incomplete clone directory: $target_dir"
            rm -rf "$target_dir" && echo "Removed" || echo "Removal failed; check manually: $target_dir"
        fi
        return 1
    fi
}

function cloneo() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: cloneo <repository-url> [custom-directory]"; return 1
    fi
    local root
    root=$(_win_drive) || return 1
    _clone "$1" "$2" "${root}/open-source" ""
}

function cloned() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: cloned <repository-url> [custom-directory]"; return 1
    fi
    local root
    root=$(_win_drive) || return 1
    _clone "$1" "$2" "${root}/dev-code" "wwlight"
}

# Clean history: remove duplicates and invalid or trivial commands.
function history_clean() {
    local tmp=$(mktemp)

    grep -v $'\ufffd' $HISTFILE | awk '
    function is_bad(cmd) {
        if (length(cmd) <= 1) return 1
        if (cmd ~ /^(cat|node|python|python3|bash|cargo|rustc|uv|clear)$/) return 1
        if (cmd ~ /^(corepack|yarn|pnpm|fnm|ni|nr)([ \t].*)?$/) return 1
        if (cmd ~ /^history [0-9]+$/) return 1
        if (cmd ~ /^cd [0-9]+\/?$/) return 1
        if (cmd ~ /^git commit -(m|a) ["'\''\x60][0-9]+["'\''\x60]$/) return 1
        if (cmd ~ /^git commit -m \${\w+}$/) return 1
        return 0
    }
    { lines[++n] = $0 }
    END {
        for (i = n; i >= 1; i--) {
            cmd = lines[i]
            sub(/^: [0-9]+:[0-9]+;/, "", cmd)
            if (is_bad(cmd)) continue
            if (!seen[cmd]++) result[++count] = lines[i]
        }
        for (i = count; i > 0; i--) print result[i]
    }' > $tmp

    if [ -s "$tmp" ]; then
        mv $tmp $HISTFILE
        echo "History cleaned: deduped, removed trivial/wrong commands"
    else
        echo "Error: output empty, history not modified"
        rm $tmp
    fi
}
