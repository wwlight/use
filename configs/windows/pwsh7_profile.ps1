# PowerShell 7 profile

# Starship
Invoke-Expression (&starship init powershell)
$ENV:STARSHIP_CONFIG = "$HOME\\.config\\starship\\starship.toml"

# eza aliases
function ls { eza --icons @args }
function l { eza -l --icons @args }
function la { eza -la --icons @args }
function lt { eza --tree --icons @args }

# Vite+
if (Test-Path "$HOME/.vite-plus/env.ps1") { . "$HOME/.vite-plus/env.ps1" }
function v { vp @args }
function vc { vp create @args }
function s { vpr start @args }
function d { vpr dev @args }
function b { vpr build @args }

# Git
function gp { git push @args }
function grt { cd "$(git rev-parse --show-toplevel)" }
function gc {
  $branch = git branch | fzf
  if ($branch) { git checkout $branch.Trim() }
}

# Other
function reload { . $PROFILE }
function oc { opencode @args }

# Scoop extensions (mirror + services)
if ($env:SCOOP) {
  $__scoopExt = "$env:SCOOP\config\scoop.ps1"
  if (Test-Path -LiteralPath $__scoopExt) { . $__scoopExt }
}
