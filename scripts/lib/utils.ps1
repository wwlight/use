$Script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

# ==============================
# 平台特有（Windows）
# ==============================
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
    if (-not [Environment]::UserInteractive) {
        return $false
    }

    try {
        return -not [Console]::IsInputRedirected
    }
    catch {
        return $false
    }
}

# ==============================
# 打印方法
# ==============================
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-ErrorAndExit {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}

# ==============================
# 远程脚本下载（带进度）
# ==============================
function Invoke-RemoteScript {
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        [string]$Label = '远程脚本'
    )

    Write-Info "正在下载 $Label ..."
    Write-Host "  $Url" -ForegroundColor DarkGray

    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.Timeout = 300000
    $request.UserAgent = 'use-main/1.0'

    try {
        $response = $request.GetResponse()
    }
    catch {
        Write-ErrorAndExit "下载失败: $Url`n$($_.Exception.Message)"
    }

    $totalBytes = $response.ContentLength
    $stream = $response.GetResponseStream()
    $buffer = New-Object byte[] 8192
    $downloaded = 0L
    $ms = New-Object System.IO.MemoryStream

    try {
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $ms.Write($buffer, 0, $read)
            $downloaded += $read
            if ($totalBytes -gt 0) {
                $pct = [int][math]::Min(100, ($downloaded * 100 / $totalBytes))
                $status = '{0:N1} / {1:N1} KB' -f ($downloaded / 1KB), ($totalBytes / 1KB)
                Write-Progress -Activity "下载 $Label" -Status $status -PercentComplete $pct
            }
            else {
                $status = '{0:N1} KB' -f ($downloaded / 1KB)
                Write-Progress -Activity "下载 $Label" -Status $status
            }
        }
    }
    finally {
        Write-Progress -Activity "下载 $Label" -Completed
        $stream.Close()
        $response.Close()
    }

    Write-Info "下载完成 ($('{0:N1}' -f ($downloaded / 1KB)) KB)"
    Write-Info '正在执行安装脚本（可能需要几分钟）...'

    $scriptText = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
    Invoke-Expression $scriptText
}

# ==============================
# manifest 读取
# ==============================
function Read-Manifest {
    param([string]$Scope = 'windows')

    $manifestPath = Join-Path $Script:ProjectRoot "scripts/$Scope/_manifest.json"
    if (-not (Test-Path $manifestPath)) {
        Write-ErrorAndExit "找不到 manifest: $manifestPath"
    }
    Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

# ==============================
# 路径展开（~ -> $HOME）
# ==============================
function Get-ExpandedPath {
    param([string]$Path)
    if ($Path -match '^~(/|\\|$)') {
        $Path = $Path -replace '^~', $env:USERPROFILE
    }
    return $Path -replace '/', '\'
}

# ==============================
# 文件复制（不保留 Zone.Identifier 等 ADS）
# ==============================
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
                Move-Item (Join-Path $tempDir $sourceName) $destination -Force
            }
        }
        finally {
            if ($tempDir -and (Test-Path $tempDir)) {
                Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        Copy-Item $source $destination -Force
    }
}

# ==============================
# 备份（支持自定义路径+日期序号+错误不中断）
# ==============================
function Backup-File {
    param(
        [string]$TargetFile,
        [string]$BackupDir = (Split-Path -Parent $TargetFile)
    )

    $target = Get-ExpandedPath $TargetFile
    if (-not (Test-Path $target)) {
        Write-Warn "目标文件不存在: $target"
        return
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
        Write-Info "备份成功: $target -> $backupFile"
    }
    catch {
        Write-Warn "备份失败: $target -> $backupFile"
    }
}

# ==============================
# 解析 config-sync 方向参数
# ==============================
function Resolve-SyncDirectionArg {
    param([string[]]$RawArgs)

    $directionArg = $null
    foreach ($a in $RawArgs) {
        if ($a -eq '1' -or $a -eq '2') {
            $directionArg = $a
        }
    }

    return $directionArg
}

function Get-SyncDirection {
    param(
        [string]$DirectionArg,
        [string]$Example,
        [string]$Line1,
        [string]$Line2
    )

    if ($DirectionArg -eq '1' -or $DirectionArg -eq '2') {
        return $DirectionArg
    }

    if (-not (Test-InteractivePrompt)) {
        Write-ErrorAndExit "非交互环境请传入方向参数: 1=备份到仓库, 2=应用到本地`n$Example"
    }

    Write-Host "请选择拷贝方向:"
    Write-Host $Line1
    Write-Host $Line2
    $choice = Read-Host
    if ([string]::IsNullOrWhiteSpace($choice)) {
        Write-ErrorAndExit "非交互环境请传入方向参数: 1=备份到仓库, 2=应用到本地`n$Example"
    }
    return $choice
}

# ==============================
# 配置同步入口
# ==============================
function Invoke-ManifestSync {
    param(
        [string]$Scope,
        [string]$DirectionArg
    )

    $manifest = Read-Manifest -Scope $Scope
    $example = "示例: npm run ${Scope}:sync -- 2 或 vpr ${Scope}:sync 2"
    $line1 = "1) 备份本地配置 -> 仓库 configs/$Scope/"
    $line2 = "2) 从仓库恢复配置 -> 本地"

    $direction = Get-SyncDirection $DirectionArg $example $line1 $line2

    $total = $manifest.sync.toRepo.Count

    switch ($direction) {
        '1' {
            $i = 0
            foreach ($item in $manifest.sync.toRepo) {
                $i++
                $local = Get-ExpandedPath $item.local
                $repo = Join-Path $Script:ProjectRoot $item.repo
                $repoDir = Split-Path $repo -Parent
                if (-not (Test-Path $repoDir)) {
                    New-Item -ItemType Directory -Path $repoDir -Force | Out-Null
                }
                Copy-FileDataOnly $local $repo
                Write-Info "[$i/$total] 已备份 $($item.repo)"
            }
            Write-Info "配置已备份到仓库"
        }
        '2' {
            $i = 0
            foreach ($item in $manifest.sync.toRepo) {
                $i++
                $local = Get-ExpandedPath $item.local
                $repo = Join-Path $Script:ProjectRoot $item.repo
                if ($item.backup) {
                    Backup-File $item.local '~/.backup'
                }
                $localDir = Split-Path $local -Parent
                if (-not (Test-Path $localDir)) {
                    New-Item -ItemType Directory -Path $localDir -Force | Out-Null
                }
                Copy-FileDataOnly $repo $local
                Write-Info "[$i/$total] 已恢复 $($item.local)"
            }
            Write-Info "配置已恢复到本地"
        }
        default {
            Write-Host '无效选择'
            exit 1
        }
    }

    if ([string]::IsNullOrWhiteSpace($DirectionArg)) {
        Write-Info "下次可直接运行：npm run ${Scope}:sync -- $direction 跳过交互选择"
    }
}
