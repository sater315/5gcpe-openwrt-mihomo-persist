param(
    [string]$SSH_IP = $(if ($env:SSH_IP) { $env:SSH_IP } else { "192.168.8.1" }),
    [string]$SSH_USER = $(if ($env:SSH_USER) { $env:SSH_USER } else { "root" }),
    [string]$SSH_PASSWORD = $env:SSH_PASSWORD
)

$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Config = Join-Path $Here "config.tun-rules.example.yaml"
if (-not (Test-Path $Config)) { throw "缺少配置模板: $Config" }

Write-Host "`n=== 启用 Mihomo TUN + 分流规则 ===" -ForegroundColor Cyan
Write-Host "会备份路由器现有 /data/clash/config.yaml，然后覆盖为 config.tun-rules.example.yaml"
& "$Here\deploy.ps1" -Action install -SSH_IP $SSH_IP -SSH_USER $SSH_USER -SSH_PASSWORD $SSH_PASSWORD -Config $Config -OverwriteConfig
if ($LASTEXITCODE -ne 0) { throw "启用 TUN + 分流规则失败" }

Write-Host "`n[OK] 已启用 TUN + 分流规则模板" -ForegroundColor Green
Write-Host "查看状态: .\deploy.ps1 -Action status" -ForegroundColor Yellow
Write-Host "关闭恢复普通代理: .\一键关闭TUN分流.ps1" -ForegroundColor Yellow
