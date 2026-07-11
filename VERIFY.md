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
