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

if command -v iptables >/dev/null 2>&1; then
    while iptables -D INPUT -j CODEX_MIHOMO_INPUT 2>/dev/null; do :; done
    iptables -F CODEX_MIHOMO_INPUT 2>/dev/null || true
    iptables -X CODEX_MIHOMO_INPUT 2>/dev/null || true
fi

exit 0
