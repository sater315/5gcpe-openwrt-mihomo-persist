# 中文入口：查看运营商策略路由和 DNS 状态
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
& "$Here\status-operator-policy-dns.ps1" @args
