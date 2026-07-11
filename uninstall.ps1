param(
    [string]$SSH_IP = $(if ($env:SSH_IP) { $env:SSH_IP } else { "192.168.8.1" }),
    [string]$SSH_USER = $(if ($env:SSH_USER) { $env:SSH_USER } else { "root" }),
    [string]$SSH_PASSWORD = $env:SSH_PASSWORD,
    [switch]$PurgeBackups
)

$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Py = Get-Command python -ErrorAction SilentlyContinue
if (-not $Py) { $Py = Get-Command py -ErrorAction SilentlyContinue }
if (-not $Py) { throw "python/py not found" }

if (-not $SSH_PASSWORD) {
    $Secure = Read-Host "SSH password for $SSH_USER@$SSH_IP" -AsSecureString
    $BSTR = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { $SSH_PASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR) }
}

$ArgsList = @("$Here\scripts\deploy.py", "uninstall", "--host", $SSH_IP, "--user", $SSH_USER, "--password", $SSH_PASSWORD)
if ($PurgeBackups) { $ArgsList += "--purge-backups" }
& $Py.Source @ArgsList
