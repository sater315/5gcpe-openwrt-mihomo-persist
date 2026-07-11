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
