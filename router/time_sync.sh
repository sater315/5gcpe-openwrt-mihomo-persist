#!/bin/sh
# CODEX_MIHOMO_TIME_SYNC
# Mihomo REALITY/VLESS 对系统时钟非常敏感；本 5GCPE 曾出现 UTC 快 8 小时，
# 会导致日志里反复出现 "REALITY authentication failed"。
# 该脚本在启动 Mihomo 前尽量做一次轻量 NTP 校时；失败不阻断启动。

PATH=/fhrom/fhshell:/usr/bin:/usr/sbin:/bin:/sbin:/fhrom/bin
LD_LIBRARY_PATH=/lib:/lib/gpl:/lib64/gpl:/lib64:/usr/lib:/fhrom/lib:/usr/lib/glib-2.0
export PATH LD_LIBRARY_PATH

CLASH_DIR=${CLASH_DIR:-/data/clash}
LOG_DIR="$CLASH_DIR/logs"
LOG="$LOG_DIR/time_sync.log"
DISABLE_FLAG="$CLASH_DIR/no_time_sync"

# 可通过环境变量覆盖：
#   MIHOMO_SYNC_TIME=0              禁用启动前校时
#   MIHOMO_NTP_TIMEOUT=8           每个 NTP peer 最多等待秒数
#   MIHOMO_NTP_PEERS="a b c"       自定义 NTP peer 列表
MIHOMO_SYNC_TIME=${MIHOMO_SYNC_TIME:-1}
MIHOMO_NTP_TIMEOUT=${MIHOMO_NTP_TIMEOUT:-8}
MIHOMO_NTP_PEERS=${MIHOMO_NTP_PEERS:-"ntp.aliyun.com ntp.tencent.com time.cloudflare.com pool.ntp.org"}

mkdir -p "$LOG_DIR" 2>/dev/null || true

say() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)] time_sync: $*" >> "$LOG" 2>/dev/null || true
}

if [ "$MIHOMO_SYNC_TIME" = "0" ]; then
    say "disabled by MIHOMO_SYNC_TIME=0"
    exit 0
fi

if [ -f "$DISABLE_FLAG" ]; then
    say "disabled by $DISABLE_FLAG"
    exit 0
fi

if ! command -v ntpd >/dev/null 2>&1; then
    say "ntpd not found, skip"
    exit 0
fi

before_epoch=$(date +%s 2>/dev/null || echo 0)
before_text=$(date -u 2>/dev/null || date 2>/dev/null || echo unknown)
say "before epoch=$before_epoch utc=$before_text"

for peer in $MIHOMO_NTP_PEERS; do
    [ -n "$peer" ] || continue
    say "try peer=$peer timeout=${MIHOMO_NTP_TIMEOUT}s"

    ntpd -nq -p "$peer" >> "$LOG" 2>&1 &
    npid=$!
    waited=0
    while kill -0 "$npid" 2>/dev/null; do
        if [ "$waited" -ge "$MIHOMO_NTP_TIMEOUT" ]; then
            kill "$npid" 2>/dev/null || true
            wait "$npid" 2>/dev/null || true
            say "peer=$peer timeout"
            break
        fi
        sleep 1
        waited=$((waited + 1))
    done

    if kill -0 "$npid" 2>/dev/null; then
        kill "$npid" 2>/dev/null || true
        wait "$npid" 2>/dev/null || true
        continue
    fi

    wait "$npid" 2>/dev/null
    rc=$?
    after_epoch=$(date +%s 2>/dev/null || echo 0)
    after_text=$(date -u 2>/dev/null || date 2>/dev/null || echo unknown)
    say "peer=$peer rc=$rc after epoch=$after_epoch utc=$after_text"

    if [ "$rc" = "0" ]; then
        say "sync ok peer=$peer"
        exit 0
    fi
done

say "all peers failed; continue without blocking mihomo"
exit 0
