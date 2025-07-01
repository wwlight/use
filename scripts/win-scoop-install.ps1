#!/usr/bin/env pwsh
# install_scoop.ps1 - Scoop安装脚本

# 检查是否已安装 Scoop
if (Get-Command scoop -ErrorAction SilentlyContinue) {
    Write-Host "[INFO] Scoop 已安装，跳过安装步骤" -ForegroundColor Green
    exit $LASTEXITCODE
}

# 设置Scoop安装路径
$env:SCOOP = 'D:\DevelopApplication\Scoop'
[Environment]::SetEnvironmentVariable('SCOOP', $env:SCOOP, 'User')

# 设置执行策略
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# 安装Scoop
try {
    Write-Host "[INFO] 正在安装 Scoop..." -ForegroundColor Cyan
    Invoke-Expression "& {$(Invoke-RestMethod get.scoop.sh)} -RunAsAdmin"

    # 检查安装是否成功
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host "[INFO] Scoop安装成功，正在安装 git..." -ForegroundColor Green

        # 确保主桶已添加
        scoop bucket add main

        # 更新Scoop（确保元数据最新）
        scoop update

        try {
            scoop install git
            Write-Host "[INFO] git 安装成功" -ForegroundColor Green
            exit 0
        } catch {
            Write-Host "[ERROR] git 安装失败: $_" -ForegroundColor Red
            exit 1
        }
        exit $LASTEXITCODE
    } else {
        Write-Host "[ERROR] Scoop 安装后仍未找到，请手动检查" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "[ERROR] Scoop安装失败: $_" -ForegroundColor Red
    exit 1
}
