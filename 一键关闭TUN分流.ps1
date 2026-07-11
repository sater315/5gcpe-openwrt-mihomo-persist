# 中文入口：关闭 TUN + 分流规则，恢复普通代理
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$Here\disable-tun-rules.ps1" @args
