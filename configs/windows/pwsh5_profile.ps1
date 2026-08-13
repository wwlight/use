# PowerShell 5 profile

# Starship
Invoke-Expression (&starship init powershell)
$ENV:STARSHIP_CONFIG = "$HOME\\.config\\starship\\starship.toml"

# Vite+ env
if (Test-Path "$HOME/.vite-plus/env.ps1") {
    . "$HOME/.vite-plus/env.ps1"
}

# Scoop extensions (mirror + services) — ~/.config/scoop/scoop.ps1
$__scoopCfg = if ($env:XDG_CONFIG_HOME) {
    Join-Path $env:XDG_CONFIG_HOME 'scoop'
} else {
    Join-Path $env:USERPROFILE '.config\scoop'
}
$__scoopExt = Join-Path $__scoopCfg 'scoop.ps1'
if (Test-Path -LiteralPath $__scoopExt) {
    . $__scoopExt
}

# Aliases (shared with pwsh 7) — ~/.config/pwsh/aliases.ps1
$__pwshCfg = if ($env:XDG_CONFIG_HOME) {
    Join-Path $env:XDG_CONFIG_HOME 'pwsh'
} else {
    Join-Path $env:USERPROFILE '.config\pwsh'
}
$__pwshAliases = Join-Path $__pwshCfg 'aliases.ps1'
if (Test-Path -LiteralPath $__pwshAliases) {
    . $__pwshAliases
}
Remove-Variable __pwshCfg, __pwshAliases -ErrorAction SilentlyContinue
