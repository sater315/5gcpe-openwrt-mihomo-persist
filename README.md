# 5GCPE OpenWrt Mihomo(OpenClash Core) 持久化部署脚本

这个仓库用于在当前 5GCPE / OpenWrt 厂商固件环境中部署 **Mihomo/Clash core**，不把完整 OpenClash LuCI 插件写入 `/usr`、`/etc/init.d` 等不可靠位置。

实际目标：

- 文件全部放在 `/data/clash`，重启不丢失。
- 通过现有 `/data/ssh_persist.sh` 所在的 collectd 持久启动链自启动。
- watchdog 保活，进程退出后自动拉起。
- 提供一键安装、一键卸载，卸载会移除本仓库写入的启动钩子、进程、iptables 链和 `/data/clash`。
- Mihomo 资源固定在本仓库 `resources/`，默认不再拉取上游 latest，避免版本漂移。

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
├── time_sync.sh
├── logs/
├── run/
├── ruleset/
└── ui/
```

默认监听端口：

| 用途 | 地址 |
|---|---|
| HTTP/SOCKS mixed proxy | `192.168.8.1:7890` |
| Mihomo external-controller API | `http://192.168.8.1:9090` |

## 一键安装

## 最傻瓜式用法

Windows PowerShell：

```powershell
git clone https://github.com/sater315/5gcpe-openwrt-mihomo-persist.git
cd 5gcpe-openwrt-mihomo-persist
.\一键部署.ps1
```

或者用英文入口：

```powershell
.\oneclick.ps1
```

执行后只需要输入一次路由器 SSH 密码，然后等待脚本自动完成：

```text
检查 Python
检查/安装 paramiko
校验仓库内固定 Mihomo v1.19.28 资源
上传到 /data/clash
接入 /data/ssh_persist.sh 开机链
启动 Mihomo
等待 7890/9090/controller 就绪
输出部署成功
```

Linux/macOS/Git Bash：

```sh
git clone https://github.com/sater315/5gcpe-openwrt-mihomo-persist.git
cd 5gcpe-openwrt-mihomo-persist
./oneclick.sh
```

### 从 GitHub 克隆后一键部署

```powershell
git clone https://github.com/sater315/5gcpe-openwrt-mihomo-persist.git
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
3. 使用本仓库固定资源 `resources/mihomo-linux-arm64-v1.19.28.gz`，并校验 SHA256。
4. 解压并上传为 `/data/clash/mihomo`。
5. 上传启动/停止/watchdog/service 脚本。
6. 首次安装时上传 `config.example.yaml` 为 `/data/clash/config.yaml`。
7. 在 `/data/ssh_persist.sh` 的 `exit 0` 前插入带标记的自启动钩子。
8. 立即启动 Mihomo 和 watchdog。
9. 自动等待 `7890`、`9090` 和 `http://127.0.0.1:9090/version` 就绪。
10. 输出状态、端口和最近日志。

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
netstat -lntp | grep -E '7890|9090|7874'
tail -n 80 /data/clash/logs/clash.log
```

## 已测试的启动/停止策略

当前 `router/start_clash.sh`、`router/stop_clash.sh`、`router/watchdog_clash.sh` 已按 5GCPE 环境做成幂等方案：

- `start_clash.sh` 可重复执行，不会重复启动多个 Mihomo。
- `service_persist.sh` 可重复执行，不会重复启动多个 watchdog。
- `stop_clash.sh` 可重复执行，即使已经停止也会返回成功。
- 停止时先停 watchdog，再停 Mihomo，避免 watchdog 在停止过程中把进程拉起来。
- 启动/停止使用 `/tmp/codex_mihomo_start.lock`、`/tmp/codex_mihomo_stop.lock` 和 `/tmp/codex_mihomo_stopping` 避免竞态。
- 启动前会校验配置；配置错误时拒绝启动，保留日志。
- 普通模式下只放行 `7890/9090`，不会再放行或监听 `7874`。
- 如果配置里 `tun.enable: false`，启动前会主动清理旧的 Mihomo TUN 残留。
- 停止时会强制清理：
  - `mihomo` TUN 网卡；
  - `ip rule pref 9000/9001/9002/9010`；
  - `ip route table 2022`；
  - `CODEX_MIHOMO_INPUT` iptables 链。

已在设备上完成测试：

```text
普通模式 service_persist 连续启动 3 次：通过，只有 1 个 Mihomo + 1 个 watchdog
普通模式 start_clash 连续启动 3 次：通过，不重复进程
普通模式 stop_clash 连续停止 3 次：通过，无进程、无端口、无 TUN 残留
普通模式 stop/start 循环 2 轮：通过
临时 TUN 配置启动后停止：通过，TUN 网卡和 9000 系列策略路由全部清理
停止后恢复普通模式：通过，7890/9090 正常，7874 不监听，WAN ping 正常
```

## 使用代理

局域网客户端设置：

```text
HTTP proxy:  192.168.8.1:7890
SOCKS proxy: 192.168.8.1:7890
```

## 一键启用 TUN + 分流规则

这台设备已经检测到：

```text
/dev/net/tun 存在
ip / iptables / sysctl 可用
Mihomo v1.19.28 带 with_gvisor
```

所以可以直接启用 Mihomo core 的 TUN 和本地 rule-providers 分流模板，不需要完整 OpenClash LuCI。

Windows PowerShell：

```powershell
.\一键启用TUN分流.ps1
```

英文入口：

```powershell
.\enable-tun-rules.ps1
```

Linux/macOS/Git Bash：

```sh
./enable-tun-rules.sh
```

启用脚本会：

1. 备份路由器当前 `/data/clash/config.yaml` 为 `/data/clash/config.yaml.bak.YYYYmmdd-HHMMSS`。
2. 上传 `config.tun-rules.example.yaml` 为新的 `/data/clash/config.yaml`。
3. 上传本地规则文件到 `/data/clash/ruleset/`。
4. 更新启动脚本，启动前自动确认 `/dev/net/tun`，并打开 `net.ipv4.ip_forward=1`。
5. 重启 Mihomo，等待 `7890`、`9090` 就绪。

启动脚本还会在真正拉起 Mihomo 前调用 `/data/clash/time_sync.sh` 做一次轻量 NTP 校时。
这是给 VLESS REALITY / Vision 节点准备的：REALITY 对系统时钟非常敏感，如果路由器 UTC 时间偏差过大，会出现 `REALITY authentication failed`，表现为节点配置看起来正确但所有代理测速失败。

TUN + 分流模板默认启用：

| 功能 | 默认值 |
|---|---|
| mixed proxy | `0.0.0.0:7890` |
| external-controller | `0.0.0.0:9090` |
| DNS | `0.0.0.0:7874` |
| TUN | `tun.enable: true` |
| TUN stack | `mixed` |
| DNS 模式 | `fake-ip` |
| 规则来源 | `/data/clash/ruleset/*.yaml` |

当前模板默认没有内置真实代理节点，`PROXY` 组默认只有 `DIRECT`：

```text
启用 TUN 后不会因为没有节点而断网；
后续你把自己的代理节点/订阅加进 config.yaml，PROXY 规则才会真正走节点。
```

### VLESS REALITY 节点注意事项

已在这台设备上实测过 VLESS Reality + `xtls-rprx-vision`：

- 普通 mixed-port 模式可用；
- TUN + fake-ip DNS 模式可用；
- LAN、WAN、DNS、controller 在 1-2 分钟临时测试窗口内均正常；
- 测试结束会自动回滚到默认普通代理模式。

关键点是 **系统时钟必须正确**。本机曾出现：

```text
路由器 UTC 比真实 UTC 快 8 小时
Mihomo 日志：REALITY authentication failed
```

校准 UTC 后，同一个节点立即恢复：

```text
REALITY Authentication: true
controller delay: 800ms - 1200ms 左右
本机 curl 通过 192.168.8.1:7890 返回 204/200
```

所以仓库已经加入 `/data/clash/time_sync.sh`，默认每次 Mihomo 冷启动前尝试 NTP 校时。可选开关：

```sh
# 临时禁用启动前校时
MIHOMO_SYNC_TIME=0 /data/clash/start_clash.sh

# 或持久禁用
touch /data/clash/no_time_sync

# 自定义 NTP peer 和单 peer 等待秒数
MIHOMO_NTP_PEERS="ntp.aliyun.com ntp.tencent.com" MIHOMO_NTP_TIMEOUT=8 /data/clash/start_clash.sh
```

## 一键关闭 TUN，恢复普通代理

如果启用 TUN 后想恢复原来的普通 mixed-port 代理模式：

```powershell
.\一键关闭TUN分流.ps1
```

英文入口：

```powershell
.\disable-tun-rules.ps1
```

Linux/macOS/Git Bash：

```sh
./disable-tun-rules.sh
```

它会备份当前配置，然后把 `/data/clash/config.yaml` 恢复为 `config.example.yaml`：

```text
dns.enable: false
tun.enable: false
rules: MATCH,DIRECT
```

## 关闭运营商策略路由和运营商 DNS

这台 5GCPE 默认会使用运营商/厂商网络进程生成的策略路由和 DNS：

```text
ip rule pref 60 lookup 60
ip rule pref 80 lookup 80
ip rule pref 100 from <ccmni-ip> lookup 100
ip rule pref 100 fwmark 0x4000000/0xfc000000 lookup 100
ip rule pref 100 oif ccmniX lookup 100

nameserver 211.138.240.110
nameserver 211.138.245.188
```

仓库提供一键开关，可以把运行态切换为只走 main/default 路由，并把 DNS 改成公共 DNS：

```text
223.5.5.5
119.29.29.29
1.1.1.1
```

关闭运营商策略路由和 DNS：

```powershell
.\一键关闭运营商策略DNS.ps1
```

英文入口：

```powershell
.\disable-operator-policy-dns.ps1
```

查看状态：

```powershell
.\查看运营商策略DNS状态.ps1
```

恢复运营商策略路由和 DNS：

```powershell
.\一键恢复运营商策略DNS.ps1
```

Linux/macOS/Git Bash：

```sh
./disable-operator-policy-dns.sh
./status-operator-policy-dns.sh
./restore-operator-policy-dns.sh
```

关闭后会写入持久标记：

```text
/data/clash/operator_policy_dns/disabled
```

并启动保持进程：

```text
/data/clash/operator_policy_dns_watchdog.sh
```

该 watchdog 每 30 秒检查一次，防止 5G 重拨或厂商进程把 `pref 60/80/100` 和运营商 DNS 写回来。

已测试：

```text
关闭后 ip rule 只剩 local/main/default
DNS 文件变为 223.5.5.5 / 119.29.29.29 / 1.1.1.1
WAN ping 223.5.5.5 正常
dnsmasq 使用公共 DNS 解析
恢复后可回到 pref 60/80/100 + 211.138.* DNS
再关闭后可重新进入公共 DNS + main/default 模式
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

仓库已经附带 `config.tun-rules.example.yaml`，可以通过 `一键启用TUN分流.ps1` 切换到 TUN + DNS + rule-providers 模式。

## 文件说明

| 文件 | 用途 |
|---|---|
| `install.ps1` | Windows 一键安装入口 |
| `uninstall.ps1` | Windows 一键卸载入口 |
| `status.ps1` | Windows 状态查看入口 |
| `deploy.ps1` | Windows 统一一键部署入口，支持 `install/uninstall/status/restart` |
| `oneclick.ps1` | Windows 傻瓜式一键部署入口：自动检查依赖、部署并等待完成 |
| `一键部署.ps1` | 中文傻瓜式入口，调用 `oneclick.ps1` |
| `enable-tun-rules.ps1` / `一键启用TUN分流.ps1` | 一键切换到 TUN + fake-ip DNS + 本地分流规则模板 |
| `disable-tun-rules.ps1` / `一键关闭TUN分流.ps1` | 一键关闭 TUN/DNS 接管，恢复普通 mixed-port 模式 |
| `disable-operator-policy-dns.ps1` / `一键关闭运营商策略DNS.ps1` | 一键删除运行态运营商策略路由，并把 DNS 改为公共 DNS |
| `restore-operator-policy-dns.ps1` / `一键恢复运营商策略DNS.ps1` | 一键恢复运营商策略路由和运营商 DNS |
| `status-operator-policy-dns.ps1` / `查看运营商策略DNS状态.ps1` | 查看运营商策略/DNS 开关状态 |
| `install.sh` | POSIX shell 一键安装入口 |
| `uninstall.sh` | POSIX shell 一键卸载入口 |
| `deploy.sh` | POSIX shell 统一一键部署入口，支持 `install/uninstall/status/restart` |
| `oneclick.sh` | POSIX shell 傻瓜式一键部署入口 |
| `enable-tun-rules.sh` | POSIX shell 启用 TUN + 分流规则入口 |
| `disable-tun-rules.sh` | POSIX shell 关闭 TUN、恢复普通代理入口 |
| `disable-operator-policy-dns.sh` | POSIX shell 关闭运营商策略/DNS 入口 |
| `restore-operator-policy-dns.sh` | POSIX shell 恢复运营商策略/DNS 入口 |
| `status-operator-policy-dns.sh` | POSIX shell 查看运营商策略/DNS 状态入口 |
| `scripts/deploy.py` | 核心部署器，使用 Paramiko SSH；已适配本机 Dropbear 无 SFTP subsystem 的情况，文件通过 SSH stdin 上传 |
| `resources/mihomo-linux-arm64-v1.19.28.gz` | 固定内置 Mihomo arm64 资源 |
| `resources/manifest.json` | 固定资源版本和 SHA256 校验信息 |
| `router/start_clash.sh` | 路由器端启动脚本 |
| `router/stop_clash.sh` | 路由器端停止/清理脚本 |
| `router/watchdog_clash.sh` | 路由器端保活脚本 |
| `router/time_sync.sh` | 路由器端启动前 NTP 校时脚本，避免 REALITY 因系统时间错误认证失败 |
| `router/operator_policy_dns.sh` | 路由器端关闭/恢复/查看运营商策略路由和 DNS |
| `router/operator_policy_dns_watchdog.sh` | 路由器端运营商策略/DNS 持久保持脚本 |
| `router/service_persist.sh` | 被 `/data/ssh_persist.sh` 调用的统一服务入口 |
| `config.example.yaml` | 默认普通代理配置模板，TUN/DNS 关闭 |
| `config.tun-rules.example.yaml` | TUN + fake-ip DNS + 本地 rule-providers 分流模板 |
| `ruleset/*.yaml` | 本地分流规则，部署到 `/data/clash/ruleset/` |

## 固定资源版本

本仓库默认固定使用内置资源：

```text
resources/mihomo-linux-arm64-v1.19.28.gz
```

校验信息在：

```text
resources/manifest.json
```

当前固定版本：

```text
Mihomo v1.19.28
SHA256: 2474450cd1c41dfa53036a54a4e85579f493d3af524d86c3d4b8e2b240b56cd2
```

默认部署不访问 MetaCubeX GitHub release，不会因为上游 latest 变化导致行为变化。

如果将来确实要从上游下载指定版本，可以显式加 `--download`：

```powershell
python .\scripts\deploy.py install --download --release v1.19.28
```

或者使用本地已下载的 core：

```powershell
python .\scripts\deploy.py install --mihomo-file C:\path\to\mihomo-linux-arm64-v1.19.28
```

