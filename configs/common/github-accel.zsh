# GitHub 加速（与 scripts/common/_manifest.json → githubAccel 保持一致）
typeset -ga GITHUB_ACCEL_MIRRORS=(
  'https://ghfast.top/'
  'https://gh-proxy.com/'
)

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

# 默认加速 → 其它加速 → 官方
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

# 用法: _git_clone_accel <repo> <target_dir>
_git_clone_accel() {
  local repo="$1" target="$2" url

  # ssh 不走 http 加速前缀
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
