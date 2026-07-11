# 中文入口：关闭运营商策略路由和运营商 DNS
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$Here\disable-operator-policy-dns.ps1" @args
