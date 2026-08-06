# GitHub acceleration (prefixes generated from manifests/common.json via generate:github-accel).
# BEGIN GENERATED GITHUB ACCEL
typeset -ga GITHUB_ACCEL_MIRRORS=(
  'https://gh-proxy.com/'
  'https://ghfast.top/'
)
# END GENERATED GITHUB ACCEL

_github_accel_strip() {
  local url="$1" p
  for p in "${GITHUB_ACCEL_MIRRORS[@]}"; do
    [[ "$url" == "$p"* ]] && { print -r -- "${url#$p}"; return 0 }
  done
  print -r -- "$url"
}

_github_accel_needed() {
  local bare
  bare=$(_github_accel_strip "$1")
  [[ "$bare" == https://github.com/* || "$bare" == https://raw.githubusercontent.com/* ]]
}

# Default mirror, other mirrors, then upstream.
_github_accel_candidates() {
  local url="$1" bare p candidate
  bare=$(_github_accel_strip "$url")
  if ! _github_accel_needed "$bare"; then
    print -r -- "$url"
    return 0
  fi
  for p in "${GITHUB_ACCEL_MIRRORS[@]}"; do
    print -r -- "${p}${bare}"
  done
  print -r -- "$bare"
}

# Usage: _git_clone_accel <repo> <target_dir>
_git_clone_accel() {
  local repo="$1" target="$2" url

  # SSH URLs do not use HTTP acceleration prefixes.
  if [[ "$repo" == git@* || "$repo" == ssh://* ]]; then
    git clone "$repo" "$target"
    return $?
  fi

  if ! _github_accel_needed "$repo"; then
    git clone "$repo" "$target"
    return $?
  fi

  while IFS= read -r url; do
    [[ -n "$url" ]] || continue
    [[ -d "$target" ]] && rm -rf "$target"
    if git clone "$url" "$target"; then
      return 0
    fi
  done < <(_github_accel_candidates "$repo")
  return 1
}
