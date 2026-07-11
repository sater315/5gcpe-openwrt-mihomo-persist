# 5GCPE Mihomo 持久化部署验证记录

验证时间：2026-07-11 16:54-16:58 UTC，设备本地显示为 UTC。

## 设备

- SSH：root@192.168.8.1:22
- 系统：OpenWrt 21.02.7
- 内核：Linux 5.4.238
- 架构：aarch64 / aarch64_cortex-a55_neon-vfpv4
- 持久目录：/data ext4

## 已部署版本

- Mihomo：v1.19.28
- Binary：mihomo-linux-arm64-v1.19.28.gz
- SHA256：2474450cd1c41dfa53036a54a4e85579f493d3af524d86c3d4b8e2b240b56cd2

## 重启自启动验证

执行：

```sh
sync; reboot
```

重启前进程：

```text
17726 root /data/clash/mihomo -d /data/clash -f /data/clash/config.yaml
17740 root /bin/sh /data/clash/watchdog_clash.sh
```

重启后状态：

```text
11347 root /data/clash/mihomo -d /data/clash -f /data/clash/config.yaml
11504 root /bin/sh /data/clash/watchdog_clash.sh
```

日志关键证据：

```text
2026-07-11T16:54:29 Mihomo shutting down
2026-07-11 16:55:06 starting mihomo: /data/clash/mihomo -d /data/clash -f /data/clash/config.yaml
2026-07-11 16:55:07 started pid=11347
2026-07-11 16:55:06 watchdog start pid=11504 interval=60
```

端口：

```text
:::7890 LISTEN mihomo
:::9090 LISTEN mihomo
```

Controller 验证：

```text
GET http://192.168.8.1:9090/version
{"meta":true,"version":"v1.19.28"}
```

结论：重启后 `/data/clash` 文件保留，`/data/ssh_persist.sh` 中的 `CODEX_MIHOMO_PERSIST` 钩子生效，Mihomo 和 watchdog 自动恢复。

## 一键卸载验证

执行：

```powershell
.\uninstall.ps1
```

卸载后状态：

```text
/data/clash 不存在
/data/service_persist.sh 不存在
/data/ssh_persist.sh 中无 CODEX_MIHOMO_PERSIST
mihomo 进程不存在
watchdog_clash 进程不存在
7890/9090 不监听
CODEX_MIHOMO_INPUT iptables 链不存在
```

结论：一键卸载可清理本次部署产生的文件、进程、iptables 链和启动钩子；不影响原有 SSH 固化链。

## 一键重装验证

执行：

```powershell
.\install.ps1
```

重装后状态：

```text
/data/clash/mihomo 存在并可执行
/data/clash/config.yaml 存在
/data/clash/enabled 存在
/data/service_persist.sh 存在
/data/ssh_persist.sh 中 CODEX_MIHOMO_PERSIST 存在
20348 root /data/clash/mihomo -d /data/clash -f /data/clash/config.yaml
20462 root /bin/sh /data/clash/watchdog_clash.sh
:::7890 LISTEN mihomo
:::9090 LISTEN mihomo
```

结论：一键重装可恢复完整运行态。

## 启动/停止幂等与 TUN 回滚验证

验证时间：2026-07-11 19:06-19:10，设备本地时间。

### 普通模式配置

```yaml
dns:
  enable: false

tun:
  enable: false

rules:
  - MATCH,DIRECT
```

### 普通模式 start/stop 测试

测试动作：

```text
service_persist.sh 连续执行 3 次
start_clash.sh 连续执行 3 次
stop_clash.sh 连续执行 1 次
stop_clash.sh 在已停止状态下再连续执行 2 次
stop/start 循环 2 轮
```

结果：

```text
ALL_SAFE_START_STOP_TESTS_PASS
```

关键状态：

```text
mihomo_count=1 watchdog_count=1
:::7890 LISTEN mihomo
:::9090 LISTEN mihomo
无 :::7874
无 mihomo TUN link
无 ip rule pref 9000/9001/9002/9010
无 table 2022 残留
WAN ping OK
```

### 临时 TUN 启动后停止回滚测试

测试动作：

```text
1. 停止普通模式。
2. 临时写入 config.tun-rules.example.yaml。
3. 启动 Mihomo TUN。
4. 确认 :::7874、mihomo TUN 网卡、9000 系列策略路由出现。
5. 执行 stop_clash.sh。
6. 验证进程、端口、TUN 网卡、策略路由、table 2022 全部清理。
7. 恢复普通 config.example.yaml。
8. 重新 service_persist.sh 启动普通模式。
```

TUN 启动时证据：

```text
:::7890 LISTEN mihomo
:::7874 LISTEN mihomo
:::9090 LISTEN mihomo
mihomo: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 9000
9000: from all to 198.18.0.0/30 lookup 2022
9001: not from all dport 53 lookup main suppress_prefixlength 0
9001: from all iif mihomo goto 9010
9002: not from all iif lo lookup 2022
9002: from 0.0.0.0 iif lo lookup 2022
9002: from 198.18.0.0/30 iif lo lookup 2022
9010: from all nop
```

停止并恢复普通模式后证据：

```text
TUN_START_STOP_ROLLBACK_TEST_PASS
:::7890 LISTEN mihomo
:::9090 LISTEN mihomo
无 :::7874
无 mihomo TUN link
无 9000/9001/9002/9010 策略路由
WAN ping OK
```

结论：

```text
当前启动/停止方案可重复执行、无重复进程、无端口残留、无 TUN 路由残留。
普通模式可作为稳定默认运行状态。
TUN 配置仍不建议长期启用，但即使临时启动过，也可以被 stop_clash.sh 清理恢复。
```

## 运营商策略路由和 DNS 关闭/恢复验证

验证时间：2026-07-11 19:32-19:39，设备本地时间。

### 原始状态

运营商/厂商策略路由：

```text
0:      from all lookup local
60:     from all lookup 60
80:     from all lookup 80
100:    from 10.114.55.59 lookup 100
100:    from all fwmark 0x4000000/0xfc000000 lookup 100
100:    from all oif ccmni3 lookup 100
32766:  from all lookup main
32767:  from all lookup default
```

运营商 DNS：

```text
/tmp/resolv.conf
/var/resolv.conf
/tmp/resolv.conf.d/resolv.conf.auto

nameserver 211.138.240.110
nameserver 211.138.245.188
```

### 关闭动作

执行：

```powershell
.\deploy.ps1 -Action operator-disable
```

关闭后状态：

```text
--- marker ---
disabled 2026-07-11 19:39:03

--- ip rule ---
0:      from all lookup local
32766:  from all lookup main
32767:  from all lookup default

--- dns files ---
nameserver 223.5.5.5
nameserver 119.29.29.29
nameserver 1.1.1.1
```

网络验证：

```text
PING 223.5.5.5: 1 packets transmitted, 1 packets received, 0% packet loss
nslookup baidu.com 使用 Server: 223.5.5.5
```

持久保持进程：

```text
/data/clash/operator_policy_dns_watchdog.sh
/tmp/codex_operator_policy_dns_watchdog.pid
```

### 恢复动作

执行：

```powershell
.\deploy.ps1 -Action operator-restore
```

恢复后状态：

```text
60:     from all lookup 60
80:     from all lookup 80
100:    from 10.114.55.59 lookup 100
100:    from all fwmark 0x4000000/0xfc000000 lookup 100
100:    from all oif ccmni3 lookup 100

table 100:
default via 10.114.55.60 dev ccmni3
10.114.55.56/29 dev ccmni3 scope link
192.168.8.0/24 dev br0 scope link

DNS:
nameserver 211.138.240.110
nameserver 211.138.245.188
```

### 再次关闭

恢复后再次执行 `operator-disable`，最终状态回到：

```text
ip rule 只剩 local/main/default
DNS 为 223.5.5.5 / 119.29.29.29 / 1.1.1.1
WAN ping 正常
operator_policy_dns_watchdog 正常运行
```

结论：

```text
运营商策略路由和 DNS 可以在运行态关闭，并通过 /data 持久标记保持；
也可以一键恢复到运营商 pref 60/80/100 策略和 211.138.* DNS。
```

## VLESS REALITY + TUN 临时导入测试

用户提供了一份 Xray/V2Ray JSON 格式的 VLESS Reality 节点配置，本仓库没有把该节点密钥写入 Git，仅在本地 `.cache/` 和路由器 `/tmp/` 中做临时转换和测试。

转换为 Mihomo YAML 后的关键形态：

```yaml
proxies:
  - name: REALITY
    type: vless
    network: tcp
    tls: true
    flow: xtls-rprx-vision
    client-fingerprint: chrome
    reality-opts:
      public-key: <redacted>
      short-id: <redacted>
```

### 首次失败原因

最初普通代理和 TUN 测试中，节点测速失败，Mihomo 日志出现：

```text
REALITY Authentication: false
connect error: REALITY authentication failed
```

排查发现路由器系统 epoch 比本机/真实 UTC 快 28800 秒：

```text
路由器 date -u: 2026-07-11 20:17 UTC
本机 UTC:        2026-07-11 12:17 UTC
偏差:            +8 小时
```

REALITY 对时间敏感，系统时钟偏差会导致认证失败。执行：

```sh
date -u -s '@<correct_epoch>'
```

校准后，同一个节点普通 mixed-port 测试通过：

```text
controller delay:
http://www.gstatic.com/generate_204      {"delay":579}
https://www.gstatic.com/generate_204     {"delay":834}
http://cp.cloudflare.com/generate_204    {"delay":573}
https://www.cloudflare.com/cdn-cgi/trace {"delay":837}

本机 curl:
HTTP proxy  192.168.8.1:7890 -> https://www.gstatic.com/generate_204 204
HTTP proxy  192.168.8.1:7890 -> https://www.cloudflare.com/cdn-cgi/trace 200
SOCKS5H     192.168.8.1:7890 -> https://www.gstatic.com/generate_204 204
```

### TUN 1-2 分钟自动回滚测试

校准时间后，将该 REALITY 节点导入临时 TUN 配置，测试窗口约 90 秒，测试结束自动回滚到普通模式。

TUN 启动证据：

```text
TUN_READY n=0
tun_link=48: mihomo: <POINTOPOINT,MULTICAST,NOARP,UP,LOWER_UP> mtu 9000
ports=:::7890 :::7874 :::9090
rules=9000/9001/9002/9010 -> table 2022
```

路由器侧 8 轮检测：

```text
router_wan_ping=OK round=1..8
router_dnsmasq_dns=OK round=1..8
controller=OK round=1..8
proxy_delay rc=0 https://www.gstatic.com/generate_204      delay=808-1247ms
proxy_delay rc=0 https://www.cloudflare.com/cdn-cgi/trace delay=814-1269ms
```

本机侧连续监控：

```text
router=True
wan=True
dnsViaRouter=True
controller=True
```

回滚后状态：

```text
post_ports=:::7890 :::9090
post_tun=
post_rules=
post_rollback_wan=OK

/data/clash/config.yaml:
dns.enable: false
tun.enable: false
rules: MATCH,DIRECT

/tmp/resolv.conf:
nameserver 223.5.5.5
nameserver 119.29.29.29
nameserver 1.1.1.1
```

结论：

```text
该设备支持 Mihomo core 的 VLESS REALITY + TUN 临时运行。
此前失败不是 TUN 路由问题，而是系统 UTC 时间偏差导致 REALITY 认证失败。
仓库已加入 router/time_sync.sh，并由 start_clash.sh 在冷启动前自动调用。
```
