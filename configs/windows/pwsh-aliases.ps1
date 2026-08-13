# Shared PowerShell aliases (pwsh 5 + pwsh 7) — mirrors configs/common/aliases.zsh

# System aliases (Get-ItemProperty/Get-Location/Get-Content/Get-ChildItem) shadow the
# same-named functions below. Remove only the built-in ones; keep any user override.
$__sysAliases = @{
    gp = 'Get-ItemProperty'
    gl = 'Get-Location'
    gc = 'Get-Content'
    ls = 'Get-ChildItem'
}
foreach ($__name in $__sysAliases.Keys) {
    $__a = Get-Alias $__name -ErrorAction SilentlyContinue
    if ($__a -and $__a.Definition -eq $__sysAliases[$__name]) {
        Remove-Item "Alias:$__name" -Force
    }
}
Remove-Variable __sysAliases, __name, __a -ErrorAction SilentlyContinue

# eza
function ls { eza --icons @args }
function l { eza -l --icons @args }
function la { eza -la --icons @args }
function lt { eza --tree --icons @args }

# Vite+
function v { vp @args }
function vc { vp create @args }
function s { vpr start @args }
function d { vpr dev @args }
function b { vpr build @args }

# Git
function gp { git push @args }
function gl { git pull @args }
function grt { cd "$(git rev-parse --show-toplevel)" }
function gc {
    $branch = git branch | fzf
    if ($branch) { git checkout $branch.Trim() }
}

# Other
function reload { . $PROFILE }
function of { onefetch @args }
function oc { opencode @args }
function t { tldr @args }
