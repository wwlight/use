param([string]$Direction)

$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

$manifest = Read-Manifest
$direction = Get-SyncDirection $Direction `
    '示例: npm run win:sync -- 2 或 vpr win:sync 2' `
    '1) 从本地目录拷贝到 windows 目录' `
    '2) 从 windows 目录拷贝到本地目录'

switch ($direction) {
    '1' {
        foreach ($item in $manifest.sync.toRepo) {
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
        Backup-File '~/.zshrc' '~/.backup'
        foreach ($item in $manifest.sync.toRepo) {
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
