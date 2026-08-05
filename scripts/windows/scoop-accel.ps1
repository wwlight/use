# Apply Scoop mirror + aria2 acceleration. Requires utils.ps1 already loaded.

function Get-ScoopAccelConfig {
    param($Manifest)
    if (-not $Manifest) { $Manifest = Read-Manifest }
    $accel = $Manifest.scoopAccel
    if (-not $accel) {
        Write-ErrorAndExit 'windows manifest 缺少 scoopAccel'
    }
    return $accel
}

function Get-ScoopMirrorPrefixes {
    param($Accel)

    $list = New-Object System.Collections.Generic.List[string]
    foreach ($p in @(Get-GithubAccelPrefixes)) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (-not $list.Contains($p)) { [void]$list.Add($p) }
    }

    if ($list.Count -eq 0) {
        Write-ErrorAndExit 'common githubAccel.mirrors 为空，请至少配置一个加速镜像'
    }
    return $list
}

function Get-ScoopMirrorSelectionMap {
    param($Accel)

    $map = Get-GithubAccelSelectionMap
    if ($map.Count -le 1) {
        # 仅有 official 说明 mirrors 为空
        Write-ErrorAndExit 'common githubAccel.mirrors 为空，请至少配置一个加速镜像'
    }
    return $map
}

function Get-ScoopMirrorChoiceId {
    param([string]$Prefix)
    if ([string]::IsNullOrWhiteSpace($Prefix)) { return 'official' }
    foreach ($item in @(Get-GithubAccelMirrors)) {
        if ($item.prefix -eq $Prefix) { return $item.id }
        if ($item.prefix.TrimEnd('/') -eq $Prefix.TrimEnd('/')) { return $item.id }
    }
    try {
        $hostName = ([Uri]$Prefix).Host
        if (-not [string]::IsNullOrWhiteSpace($hostName)) { return $hostName }
    }
    catch { }
    return (($Prefix -replace '^https?://', '') -replace '/$', '')
}

function Show-ScoopMirrorUsage {
    param($Accel)
    $map = Get-ScoopMirrorSelectionMap -Accel $Accel
    $keys = @($map.Keys)
    Write-Host "用法: vpr pm [$($keys -join '|')]"
    Write-Host ''
    foreach ($k in $keys) {
        $label = if ($k -eq 'official') { '官方源' } else { $map[$k] }
        Write-Host ("  {0,-12}  {1}" -f $k, $label)
    }
    Write-Host ''
    Write-Host '示例:'
    Write-Host '  vpr pm'
    Write-Host '  vpr pm -- ghfast'
    Write-Host '  vpr pm -- ghproxy'
    Write-Host '  vpr pm -- official'
}

function Strip-ScoopMirrorPrefix {
    param(
        [string]$Url,
        $Prefixes
    )
    foreach ($p in @($Prefixes)) {
        $prefix = [string]$p
        if ([string]::IsNullOrWhiteSpace($prefix)) { continue }
        if ($Url.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            return $Url.Substring($prefix.Length)
        }
    }
    return $Url
}

function Join-ScoopMirrorUrl {
    param(
        [string]$Url,
        [string]$Prefix,
        $AllPrefixes
    )
    if ([string]::IsNullOrWhiteSpace($Url)) { return $Url }
    if (-not $AllPrefixes) { $AllPrefixes = @() }
    $bare = Strip-ScoopMirrorPrefix -Url $Url -Prefixes $AllPrefixes
    if ([string]::IsNullOrWhiteSpace($Prefix)) { return $bare }
    if (-not $Prefix.EndsWith('/')) { $Prefix += '/' }
    return ($Prefix + $bare)
}

function Get-ScoopMirrorUrlCandidates {
    param(
        [string]$Url,
        $Prefixes
    )
    $bare = Strip-ScoopMirrorPrefix -Url $Url -Prefixes $Prefixes
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($p in @($Prefixes)) {
        $prefix = [string]$p
        if ([string]::IsNullOrWhiteSpace($prefix)) { continue }
        $candidate = $prefix + $bare
        if (-not $list.Contains($candidate)) { [void]$list.Add($candidate) }
    }
    if (-not $list.Contains($bare)) { [void]$list.Add($bare) }
    return $list
}

function Test-ScoopUrlReachable {
    param(
        [string]$Url,
        [int]$TimeoutSec = 3
    )
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }

    foreach ($method in @('Head', 'Get')) {
        try {
            $res = Invoke-WebRequest -Uri $Url -Method $method -TimeoutSec $TimeoutSec -UseBasicParsing -ErrorAction Stop
            if ([int]$res.StatusCode -ge 200 -and [int]$res.StatusCode -lt 400) {
                return $true
            }
        }
        catch {
            continue
        }
    }
    return $false
}

function Invoke-NodeMenuSelect {
    param(
        [string]$Title,
        [string[]]$Items
    )

    $menuScript = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\lib\menu-select.mjs'))
    if (-not (Test-Path $menuScript)) {
        Write-ErrorAndExit "找不到菜单脚本: $menuScript"
    }
    $outFile = [System.IO.Path]::GetTempFileName()
    try {
        $env:MENU_SELECT_OUT = $outFile
        $menuArgs = @($Title) + @($Items | Where-Object { $_ })
        & node $menuScript @menuArgs
        if ($LASTEXITCODE -ne 0) { return '' }
        $choice = (Get-Content -LiteralPath $outFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
        return "$choice".Trim()
    }
    finally {
        Remove-Item Env:MENU_SELECT_OUT -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-ScoopMirrorSelection {
    param(
        $Accel,
        [string]$Choice = ''
    )

    $map = Get-ScoopMirrorSelectionMap -Accel $Accel
    if ($Choice -match '^--(.+)$') { $Choice = $Matches[1] }
    $Choice = "$Choice".Trim()

    if ($Choice -ne '') {
        if ($map.Contains($Choice)) { return $map[$Choice] }
        foreach ($k in @($map.Keys)) {
            $prefix = $map[$k]
            if ($prefix -eq $Choice) { return $prefix }
            if ($prefix -and ($prefix.TrimEnd('/') -eq $Choice.TrimEnd('/'))) { return $prefix }
        }
        Show-ScoopMirrorUsage -Accel $Accel
        Write-ErrorAndExit "未知加速镜像: $Choice"
    }

    if (-not (Test-InteractivePrompt)) {
        Show-ScoopMirrorUsage -Accel $Accel
        Write-ErrorAndExit '非交互环境请传入参数（示例: vpr pm -- official）'
    }

    $menuItems = New-Object System.Collections.Generic.List[string]
    foreach ($k in @($map.Keys)) {
        if ($k -eq 'official') {
            [void]$menuItems.Add("${k}) 官方源")
        }
        else {
            [void]$menuItems.Add("${k}) $($map[$k])")
        }
    }

    $selected = Invoke-NodeMenuSelect -Title '请选择 Scoop 加速镜像' -Items @($menuItems)
    if ([string]::IsNullOrWhiteSpace($selected) -or -not $map.Contains($selected)) {
        Show-ScoopMirrorUsage -Accel $Accel
        Write-ErrorAndExit '非交互环境请传入参数（示例: vpr pm -- official）'
    }
    return $map[$selected]
}

function Format-ScoopMirrorActiveLabel {
    param([string]$ActivePrefix)
    if ([string]::IsNullOrWhiteSpace($ActivePrefix)) { return '官方源' }
    return $ActivePrefix
}

function Get-ScoopMirrorLabelFromUrl {
    param(
        [string]$Url,
        $Prefixes
    )
    foreach ($p in @($Prefixes)) {
        $prefix = [string]$p
        if ([string]::IsNullOrWhiteSpace($prefix)) { continue }
        if ($Url.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $prefix }
    }
    return '官方源'
}

function Invoke-ScoopInstallScriptWithFallback {
    param(
        $Accel,
        [string]$PreferredPrefix = $null
    )

    # 引导安装脚本只从官方地址执行，避免第三方加速站篡改后被 iex。
    # PreferredPrefix 仅用于安装完成后的下载/仓库加速，不用于执行远程脚本。
    $null = $PreferredPrefix
    $url = [string]$Accel.installScript
    if ([string]::IsNullOrWhiteSpace($url)) {
        Write-ErrorAndExit 'scoopAccel.installScript 为空'
    }

    Write-Info "尝试安装脚本（官方源）: $url"
    Write-Info '镜像加速将在 scoop 安装完成后生效；若官方源不可达可先运行 vpr hosts'
    try {
        if (Test-Administrator) {
            iex "& {$(irm $url)} -RunAsAdmin"
        }
        else {
            Invoke-RestMethod -Uri $url | Invoke-Expression
        }
        Write-Info '安装脚本成功（官方源）'
        return
    }
    catch {
        Write-ErrorAndExit "scoop 安装失败（官方安装脚本）: $($_.Exception.Message)"
    }
}

function Get-ScoopLibDownloadPath {
    $scoopRoot = if ($env:SCOOP) { $env:SCOOP } else { (Read-Manifest).scoopDir }
    $download = Join-Path $scoopRoot 'apps\scoop\current\lib\download.ps1'
    if (-not (Test-Path $download)) {
        Write-ErrorAndExit "找不到 Scoop download.ps1: $download"
    }
    return $download
}

function ConvertTo-MirrorUrl {
    param(
        [string]$Url,
        [string]$Prefix,
        [string[]]$AllPrefixes
    )
    if ([string]::IsNullOrWhiteSpace($Url)) { return $Url }
    if (-not $AllPrefixes) { $AllPrefixes = @() }
    $bare = Strip-ScoopMirrorPrefix -Url $Url.Trim() -Prefixes $AllPrefixes
    if ($bare -match '^https://github\.com/' -or $bare -match '^https://raw\.githubusercontent\.com/') {
        return (Join-ScoopMirrorUrl -Url $bare -Prefix $Prefix -AllPrefixes $AllPrefixes)
    }
    return $bare
}

function Write-Utf8NoBomFile {
    param(
        [string]$Path,
        [string]$Content
    )
    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

# Windows PowerShell 5.1 defaults to system ANSI without BOM; use BOM for .ps1.
function Write-Utf8BomFile {
    param(
        [string]$Path,
        [string]$Content
    )
    $encoding = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Install-ScoopMirrorAccelScript {
    param($Manifest)

    if (-not $Manifest) { $Manifest = Read-Manifest }
    $scoopRoot = $env:SCOOP
    if (-not $scoopRoot) { $scoopRoot = $Manifest.scoopDir }
    if (-not $scoopRoot) { Write-ErrorAndExit 'SCOOP 环境变量未设置，且 windows manifest 缺少 scoopDir' }

    $configDir = Join-Path $scoopRoot 'config'
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $src = Join-Path $PSScriptRoot 'mirror-accel.ps1'
    if (-not (Test-Path $src)) {
        Write-ErrorAndExit "找不到 mirror-accel.ps1: $src"
    }
    $dest = Join-Path $configDir 'mirror-accel.ps1'
    $ps1Content = Get-Content -LiteralPath $src -Raw -Encoding UTF8
    if ($null -eq $ps1Content) { $ps1Content = '' }
    Write-Utf8BomFile -Path $dest -Content $ps1Content
    Write-Info "已同步 mirror-accel 到 $dest"
}

function Install-ScoopMirrorAccelFiles {
    param(
        $Accel,
        [string]$ActivePrefix,
        $Prefixes
    )

    $scoopRoot = $env:SCOOP
    if (-not $scoopRoot) { Write-ErrorAndExit 'SCOOP 环境变量未设置' }

    $configDir = Join-Path $scoopRoot 'config'
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    if (-not $Prefixes) { $Prefixes = Get-ScoopMirrorPrefixes -Accel $Accel }

    $jsonPath = Join-Path $configDir 'mirror-accel.json'
    $payload = [ordered]@{
        mirrorPrefix = @($Prefixes)
        activePrefix = $ActivePrefix
        githubHosts  = @($Accel.githubHosts)
    }
    Write-Utf8NoBomFile -Path $jsonPath -Content (($payload | ConvertTo-Json -Depth 5) + "`n")

    Install-ScoopMirrorAccelScript
}

function Install-ScoopDownloadHook {
    $downloadPath = Get-ScoopLibDownloadPath
    $markerBegin = '# >>> scoop-mirror-accel'
    $markerEnd = '# <<< scoop-mirror-accel'
    $hookLines = @(
        $markerBegin
        '. "$env:SCOOP\config\mirror-accel.ps1"'
        $markerEnd
    )
    $hook = ($hookLines -join "`n")

    $content = Get-Content $downloadPath -Raw -Encoding UTF8
    if ($null -eq $content) { $content = '' }

    $hadHook = $content.Contains($markerBegin)
    $beginIdx = $content.IndexOf($markerBegin)
    if ($beginIdx -ge 0) {
        $endIdx = $content.IndexOf($markerEnd, $beginIdx)
        if ($endIdx -lt 0) {
            Write-ErrorAndExit "download.ps1 加速标记不完整: $downloadPath"
        }
        $endIdx += $markerEnd.Length
        $content = $content.Substring(0, $beginIdx).TrimEnd() + "`n`n" + $hook + "`n" + $content.Substring($endIdx).TrimStart()
    }
    else {
        if (-not $content.EndsWith("`n")) { $content += "`n" }
        $content += "`n$hook`n"
    }
    Write-Utf8NoBomFile -Path $downloadPath -Content $content
    if ($hadHook) {
        Write-Info '已刷新 download.ps1 加速挂钩'
    }
    else {
        Write-Info '已写入 download.ps1 加速挂钩（scoop update 后由 profile 自动恢复）'
    }
}

function Set-ScoopBucketMirrors {
    param(
        $Accel,
        [string]$ActivePrefix,
        $Prefixes
    )

    if (-not $Prefixes) { $Prefixes = Get-ScoopMirrorPrefixes -Accel $Accel }
    $bucketsRoot = Join-Path $env:SCOOP 'buckets'
    if (-not (Test-Path $bucketsRoot)) { return }

    Get-ChildItem $bucketsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $gitDir = Join-Path $_.FullName '.git'
        if (-not (Test-Path $gitDir)) { return }
        $origin = git -C $_.FullName remote get-url origin 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($origin)) { return }
        $mirrored = ConvertTo-MirrorUrl -Url $origin.Trim() -Prefix $ActivePrefix -AllPrefixes $Prefixes
        if ($mirrored -ne $origin.Trim()) {
            git -C $_.FullName remote set-url origin $mirrored 2>$null | Out-Null
        }
    }
}

function Install-ScoopAria2Accel {
    param($Accel)

    $aria = $Accel.aria2
    if (-not $aria) { return }

    if (-not (Get-Command aria2c -ErrorAction SilentlyContinue)) {
        Write-Info '正在安装 aria2...'
        scoop install aria2
        if ($LASTEXITCODE -ne 0) {
            Write-Warn 'aria2 安装失败；可稍后重试。若镜像站不支持分片，可执行: scoop config aria2-enabled false'
            return
        }
    }

    Write-Info '正在配置 aria2 多线程下载...'
    scoop config aria2-enabled $(if ($aria.enabled) { 'true' } else { 'false' })
    scoop config aria2-warning-enabled $(if ($aria.warningEnabled) { 'true' } else { 'false' })
    if ($null -ne $aria.retryWait) { scoop config aria2-retry-wait $aria.retryWait }
    if ($null -ne $aria.split) { scoop config aria2-split $aria.split }
    if ($null -ne $aria.maxConnectionPerServer) { scoop config aria2-max-connection-per-server $aria.maxConnectionPerServer }
    if ($null -ne $aria.minSplitSize) { scoop config aria2-min-split-size $aria.minSplitSize }
    Write-Info 'aria2 配置完成'
}

function Enable-ScoopAccel {
    param(
        $Manifest,
        [string]$Mirror = '',
        $ActivePrefix,
        [switch]$SkipAria2
    )

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit 'scoop 未安装，无法应用加速配置'
    }

    if (-not $env:SCOOP) {
        $env:SCOOP = (Read-Manifest).scoopDir
    }

    $accel = Get-ScoopAccelConfig -Manifest $Manifest
    $prefixes = Get-ScoopMirrorPrefixes -Accel $accel

    if (-not $PSBoundParameters.ContainsKey('ActivePrefix')) {
        $ActivePrefix = Resolve-ScoopMirrorSelection -Accel $accel -Choice $Mirror
    }
    $ActivePrefix = [string]$ActivePrefix

    $activeLabel = Format-ScoopMirrorActiveLabel -ActivePrefix $ActivePrefix
    Write-Info "正在应用 Scoop 加速，当前加速代理: $activeLabel"

    if (-not [string]::IsNullOrWhiteSpace($ActivePrefix)) {
        $probeTarget = [string]$accel.installScript
        if ([string]::IsNullOrWhiteSpace($probeTarget)) { $probeTarget = [string]$accel.scoopRepo }
        $probeUrl = Join-ScoopMirrorUrl -Url $probeTarget -Prefix $ActivePrefix -AllPrefixes $prefixes
        if (-not (Test-ScoopUrlReachable -Url $probeUrl)) {
            Write-Warn "所选加速站当前探测未通过，仍将写入配置；下载失败时会自动回退其他源"
        }
    }

    if ([string]::IsNullOrWhiteSpace($ActivePrefix)) {
        scoop config scoop_repo ([string]$accel.scoopRepo)
    }
    else {
        $scoopRepo = Join-ScoopMirrorUrl -Url ([string]$accel.scoopRepo) -Prefix $ActivePrefix -AllPrefixes $prefixes
        scoop config scoop_repo $scoopRepo
    }

    Install-ScoopMirrorAccelFiles -Accel $accel -ActivePrefix $ActivePrefix -Prefixes $prefixes
    Install-ScoopDownloadHook
    Set-ScoopBucketMirrors -Accel $accel -ActivePrefix $ActivePrefix -Prefixes $prefixes

    if (-not $SkipAria2) {
        Install-ScoopAria2Accel -Accel $accel
    }

    Write-Info "Scoop 加速配置完成（加速代理: $activeLabel）"
}
