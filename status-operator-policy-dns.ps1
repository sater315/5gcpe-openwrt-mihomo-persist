param(
    [string]$SSH_IP = $(if ($env:SSH_IP) { $env:SSH_IP } else { "192.168.8.1" }),
    [string]$SSH_USER = $(if ($env:SSH_USER) { $env:SSH_USER } else { "root" }),
    [string]$SSH_PASSWORD = $env:SSH_PASSWORD
)
$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$Here\deploy.ps1" -Action operator-status -SSH_IP $SSH_IP -SSH_USER $SSH_USER -SSH_PASSWORD $SSH_PASSWORD
