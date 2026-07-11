# 中文入口：启用 TUN + 分流规则
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$Here\enable-tun-rules.ps1" @args
