# 中文入口：双击/右键 PowerShell 运行，或在 PowerShell 中执行 .\一键部署.ps1
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$Here\oneclick.ps1" @args
