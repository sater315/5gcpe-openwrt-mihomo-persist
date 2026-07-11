# 5GCPE OpenWrt Mihomo(OpenClash Core) 持久化部署脚本

这个仓库用于在当前 5GCPE / OpenWrt 厂商固件环境中部署 **Mihomo/Clash core**，不把完整 OpenClash LuCI 插件写入 `/usr`、`/etc/init.d` 等不可靠位置。

实际目标：

- 文件全部放在 `/data/clash`，重启不丢失。
- 通过现有 `/data/ssh_persist.sh` 所在的 collectd 持久启动链自启动。
- watchdog 保活，进程退出后自动拉起。
- 提供一键安装、一键卸载，卸载会移除本仓库写入的启动钩子、进程、iptables 链和 `/data/clash`。

> 本方案不是完整 LuCI 版 OpenClash；它是更适合这台设备的 Mihomo core 持久化部署。默认只开启普通 HTTP/SOCKS mixed 代理端口和 external-controller，不启用 TUN/透明代理/DNS 劫持。

## 已按你的设备做过的关键适配

根据 SSH 探测结果：

| 项目 | 实测值 |
|---|---|
| SSH | `root@192.168.8.1:22` |
| 系统 | OpenWrt 21.02.7，Linux 5.4.238 |
| 架构 | `aarch64` / `aarch64_cortex-a55_neon-vfpv4` |
| 持久分区 | `/data` ext4，可写，约 2.2G 可用 |
| 根文件系统 | `/dev/root` squashfs 只读 |
| 已有 SSH 持久链 | `/data/config/collectd` -> `/data/collectd/uptime.so` -> `/data/ssh_persist.sh` |
| TUN 设备 | `/dev/net/tun` 存在 |
| iptables | nat/mangle/filter 可用，存在 REDIRECT/MARK 相关模块 |

默认部署目录：

```text
/data/clash/
├── mihomo
├── config.yaml
├── enabled
├── start_clash.sh
├── stop_clash.sh
├── watchdog_clash.sh
├── logs/
├── run/
└── ui/
```

默认监听端口：

| 用途 | 地址 |
|---|---|
| HTTP/SOCKS mixed proxy | `192.168.8.1:7890` |
| Mihomo external-controller API | `http://192.168.8.1:9090` |

## 一键安装

### 从 GitHub 克隆后一键部署

```powershell
git clone <YOUR_GITHUB_REPO_URL>
cd 5gcpe-openwrt-mihomo-persist
.\deploy.ps1
```

如需指定设备地址：

```powershell
.\deploy.ps1 -Action install -SSH_IP 192.168.8.1 -SSH_USER root
```

脚本会询问 SSH 密码；密码只在当前部署进程中使用，不会写入 git 仓库。

### 本地仓库直接部署

PowerShell：

```powershell
cd C:\Users\ghkjg\Documents\Codex\2026-07-11\5gcpe-openwrt-openclash-git-ssh-ip
.\deploy.ps1
```

或显式传参；未传 `SSH_PASSWORD` 时会交互式询问，不会把密码写入仓库：

```powershell
.\deploy.ps1 -Action install -SSH_IP 192.168.8.1 -SSH_USER root
```

如需无人值守安装，可只在当前终端会话设置环境变量：

```powershell
$env:SSH_PASSWORD = '<your-router-ssh-password>'
.\deploy.ps1 -Action install -SSH_IP 192.168.8.1 -SSH_USER root
```

Linux/macOS/Git Bash：

```sh
./deploy.sh install
```

安装脚本会：

1. 用 SSH 登录路由器。
2. 检查 `/data`、架构、`/data/ssh_persist.sh`。
3. 下载 GitHub 最新稳定版 `mihomo-linux-arm64-*.gz` 到本机 `.cache/`。
4. 解压并上传为 `/data/clash/mihomo`。
5. 上传启动/停止/watchdog/service 脚本。
6. 首次安装时上传 `config.example.yaml` 为 `/data/clash/config.yaml`。
7. 在 `/data/ssh_persist.sh` 的 `exit 0` 前插入带标记的自启动钩子。
8. 立即启动 Mihomo 和 watchdog。
9. 输出状态、端口和最近日志。

## 一键卸载并恢复

PowerShell：

```powershell
.\deploy.ps1 -Action uninstall
```

Linux/macOS/Git Bash：

```sh
./deploy.sh uninstall
```

卸载脚本会：

- 停止 watchdog。
- 停止 Mihomo。
- 删除 `CODEX_MIHOMO_INPUT` iptables 链。
- 从 `/data/ssh_persist.sh` 删除本仓库插入的 `BEGIN/END CODEX_MIHOMO_PERSIST` 启动块。
- 删除本仓库生成的 `/data/service_persist.sh`。
- 删除 `/data/clash`。
- 清理 `/tmp/codex_mihomo*`、`/tmp/codex_service_persist.log`。

默认会保留 `/data/ssh_persist.sh` 的备份文件，便于需要时人工对照。如果要连备份也删掉：

```powershell
python .\scripts\deploy.py uninstall --purge-backups
```

## 查看状态

```powershell
.\deploy.ps1 -Action status
```

或：

```powershell
python .\scripts\deploy.py status
```

路由器上也可以直接查看：

```sh
/data/clash/mihomo -v
ps | grep mihomo
netstat -lntp | grep -E '7890|9090'
tail -n 80 /data/clash/logs/clash.log
```

## 使用代理

局域网客户端设置：

```text
HTTP proxy:  192.168.8.1:7890
SOCKS proxy: 192.168.8.1:7890
```

默认配置是 DIRECT 占位配置，主要用于验证进程、端口和自启动稳定性。要真正走节点，把你的 Mihomo/Clash YAML 写入：

```text
/data/clash/config.yaml
```

然后执行：

```sh
/data/clash/stop_clash.sh
/data/clash/start_clash.sh
```

或者从电脑执行：

```powershell
python .\scripts\deploy.py restart
```

## 配置说明

默认 `config.example.yaml` 做了这些保守设置：

- `mixed-port: 7890`
- `allow-lan: true`
- `external-controller: 0.0.0.0:9090`
- `dns.enable: false`
- `tun.enable: false`
- `rules: MATCH,DIRECT`

也就是第一阶段只做普通代理，不劫持 DNS，不改路由，不启用 TUN。这样对 5G 模块、厂商 Web、TR069/管理进程、LAN DHCP/DNS 的影响最小。

如果之后要启用 TUN/透明代理，建议先确认 `config.yaml` 在普通 mixed 端口模式下能稳定运行，再逐步添加 TUN/DNS/iptables 规则。

## 文件说明

| 文件 | 用途 |
|---|---|
| `install.ps1` | Windows 一键安装入口 |
| `uninstall.ps1` | Windows 一键卸载入口 |
| `status.ps1` | Windows 状态查看入口 |
| `deploy.ps1` | Windows 统一一键部署入口，支持 `install/uninstall/status/restart` |
| `install.sh` | POSIX shell 一键安装入口 |
| `uninstall.sh` | POSIX shell 一键卸载入口 |
| `deploy.sh` | POSIX shell 统一一键部署入口，支持 `install/uninstall/status/restart` |
| `scripts/deploy.py` | 核心部署器，使用 Paramiko SSH；已适配本机 Dropbear 无 SFTP subsystem 的情况，文件通过 SSH stdin 上传 |
| `router/start_clash.sh` | 路由器端启动脚本 |
| `router/stop_clash.sh` | 路由器端停止/清理脚本 |
| `router/watchdog_clash.sh` | 路由器端保活脚本 |
| `router/service_persist.sh` | 被 `/data/ssh_persist.sh` 调用的统一服务入口 |
| `config.example.yaml` | 默认 Mihomo 配置模板 |

## GitHub release 选择

脚本默认通过 GitHub API 获取 MetaCubeX/mihomo 最新稳定 release，然后选择：

```text
mihomo-linux-arm64-<version>.gz
```

也可以固定版本：

```powershell
python .\scripts\deploy.py install --release v1.19.28
```

或者使用本地已下载的 core：

```powershell
python .\scripts\deploy.py install --mihomo-file C:\path\to\mihomo-linux-arm64-v1.19.28
```
