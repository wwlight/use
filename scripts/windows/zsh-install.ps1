param()

$ScriptDir = Split-Path $PSScriptRoot -Parent
. (Join-Path $ScriptDir 'lib/utils.ps1')

Assert-TargetOs windows

$manifest = Read-Manifest

function Get-GitPath {
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-ErrorAndExit '未检测到 scoop 安装，请先安装 scoop'
    }

    $gitPath = (scoop prefix git).Trim()
    if ([string]::IsNullOrWhiteSpace($gitPath) -or -not (Test-Path $gitPath)) {
        Write-ErrorAndExit '无法获取 git 路径'
    }

    return $gitPath
}

function Get-ZshExePath {
    param([string]$GitPath)

    return Join-Path $GitPath 'usr\bin\zsh.exe'
}

function Test-ZshInstalled {
    param([string]$GitPath)

    return Test-Path (Get-ZshExePath $GitPath)
}

function Remove-PathSafe {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
        return
    }

    Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
}

function Install-ZshForGit {
    param(
        $ZshInstall,
        [string]$GitPath
    )

    $workDir = Get-ExpandedPath $ZshInstall.workDir
    $tempExtractDir = Join-Path $workDir $ZshInstall.tempExtractDir
    $cpErrorLog = Join-Path $workDir $ZshInstall.cpErrorLog
    $zipFile = Join-Path $workDir $ZshInstall.archiveName
    $tarFile = Join-Path $workDir ($ZshInstall.archiveName -replace '\.zst$')

    Write-Step '步骤1/6: 下载 zsh 压缩包...'
    & curl.exe --ssl-no-revoke -L $ZshInstall.downloadUrl -o $zipFile
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorAndExit '下载 zsh 压缩包失败'
    }
    Write-Info "下载完成: $zipFile"

    Write-Step '步骤2/6: 查找 git 安装路径...'
    Write-Info "git 路径: $GitPath"
    Write-Host ''

    Write-Step '步骤3/6: 检查 7z 工具...'
    if (-not (Get-Command 7z -ErrorAction SilentlyContinue)) {
        Remove-PathSafe $zipFile
        Write-ErrorAndExit '7z 命令未找到，请安装 7-Zip'
    }
    Write-Info '7z 工具可用'

    Write-Step '步骤4/6: 解压 .zst 文件...'
    Remove-PathSafe $tempExtractDir
    New-Item -ItemType Directory -Path $tempExtractDir -Force | Out-Null

    & 7z x "-o$workDir" $zipFile
    if ($LASTEXITCODE -ne 0) {
        Remove-PathSafe $zipFile
        Remove-PathSafe $tempExtractDir
        Write-ErrorAndExit '解压 .zst 文件失败'
    }

    if (-not (Test-Path $tarFile)) {
        Remove-PathSafe $zipFile
        Remove-PathSafe $tempExtractDir
        Write-ErrorAndExit '未找到解压后的 .tar 文件'
    }
    Write-Info '.zst 文件解压完成'

    Write-Step '步骤5/6: 解压 .tar 文件并移动文件...'
    & 7z x "-o$tempExtractDir" $tarFile
    if ($LASTEXITCODE -ne 0) {
        Remove-PathSafe $zipFile
        Remove-PathSafe $tarFile
        Remove-PathSafe $tempExtractDir
        Write-ErrorAndExit '解压 .tar 文件失败'
    }
    Write-Info '.tar 文件解压完成'

    try {
        Copy-Item -Path (Join-Path $tempExtractDir '*') -Destination $gitPath -Recurse -Force -ErrorAction Stop
        Write-Info '文件移动完成'
        Remove-PathSafe $cpErrorLog
    }
    catch {
        $_ | Out-File -FilePath $cpErrorLog -Encoding utf8
        Remove-PathSafe $zipFile
        Remove-PathSafe $tarFile
        Remove-PathSafe $tempExtractDir
        Write-ErrorAndExit "移动失败，查看详细错误: $cpErrorLog"
    }

    Write-Step '步骤6/6: 清理临时文件...'
    Remove-PathSafe $zipFile
    Remove-PathSafe $tarFile
    Remove-PathSafe $tempExtractDir

    Write-Info 'zsh 安装完成！'
}

$gitPath = Get-GitPath
$zshAlreadyInstalled = Test-ZshInstalled $gitPath

if (-not $zshAlreadyInstalled) {
    Install-ZshForGit -ZshInstall $manifest.zshInstall -GitPath $gitPath
}
else {
    Write-Info 'zsh 已安装，跳过'
}
