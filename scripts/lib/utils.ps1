$Script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

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

function Get-ExpandedPath {
    param([string]$Path)
    if ($Path -match '^~(/|\\|$)') {
        return $Path -replace '^~', $env:USERPROFILE
    }
    return $Path
}

function Read-Manifest {
    $manifestPath = Join-Path $Script:ProjectRoot 'scripts/windows/manifest.json'
    if (-not (Test-Path $manifestPath)) {
        Write-ErrorAndExit "找不到 manifest: $manifestPath"
    }
    Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

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
        Copy-Item $target $backupFile -Force
        Write-Info "备份成功: $target -> $backupFile"
    }
    catch {
        Write-Warn "备份失败: $target -> $backupFile"
    }
}

function Get-SyncDirection {
    param(
        [string]$Arg,
        [string]$Example,
        [string]$Line1,
        [string]$Line2
    )

    if ($Arg -eq '1' -or $Arg -eq '2') {
        return $Arg
    }

    Write-Host '请选择拷贝方向:'
    Write-Host $Line1
    Write-Host $Line2
    $choice = Read-Host
    if ([string]::IsNullOrWhiteSpace($choice)) {
        Write-Host "[ERROR] 非交互环境请传入方向参数: 1=备份到仓库, 2=应用到本地`n$Example" -ForegroundColor Red
        exit 1
    }
    return $choice
}

function Invoke-PwshScript {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    $psArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath) + $Arguments
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        & pwsh @psArgs
    }
    else {
        & powershell.exe @psArgs
    }
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
