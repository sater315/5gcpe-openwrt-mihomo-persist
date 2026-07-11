param(
    [string]$SSH_IP = $(if ($env:SSH_IP) { $env:SSH_IP } else { "192.168.8.1" }),
    [string]$SSH_USER = $(if ($env:SSH_USER) { $env:SSH_USER } else { "root" }),
    [string]$SSH_PASSWORD = $env:SSH_PASSWORD
)

$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Config = Join-Path $Here "config.example.yaml"
if (-not (Test-Path $Config)) { throw "缺少配置模板: $Config" }

Write-Host "`n=== 关闭 TUN + DNS 接管，恢复普通 mixed-port 代理 ===" -ForegroundColor Cyan
Write-Host "会备份路由器现有 /data/clash/config.yaml，然后覆盖为 config.example.yaml"
& "$Here\deploy.ps1" -Action install -SSH_IP $SSH_IP -SSH_USER $SSH_USER -SSH_PASSWORD $SSH_PASSWORD -Config $Config -OverwriteConfig
if ($LASTEXITCODE -ne 0) { throw "关闭 TUN + 分流规则失败" }

Write-Host "`n[OK] 已恢复普通代理模式" -ForegroundColor Green
Write-Host "HTTP/SOCKS: $SSH_IP`:7890" -ForegroundColor Yellow
Write-Host "控制接口: http://$SSH_IP`:9090" -ForegroundColor Yellow
