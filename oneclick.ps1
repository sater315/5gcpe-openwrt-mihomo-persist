param(
    [string]$SSH_IP = $(if ($env:SSH_IP) { $env:SSH_IP } else { "192.168.8.1" }),
    [string]$SSH_USER = $(if ($env:SSH_USER) { $env:SSH_USER } else { "root" }),
    [string]$SSH_PASSWORD = $env:SSH_PASSWORD,
    [string]$Config = "",
    [switch]$OverwriteConfig
)

$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say($Text) { Write-Host "`n=== $Text ===" -ForegroundColor Cyan }
function Ok($Text) { Write-Host "[OK] $Text" -ForegroundColor Green }

Say "5GCPE Mihomo 傻瓜式一键部署"
Write-Host "目标设备: $SSH_USER@$SSH_IP"
Write-Host "固定资源: resources/mihomo-linux-arm64-v1.19.28.gz"
Write-Host "部署目录: /data/clash"

$Py = Get-Command python -ErrorAction SilentlyContinue
if (-not $Py) { $Py = Get-Command py -ErrorAction SilentlyContinue }
if (-not $Py) { throw "未找到 python/py。请先安装 Python 3。" }
Ok "Python: $($Py.Source)"

Say "检查 Python 依赖 paramiko"
& $Py.Source -c "import paramiko" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "未检测到 paramiko，正在自动安装到当前用户环境..." -ForegroundColor Yellow
    & $Py.Source -m pip install --user paramiko
    if ($LASTEXITCODE -ne 0) { throw "paramiko 安装失败" }
}
Ok "paramiko 已就绪"

if (-not $SSH_PASSWORD) {
    Say "输入路由器 SSH 密码"
    $Secure = Read-Host "SSH password for $SSH_USER@$SSH_IP" -AsSecureString
    $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { $SSH_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR) }
}

Say "开始部署，等待完成即可"
$ArgsList = @("$Here\scripts\deploy.py", "install", "--host", $SSH_IP, "--user", $SSH_USER, "--password", $SSH_PASSWORD, "--wait-timeout", "120")
if ($Config -ne "") { $ArgsList += @("--config", $Config) }
if ($OverwriteConfig) { $ArgsList += "--overwrite-config" }
& $Py.Source @ArgsList
if ($LASTEXITCODE -ne 0) { throw "部署失败" }

Say "部署完成"
Ok "Mihomo 已安装到 /data/clash，并接入开机自启动链"
Ok "HTTP/SOCKS 代理: $SSH_IP`:7890"
Ok "控制接口: http://$SSH_IP`:9090"
Write-Host "`n查看状态: .\deploy.ps1 -Action status" -ForegroundColor Yellow
Write-Host "一键卸载: .\deploy.ps1 -Action uninstall" -ForegroundColor Yellow
