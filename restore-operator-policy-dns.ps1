param(
    [string]$SSH_IP = $(if ($env:SSH_IP) { $env:SSH_IP } else { "192.168.8.1" }),
    [string]$SSH_USER = $(if ($env:SSH_USER) { $env:SSH_USER } else { "root" }),
    [string]$SSH_PASSWORD = $env:SSH_PASSWORD
)
$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "`n=== 恢复运营商策略路由和 DNS ===" -ForegroundColor Cyan
& "$Here\deploy.ps1" -Action operator-restore -SSH_IP $SSH_IP -SSH_USER $SSH_USER -SSH_PASSWORD $SSH_PASSWORD
if ($LASTEXITCODE -ne 0) { throw "恢复运营商策略/DNS 失败" }
Write-Host "`n[OK] 已恢复运营商策略路由和 DNS" -ForegroundColor Green
