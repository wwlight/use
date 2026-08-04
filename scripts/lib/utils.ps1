$Script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

# --- 平台特有（Windows） ---
function Test-Administrator {
    try {
        $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        if ($null -eq $currentIdentity) { return $false }
        $principal = [Security.Principal.WindowsPrincipal]::new($currentIdentity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Test-InteractivePrompt {
    if ($env:SYNC_INTERACTIVE -eq '1') {
        return $true
    }

    if (-not [Environment]::UserInteractive) {
        return $false
    }

    try {
        if (-not [Console]::IsInputRedirected) {
            return $true
        }
    }
    catch {
        return $false
    }

    # 不在此打开 CONIN$：在 node/zsh 调度、stdin 重定向时可能长时间阻塞。
    # 需要交互时由上层设置 SYNC_INTERACTIVE=1。
    return $false
}

# 规范化 git remote，便于比较是否同一仓库
function Normalize-RepoUrl {
    param([string]$Url)
    $u = Strip-GithubAccelPrefix -Url $Url
    while ($u.EndsWith('/')) { $u = $u.TrimEnd('/') }
    if ($u.EndsWith('.git')) { $u = $u.Substring(0, $u.Length - 4) }
    foreach ($prefix in @('https://', 'http://', 'ssh://git@', 'git@')) {
        if ($u.StartsWith($prefix)) {
            $u = $u.Substring($prefix.Length)
            break
        }
    }
    return ($u -replace ':', '/')
}

function Get-GithubAccelMirrors {
    if ($null -ne $script:GithubAccelMirrors) {
        return $script:GithubAccelMirrors
    }

    $cfg = (Read-Manifest -Scope common).githubAccel
    if (-not $cfg) {
        Write-ErrorAndExit 'common manifest 缺少 githubAccel'
    }

    $mirrors = @()
    foreach ($item in @($cfg.mirrors)) {
        if ($null -eq $item) { continue }
        $id = [string]$item.id
        $p = [string]$item.prefix
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($p)) { continue }
        if (-not $p.EndsWith('/')) { $p += '/' }
        $mirrors += [pscustomobject]@{ id = $id; prefix = $p }
    }

    if ($mirrors.Count -eq 0) {
        Write-ErrorAndExit 'common githubAccel.mirrors 为空，请至少配置一个加速镜像'
    }

    $script:GithubAccelMirrors = $mirrors
    return $script:GithubAccelMirrors
}

function Get-GithubAccelPrefixes {
    if ($null -ne $script:GithubAccelPrefixes) {
        return $script:GithubAccelPrefixes
    }

    $prefixes = @(
        foreach ($item in (Get-GithubAccelMirrors)) {
            [string]$item.prefix
        }
    )
    $script:GithubAccelPrefixes = $prefixes
    return $script:GithubAccelPrefixes
}

function Get-GithubAccelSelectionMap {
    $map = [ordered]@{}
    foreach ($item in (Get-GithubAccelMirrors)) {
        $id = [string]$item.id
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        if (-not $map.Contains($id)) { $map[$id] = [string]$item.prefix }
    }
    $map['official'] = ''
    return $map
}

function Get-GithubAccelDefaultPrefix {
    if ($null -ne $script:GithubAccelDefaultPrefix) {
        return $script:GithubAccelDefaultPrefix
    }

    $cfg = (Read-Manifest -Scope common).githubAccel
    $defaultId = [string]$cfg.default
    $prefix = ''
    foreach ($item in (Get-GithubAccelMirrors)) {
        if ($defaultId -and ([string]$item.id -eq $defaultId)) {
            $prefix = [string]$item.prefix
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($prefix)) {
        $prefix = [string](Get-GithubAccelMirrors)[0].prefix
    }

    $script:GithubAccelDefaultPrefix = $prefix
    return $script:GithubAccelDefaultPrefix
}

function Strip-GithubAccelPrefix {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $Url }
    foreach ($p in @(Get-GithubAccelPrefixes)) {
        if ($p -and $Url.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) {
            return $Url.Substring($p.Length)
        }
    }
    return $Url
}

function Test-GithubHttpUrl {
    param([string]$Url)
    $bare = Strip-GithubAccelPrefix -Url $Url
    return $bare -match '^https://(github\.com|raw\.githubusercontent\.com)/'
}

function ConvertTo-GithubAccelUrl {
    param([string]$Url)
    if (-not (Test-GithubHttpUrl -Url $Url)) { return $Url }
    $bare = Strip-GithubAccelPrefix -Url $Url
    $prefix = Get-GithubAccelDefaultPrefix
    if ([string]::IsNullOrWhiteSpace($prefix)) { return $bare }
    return ($prefix + $bare)
}

function Get-GithubAccelUrlCandidates {
    param([string]$Url)
    if (-not (Test-GithubHttpUrl -Url $Url)) {
        return @($Url)
    }

    $bare = Strip-GithubAccelPrefix -Url $Url
    $candidates = @()
    $default = Get-GithubAccelDefaultPrefix
    if ($default) { $candidates += ($default + $bare) }
    foreach ($p in (Get-GithubAccelPrefixes)) {
        if (-not $p) { continue }
        $candidate = $p + $bare
        if ($candidates -notcontains $candidate) { $candidates += $candidate }
    }
    if ($candidates -notcontains $bare) { $candidates += $bare }
    return $candidates
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

# --- 打印方法 ---
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Write-Step {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

# 全局步骤计数（跨子进程，专用前缀避免脏环境干扰）
#   USE_STEP_CHAIN=1  由 install 入口设置，表示续接父进度
#   USE_STEP_TOTAL    总步数
#   USE_STEP_CURRENT  当前已完成步数
function Test-UseStepUInt {
    param([string]$Value)
    return ($Value -match '^\d+$')
}

# 用法: Write-NextStep '正在创建目录结构...'
function Write-NextStep {
    param([string]$Message)

    $current = 0
    if (Test-UseStepUInt $env:USE_STEP_CURRENT) { $current = [int]$env:USE_STEP_CURRENT }
    $current++
    $env:USE_STEP_CURRENT = "$current"

    $total = 0
    if ((Test-UseStepUInt $env:USE_STEP_TOTAL) -and ([int]$env:USE_STEP_TOTAL -gt 0)) {
        $total = [int]$env:USE_STEP_TOTAL
    }

    if ($total -gt 0) {
        Write-Step "步骤 ${current}/${total}: $Message"
    }
    else {
        Write-Step $Message
    }
}

# 用法: Initialize-StepProgress 4
# - 无 USE_STEP_CHAIN=1：始终按本脚本步数重置（忽略残留环境变量）
# - 有链式标记：总数 = 已完成 + 本脚本步数（以本脚本为准，防止与入口漂移）
function Initialize-StepProgress {
    param([int]$LocalSteps)

    if ($env:USE_STEP_CHAIN -eq '1') {
        $current = 0
        if (Test-UseStepUInt $env:USE_STEP_CURRENT) { $current = [int]$env:USE_STEP_CURRENT }
        $env:USE_STEP_CURRENT = "$current"
        $env:USE_STEP_TOTAL = "$($current + $LocalSteps)"
        return
    }

    $env:USE_STEP_TOTAL = "$LocalSteps"
    $env:USE_STEP_CURRENT = '0'
}

function Write-Backup {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-SyncProgressHint {
    param(
        [string]$Direction,
        [int]$Total
    )

    if ($Total -le 0) { return }
    if ($env:SYNC_FROM_DISPATCH -eq '1') { return }

    if ($Direction -eq '1') {
        Write-Step "正在备份 $Total 个文件到仓库..."
    }
    else {
        Write-Step "正在恢复 $Total 个文件到本地..."
    }
    [Console]::Out.Flush()
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

# 安装或更新 git 仓库型插件
# - 目录不存在：clone
# - 已存在且 -Update：同 remote 则 pull，否则删了重装
# - 已存在且无 -Update：跳过
function Update-GitRepoToLatest {
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

function Install-GitRepoClone {
    param(
        [string]$Repo,
        [string]$TargetPath,
        [string]$Name
    )

    Write-Info "正在下载插件: $Name..."
    $candidates = @(Get-GithubAccelUrlCandidates -Url $Repo)
    $ok = $false
    foreach ($url in $candidates) {
        if (Test-Path $TargetPath) {
            Remove-Item $TargetPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        git clone $url $TargetPath
        if ($LASTEXITCODE -eq 0) {
            $ok = $true
            if ($url -ne $Repo -and $url -ne (Strip-GithubAccelPrefix -Url $Repo)) {
                Write-Info "$Name 已通过加速源克隆"
            }
            break
        }
    }
    if (-not $ok) {
        Write-Warn "$Name 下载失败，跳过此插件"
        return
    }
    Write-Info "$Name 下载完成"
}

function Sync-GitRepoPlugin {
    param(
        [string]$Repo,
        [string]$TargetPath,
        [string]$Name,
        [switch]$Update
    )

    if (-not (Test-Path $TargetPath -PathType Container)) {
        Install-GitRepoClone -Repo $Repo -TargetPath $TargetPath -Name $Name
        return
    }

    if (-not $Update) {
        Write-Info "插件 $Name 已存在，跳过"
        return
    }

    if (Test-SameRemoteRepo -Dir $TargetPath -ExpectedRepo $Repo) {
        Write-Info "插件 $Name 已是线上仓库，正在拉取最新..."
        $accelUrl = ConvertTo-GithubAccelUrl -Url $Repo
        $current = (git -C $TargetPath remote get-url origin 2>$null)
        if ($accelUrl -and $current -and ($current.Trim() -ne $accelUrl)) {
            git -C $TargetPath remote set-url origin $accelUrl 2>$null
        }
        if (Update-GitRepoToLatest -Dir $TargetPath) {
            Write-Info "$Name 已更新到最新"
        }
        else {
            # 加速源失败时回退官方 remote 再试一次
            $bare = Strip-GithubAccelPrefix -Url $Repo
            git -C $TargetPath remote set-url origin $bare 2>$null
            if (Update-GitRepoToLatest -Dir $TargetPath) {
                Write-Info "$Name 已更新到最新（官方源）"
            }
            else {
                Write-Warn "$Name 拉取最新失败，跳过此插件"
            }
        }
        return
    }

    Write-Info "插件 $Name 同名但非目标仓库，正在删除并重新克隆..."
    Remove-Item $TargetPath -Recurse -Force -ErrorAction SilentlyContinue
    Install-GitRepoClone -Repo $Repo -TargetPath $TargetPath -Name $Name
}

function Write-ErrorAndExit {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}

# --- 系统环境检测 ---
function Get-Os {
    if (($env:OS -eq 'Windows_NT') -or (($null -ne (Get-Variable IsWindows -ErrorAction SilentlyContinue)) -and $IsWindows)) {
        return 'windows'
    }
    if (($null -ne (Get-Variable IsMacOS -ErrorAction SilentlyContinue)) -and $IsMacOS) {
        return 'macos'
    }
    if (($null -ne (Get-Variable IsLinux -ErrorAction SilentlyContinue)) -and $IsLinux) {
        return 'linux'
    }

    $unameS = ''
    try { $unameS = (& uname -s 2>$null) } catch { }

    switch -Regex ($unameS) {
        '^Darwin$' { return 'macos' }
        '^(CYGWIN|MINGW|MSYS)' { return 'windows' }
        '^Linux$' { return 'linux' }
    }

    if ($env:OSTYPE -match '^(msys|cygwin)') { return 'windows' }
    if ($env:OSTYPE -match '^darwin') { return 'macos' }
    if ($env:OSTYPE -match '^linux') { return 'linux' }
    if ($env:WINDIR) { return 'windows' }

    return 'unknown'
}

# 期望值: macos / windows / linux
function Assert-TargetOs {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('macos', 'windows', 'linux')]
        [string]$Expected
    )

    $current = Get-Os
    if ($current -ne $Expected) {
        Write-ErrorAndExit "本脚本仅支持 $Expected，检测到当前系统为 $current"
    }
}

# --- manifest 读取 ---
function Get-ManifestDirectories {
    param([string]$Scope = 'windows')

    $dirs = @()
    $seen = @{}
    foreach ($s in (Get-SyncScopes $Scope)) {
        $m = Read-Manifest -Scope $s
        foreach ($d in @($m.directories)) {
            if ($d -and -not $seen.ContainsKey($d)) {
                $seen[$d] = $true
                $dirs += $d
            }
        }
    }
    return $dirs
}

function Read-Manifest {
    param([string]$Scope = 'windows')

    $manifestPath = Join-Path $Script:ProjectRoot "scripts/$Scope/_manifest.json"
    if (-not (Test-Path $manifestPath)) {
        Write-ErrorAndExit "找不到 manifest: $manifestPath"
    }
    Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-SyncScopes {
    param([string]$Scope)

    $scopes = @($Scope)
    if ($Scope -eq 'macos' -or $Scope -eq 'windows') {
        $scopes += 'common'
    }
    return $scopes
}

function Write-SyncSelectError {
    if ($LASTEXITCODE -eq 130) {
        Write-ErrorAndExit '文件选择已取消'
    }
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorAndExit '文件选择失败，请重试或通过 vpr sync 运行'
    }
}

# --- 路径展开（~ -> $HOME） ---
function Get-ExpandedPath {
    param([string]$Path)
    if ($Path -match '^~(/|\\|$)') {
        $Path = $Path -replace '^~', $env:USERPROFILE
    }
    return $Path -replace '/', '\'
}

function Format-LocalDisplay {
    param([string]$Path)

    $normalized = $Path -replace '\\', '/'
    $userHome = ($env:USERPROFILE -replace '\\', '/').TrimEnd('/')

    if ($normalized -eq $userHome) {
        return '~'
    }
    if ($normalized -like "$userHome/*") {
        return "~/$($normalized.Substring($userHome.Length + 1))"
    }

    return $normalized
}

# --- 文件复制（不保留 Zone.Identifier 等 ADS） ---
function Copy-FileDataOnly {
    param(
        [string]$SourceFile,
        [string]$DestinationFile
    )

    $source = Get-ExpandedPath $SourceFile
    $destination = Get-ExpandedPath $DestinationFile
    $destinationDir = Split-Path $destination -Parent

    if (-not (Test-Path $source)) {
        throw "源文件不存在: $source"
    }

    if (-not (Test-Path $destinationDir)) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }

    $robocopy = Get-Command robocopy.exe -ErrorAction SilentlyContinue
    if ($robocopy) {
        $sourceDir = Split-Path $source -Parent
        $sourceName = Split-Path $source -Leaf
        $destinationName = Split-Path $destination -Leaf
        $robocopyPath = $robocopy.Source
        $copyDir = $destinationDir
        $tempDir = $null

        if ($sourceName -ne $destinationName) {
            $tempDir = Join-Path $destinationDir ".copy-data-only-$([Guid]::NewGuid().ToString('N'))"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            $copyDir = $tempDir
        }

        try {
            & $robocopyPath $sourceDir $copyDir $sourceName /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NC /NS | Out-Null
            $exitCode = $LASTEXITCODE
            if ($exitCode -ge 8) {
                throw "robocopy 复制失败，退出码: $exitCode"
            }

            if ($tempDir) {
                Move-Item (Join-Path $tempDir $sourceName) $destination -Force -ErrorAction Stop
            }
        }
        finally {
            if ($tempDir -and (Test-Path $tempDir)) {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        if (-not (Test-Path $destination)) {
            throw "复制后目标不存在: $destination"
        }
    }
    else {
        Copy-Item $source $destination -Force -ErrorAction Stop
    }
}

# --- 备份（支持自定义路径+日期序号+错误不中断） ---
function Backup-File {
    param(
        [string]$TargetFile,
        [string]$BackupDir = (Split-Path -Parent $TargetFile)
    )

    $target = Get-ExpandedPath $TargetFile
    if (-not (Test-Path $target)) {
        return $null
    }

    $backupRoot = Get-ExpandedPath $BackupDir
    if (-not (Test-Path $backupRoot)) {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    }

    $fileName = Split-Path $target -Leaf
    $dateStr = Get-Date -Format 'yyyyMMdd'
    $backupBase = Join-Path $backupRoot "$fileName.bak.$dateStr"
    $nextNum = 0
    while (Test-Path "$backupBase.$nextNum") { $nextNum++ }

    $backupFile = "$backupBase.$nextNum"
    try {
        Copy-FileDataOnly $target $backupFile
        return "$fileName.bak.$dateStr.$nextNum"
    }
    catch {
        Write-Warn "备份失败: $fileName"
        return $null
    }
}

# --- 解析 config-sync 方向参数 ---
function Resolve-SyncDirectionArg {
    param([string[]]$RawArgs)

    $directionArg = $null
    foreach ($a in $RawArgs) {
        if ($a -eq '--') { continue }
        if ($a -eq '1' -or $a -eq '2') {
            return $a
        }
        if (-not [string]::IsNullOrWhiteSpace($a)) {
            return $a
        }
    }

    return $null
}

function Format-RepoDisplay {
    param([string]$Repo)

    if ($Repo.StartsWith('./')) {
        return $Repo
    }
    return "./$Repo"
}

function Resolve-SyncDirection {
    param(
        [string]$DirectionArg,
        [string]$Example = '示例: vpr sync 2'
    )

    if ($DirectionArg -eq '1' -or $DirectionArg -eq '2') {
        return $DirectionArg
    }

    if (Test-SyncDispatchMode) {
        Write-ErrorAndExit "缺少同步方向参数`n$Example"
    }

    if (-not [string]::IsNullOrWhiteSpace($DirectionArg)) {
        Write-ErrorAndExit "无效的同步方向: 请使用 1 或 2`n$Example"
    }

    $dirScript = Join-Path $PSScriptRoot 'sync-direction.mjs'
    $hint = (& node $dirScript --hint 2>$null)
    if ([string]::IsNullOrWhiteSpace($hint)) {
        $hint = '1=备份配置→仓库, 2=恢复配置→本地'
    }

    if (-not (Test-InteractivePrompt)) {
        Write-ErrorAndExit "非交互环境请传入方向参数: $hint`n$Example"
    }

    $choice = & node $dirScript
    $choice = "$choice".Trim()
    if ($LASTEXITCODE -ne 0 -or ($choice -ne '1' -and $choice -ne '2')) {
        Write-ErrorAndExit "非交互环境请传入方向参数: $hint`n$Example"
    }
    return $choice
}

function Test-SyncDispatchMode {
    return $env:SYNC_FROM_DISPATCH -eq '1'
}

function Test-SkipSyncSelect {
    if ($env:SYNC_SELECT_ALL -eq '1') {
        return $true
    }
    return -not (Test-InteractivePrompt)
}

function Read-SyncItemsFromPairsFile {
    param([string]$PairsFile)

    $selected = @()
    foreach ($line in [System.IO.File]::ReadAllLines($PairsFile)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line.Split("`t")
        $selected += [PSCustomObject]@{
            local  = $parts[0]
            repo   = $parts[1]
            backup = ($parts[2] -eq '1')
        }
    }
    return $selected
}

function Get-SyncItemsFiltered {
    param(
        [string[]]$Scopes,
        [string]$Direction,
        [string]$DirectionArg
    )

    if ($env:SYNC_FILTERED_PAIRS -and (Test-Path $env:SYNC_FILTERED_PAIRS)) {
        try {
            $selected = Read-SyncItemsFromPairsFile $env:SYNC_FILTERED_PAIRS
            if ($selected.Count -eq 0) {
                Write-ErrorAndExit '没有可同步的配置项'
            }
            return $selected
        }
        finally {
            Remove-Item $env:SYNC_FILTERED_PAIRS -Force -ErrorAction SilentlyContinue
            Remove-Item Env:SYNC_FILTERED_PAIRS -ErrorAction SilentlyContinue
        }
    }

    $items = @()
    foreach ($s in $Scopes) {
        $manifest = Read-Manifest -Scope $s
        foreach ($item in $manifest.sync.toRepo) {
            if ($env:SYNC_PROFILE -eq 'lite' -and $item.PSObject.Properties['lite'] -and $item.lite -eq $false) {
                continue
            }
            $items += [PSCustomObject]@{
                local  = $item.local
                repo   = $item.repo
                backup = [bool]$item.backup
            }
        }
    }

    if (Test-SyncDispatchMode) {
        if (Test-SkipSyncSelect) {
            return $items
        }
        Write-ErrorAndExit '缺少已选文件列表，请通过 vpr sync 运行'
    }

    if (Test-SkipSyncSelect) {
        return $items
    }

    $pairsFile = [System.IO.Path]::GetTempFileName()
    $filteredFile = [System.IO.Path]::GetTempFileName()
    try {
        $lines = foreach ($item in $items) {
            $backupFlag = if ($item.backup) { '1' } else { '0' }
            "$($item.local)`t$($item.repo)`t$backupFlag"
        }
        [System.IO.File]::WriteAllLines($pairsFile, $lines)

        if (Test-InteractivePrompt) {
            $env:SYNC_INTERACTIVE = '1'
        }

        $scriptPath = Join-Path $PSScriptRoot 'sync-select.mjs'
        & node $scriptPath $Direction $pairsFile $filteredFile
        Write-SyncSelectError

        $selected = Read-SyncItemsFromPairsFile $filteredFile
        if ($selected.Count -eq 0) {
            Write-ErrorAndExit '没有可同步的配置项'
        }
        return $selected
    }
    finally {
        Remove-Item Env:SYNC_INTERACTIVE -ErrorAction SilentlyContinue
        Remove-Item $pairsFile, $filteredFile -Force -ErrorAction SilentlyContinue
    }
}

# --- 配置同步入口 ---
function Invoke-ManifestSync {
    param(
        [string]$Scope,
        [string]$DirectionArg
    )

    $scopes = Get-SyncScopes $Scope

    $example = '示例: vpr sync 2'
    $direction = Resolve-SyncDirection -DirectionArg $DirectionArg -Example $example
    $items = Get-SyncItemsFiltered -Scopes $scopes -Direction $direction -DirectionArg $DirectionArg
    $total = $items.Count

    Write-SyncProgressHint -Direction $direction -Total $total

    switch ($direction) {
        '1' {
            $i = 0
            foreach ($item in $items) {
                $i++
                $local = Get-ExpandedPath $item.local
                $repo = Join-Path $Script:ProjectRoot $item.repo
                $repoDir = Split-Path $repo -Parent
                if (-not (Test-Path $repoDir)) {
                    New-Item -ItemType Directory -Path $repoDir -Force | Out-Null
                }
                try {
                    Copy-FileDataOnly $local $repo
                } catch {
                    Write-ErrorAndExit $_.Exception.Message
                }
                Write-Backup "[$i/$total] 已备份 $(Format-RepoDisplay $item.repo)"
            }
            Write-Info '配置已备份到仓库'
        }
        '2' {
            $i = 0
            foreach ($item in $items) {
                $i++
                $local = Get-ExpandedPath $item.local
                $repo = Join-Path $Script:ProjectRoot $item.repo
                if ($item.backup) {
                    $bakName = Backup-File $item.local '~/.backup'
                    if ($bakName) {
                        Write-Backup "[$i/$total] 已备份 $(Format-LocalDisplay $item.local) -> ~/.backup/$bakName"
                    }
                }
                $localDir = Split-Path $local -Parent
                if (-not (Test-Path $localDir)) {
                    New-Item -ItemType Directory -Path $localDir -Force | Out-Null
                }
                try {
                    Copy-FileDataOnly $repo $local
                } catch {
                    Write-ErrorAndExit $_.Exception.Message
                }
                Write-Backup "[$i/$total] 已恢复 $(Format-LocalDisplay $item.local)"
            }
            Write-Info '配置已恢复到本地'
        }
        default {
            Write-ErrorAndExit '无效选择'
        }
    }
}
