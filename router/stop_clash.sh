#!/bin/sh
# CODEX_MIHOMO_STOP
PATH=/fhrom/fhshell:/usr/bin:/usr/sbin:/bin:/sbin:/fhrom/bin
export PATH

CLASH_DIR=/data/clash
RUN_DIR="$CLASH_DIR/run"
PID="$RUN_DIR/mihomo.pid"
WDPID=/tmp/codex_mihomo_watchdog.pid
LOG="$CLASH_DIR/logs/clash.log"

say() {
    mkdir -p "$CLASH_DIR/logs" 2>/dev/null
    echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)] stop: $*" >> "$LOG" 2>/dev/null || true
}

cleanup_tun_state() {
    command -v ip >/dev/null 2>&1 || return 0
    # Mihomo TUN auto-route uses table 2022 and preferences around 9000.
    # Remove them on stop so disabling TUN immediately restores normal routing.
    for i in 1 2 3 4 5; do
        ip rule del pref 9000 2>/dev/null || true
        ip rule del pref 9001 2>/dev/null || true
        ip rule del pref 9002 2>/dev/null || true
        ip rule del pref 9010 2>/dev/null || true
    done
    ip route flush table 2022 2>/dev/null || true
    ip link set mihomo down 2>/dev/null || true
    ip link del mihomo 2>/dev/null || true
    say "mihomo tun policy route cleanup done"
}

if [ -f "$WDPID" ]; then
    w=$(cat "$WDPID" 2>/dev/null)
    [ -n "$w" ] && kill "$w" 2>/dev/null || true
    rm -f "$WDPID" 2>/dev/null || true
    say "watchdog stopped pid=$w"
fi

if [ -f "$PID" ]; then
    p=$(cat "$PID" 2>/dev/null)
    [ -n "$p" ] && kill "$p" 2>/dev/null || true
    i=0
    while [ -n "$p" ] && kill -0 "$p" 2>/dev/null && [ "$i" -lt 6 ]; do
        sleep 1
        i=$((i + 1))
    done
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null || true
    rm -f "$PID" 2>/dev/null || true
    say "mihomo stopped pid=$p"
fi

for p in $(pidof mihomo 2>/dev/null); do
    [ -n "$p" ] && kill "$p" 2>/dev/null || true
    i=0
    while [ -n "$p" ] && kill -0 "$p" 2>/dev/null && [ "$i" -lt 6 ]; do
        sleep 1
        i=$((i + 1))
    done
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null && kill -9 "$p" 2>/dev/null || true
    say "extra mihomo killed pid=$p"
done

cleanup_tun_state

if command -v iptables >/dev/null 2>&1; then
    while iptables -D INPUT -j CODEX_MIHOMO_INPUT 2>/dev/null; do :; done
    iptables -F CODEX_MIHOMO_INPUT 2>/dev/null || true
    iptables -X CODEX_MIHOMO_INPUT 2>/dev/null || true
fi

exit 0
