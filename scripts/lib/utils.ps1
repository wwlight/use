$Script:ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -eq 'Restricted' -or $policy -eq 'Undefined') {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
}

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
        return $Path -replace '^~', $env:USERPROFILE
    }
    return $Path
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
        Copy-Item $target $backupFile -Force
        Write-Info "备份成功: $target -> $backupFile"
    }
    catch {
        Write-Warn "备份失败: $target -> $backupFile"
    }
}

# ==============================
# 解析 config-sync 方向参数
# ==============================
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
        [string]$Arg,
        [string[]]$BackupLocal
    )

    $manifest = Read-Manifest -Scope $Scope
    $example = "示例: npm run ${Scope}:sync -- 2 或 vpr ${Scope}:sync 2"
    $line1 = "1) 备份本地配置 -> 仓库 configs/$Scope/"
    $line2 = "2) 从仓库恢复配置 -> 本地"

    $direction = Get-SyncDirection $Arg $example $line1 $line2

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
                Copy-Item $local $repo -Force
                Write-Info "[$i/$total] 已备份 $($item.repo)"
            }
            Write-Info "配置已备份到仓库"
        }
        '2' {
            foreach ($f in $BackupLocal) {
                Backup-File $f '~/.backup'
            }
            $i = 0
            foreach ($item in $manifest.sync.toRepo) {
                $i++
                $local = Get-ExpandedPath $item.local
                $repo = Join-Path $Script:ProjectRoot $item.repo
                $localDir = Split-Path $local -Parent
                if (-not (Test-Path $localDir)) {
                    New-Item -ItemType Directory -Path $localDir -Force | Out-Null
                }
                Copy-Item $repo $local -Force
                Write-Info "[$i/$total] 已恢复 $($item.local)"
            }
            Write-Info "配置已恢复到本地"
        }
        default {
            Write-Host '无效选择'
            exit 1
        }
    }

    Write-Info "下次可直接运行：npm run ${Scope}:sync -- ${Direction} 跳过交互选择"
}
