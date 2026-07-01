param([string]$Direction)

$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

$direction = Get-SyncDirection $Direction `
    '示例: npm run common:sync -- 2 或 vpr common:sync 2' `
    '1) 从本地目录拷贝到 common 目录' `
    '2) 从 common 目录拷贝到本地目录'

$syncItems = @(
    @{ local = '~/.zsh/zfunc/_eza'; repo = 'configs/common/_eza' },
    @{ local = '~/.config/starship/starship.toml'; repo = 'configs/common/starship.toml' }
)

switch ($direction) {
    '1' {
        foreach ($item in $syncItems) {
            $local = Get-ExpandedPath $item.local
            $repo = Join-Path $Script:ProjectRoot $item.repo
            $repoDir = Split-Path $repo -Parent
            if (-not (Test-Path $repoDir)) {
                New-Item -ItemType Directory -Path $repoDir -Force | Out-Null
            }
            Copy-Item $local $repo -Force -Verbose
        }
    }
    '2' {
        foreach ($item in $syncItems) {
            $local = Get-ExpandedPath $item.local
            $repo = Join-Path $Script:ProjectRoot $item.repo
            $localDir = Split-Path $local -Parent
            if (-not (Test-Path $localDir)) {
                New-Item -ItemType Directory -Path $localDir -Force | Out-Null
            }
            Copy-Item $repo $local -Force -Verbose
        }
    }
    default {
        Write-Host '无效选择'
        exit 1
    }
}

Write-Host '操作完成！'
