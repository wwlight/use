param(
    [switch]$Update
)

$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

$manifest = Read-Manifest -Scope common

$UpdateMode = [bool]$Update

function Normalize-RepoUrl {
    param([string]$Url)
    $u = $Url.TrimEnd('/')
    if ($u.EndsWith('.git')) { $u = $u.Substring(0, $u.Length - 4) }
    foreach ($prefix in @('https://', 'http://', 'ssh://git@', 'git@')) {
        if ($u.StartsWith($prefix)) {
            $u = $u.Substring($prefix.Length)
            break
        }
    }
    return ($u -replace ':', '/')
}

function Test-SameRemoteRepo {
    param(
        [string]$Dir,
        [string]$ExpectedRepo
    )
    $gitDir = Join-Path $Dir '.git'
    if (-not (Test-Path $gitDir)) { return $false }
    $remote = git -C $Dir remote get-url origin 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) { return $false }
    return (Normalize-RepoUrl $remote) -eq (Normalize-RepoUrl $ExpectedRepo)
}

function Update-RepoToLatest {
    param([string]$Dir)

    git -C $Dir fetch --prune origin
    if ($LASTEXITCODE -ne 0) { return $false }

    $branch = (git -C $Dir rev-parse --abbrev-ref HEAD 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) { return $false }

    if ($branch -eq 'HEAD') {
        $originHead = (git -C $Dir symbolic-ref -q --short refs/remotes/origin/HEAD 2>$null)
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($originHead)) { return $false }
        $branch = ($originHead.Trim() -replace '^origin/', '')
        if ([string]::IsNullOrWhiteSpace($branch)) { return $false }
    }

    git -C $Dir reset --hard "origin/$branch"
    return ($LASTEXITCODE -eq 0)
}

function Install-ZshPluginClone {
    param(
        [string]$Repo,
        [string]$TargetPath,
        [string]$Name
    )

    Write-Info "正在下载插件: $Name..."
    try {
        git clone $Repo $TargetPath
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "$Name 下载失败，跳过此插件"
            return
        }
        Write-Info "$Name 下载完成"
    }
    catch {
        Write-Warn "$Name 下载失败，跳过此插件"
    }
}

function Sync-ExistingZshPlugin {
    param(
        [string]$Repo,
        [string]$TargetPath,
        [string]$Name
    )

    if (Test-SameRemoteRepo -Dir $TargetPath -ExpectedRepo $Repo) {
        Write-Info "插件 $Name 已是线上仓库，正在拉取最新..."
        if (Update-RepoToLatest -Dir $TargetPath) {
            Write-Info "$Name 已更新到最新"
        }
        else {
            Write-Warn "$Name 拉取最新失败，跳过此插件"
        }
        return
    }

    Write-Info "插件 $Name 同名但非目标仓库，正在删除并重新克隆..."
    Remove-Item $TargetPath -Recurse -Force -ErrorAction SilentlyContinue
    Install-ZshPluginClone -Repo $Repo -TargetPath $TargetPath -Name $Name
}

Write-Info '正在安装 zsh 插件...'
$pluginsDir = Get-ExpandedPath '~/.zsh/plugins'
if (-not (Test-Path $pluginsDir)) {
    New-Item -ItemType Directory -Path $pluginsDir -Force | Out-Null
}

foreach ($plugin in $manifest.zshPlugins) {
    $targetPath = Join-Path $pluginsDir $plugin.name

    if (-not (Test-Path $targetPath -PathType Container)) {
        Install-ZshPluginClone -Repo $plugin.repo -TargetPath $targetPath -Name $plugin.name
        continue
    }

    if ($UpdateMode) {
        Sync-ExistingZshPlugin -Repo $plugin.repo -TargetPath $targetPath -Name $plugin.name
    }
    else {
        Write-Info "插件 $($plugin.name) 已存在，跳过"
    }
}

$global:LASTEXITCODE = 0
