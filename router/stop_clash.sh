#!/bin/sh
# CODEX_MIHOMO_STOP
PATH=/fhrom/fhshell:/usr/bin:/usr/sbin:/bin:/sbin:/fhrom/bin
export PATH

CLASH_DIR=/data/clash
RUN_DIR="$CLASH_DIR/run"
PID="$RUN_DIR/mihomo.pid"
WDPID=/tmp/codex_mihomo_watchdog.pid
LOG="$CLASH_DIR/logs/clash.log"
STOPPING=/tmp/codex_mihomo_stopping
LOCK_DIR=/tmp/codex_mihomo_stop.lock

say() {
    mkdir -p "$CLASH_DIR/logs" 2>/dev/null
    echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)] stop: $*" >> "$LOG" 2>/dev/null || true
}

acquire_lock() {
    i=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        lockpid=''
        [ -f "$LOCK_DIR/pid" ] && lockpid=$(cat "$LOCK_DIR/pid" 2>/dev/null)
        if [ -n "$lockpid" ] && ! kill -0 "$lockpid" 2>/dev/null; then
            rm -rf "$LOCK_DIR" 2>/dev/null || true
            continue
        fi
        i=$((i + 1))
        [ "$i" -ge 20 ] && { say "stop lock timeout"; exit 1; }
        sleep 1
    done
    echo $$ > "$LOCK_DIR/pid" 2>/dev/null || true
    echo $$ > "$STOPPING" 2>/dev/null || true
    trap 'rm -f "$STOPPING" 2>/dev/null || true; rm -rf "$LOCK_DIR" 2>/dev/null || true' EXIT INT TERM
}

cleanup_tun_state() {
    command -v ip >/dev/null 2>&1 || return 0
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

cleanup_firewall() {
    command -v iptables >/dev/null 2>&1 || return 0
    while iptables -D INPUT -j CODEX_MIHOMO_INPUT 2>/dev/null; do :; done
    iptables -F CODEX_MIHOMO_INPUT 2>/dev/null || true
    iptables -X CODEX_MIHOMO_INPUT 2>/dev/null || true
    say "firewall cleanup done"
}

kill_and_wait() {
    sig="$1"
    shift
    for p in "$@"; do
        [ -n "$p" ] && kill -"$sig" "$p" 2>/dev/null || true
    done
}

wait_gone() {
    p="$1"
    limit="$2"
    i=0
    while [ -n "$p" ] && kill -0 "$p" 2>/dev/null && [ "$i" -lt "$limit" ]; do
        sleep 1
        i=$((i + 1))
    done
    ! kill -0 "$p" 2>/dev/null
}

acquire_lock
say "begin"

# Stop watchdog first to avoid auto-restart while stopping.
watchdogs=''
[ -f "$WDPID" ] && watchdogs="$watchdogs $(cat "$WDPID" 2>/dev/null)"
for p in $(ps 2>/dev/null | awk '/[w]atchdog_clash/ {print $1}'); do
    watchdogs="$watchdogs $p"
done
for w in $watchdogs; do
    [ -n "$w" ] && kill "$w" 2>/dev/null || true
done
sleep 1
for w in $watchdogs; do
    [ -n "$w" ] && kill -9 "$w" 2>/dev/null || true
done
rm -f "$WDPID" /tmp/codex_mihomo_watchdog.out 2>/dev/null || true
say "watchdog stopped"

pids=''
[ -f "$PID" ] && pids="$pids $(cat "$PID" 2>/dev/null)"
for p in $(pidof mihomo 2>/dev/null); do
    pids="$pids $p"
done

# Graceful first, hard kill only if needed.
for p in $pids; do
    [ -n "$p" ] && kill "$p" 2>/dev/null || true
done
for p in $pids; do
    wait_gone "$p" 8 || true
done
for p in $pids; do
    [ -n "$p" ] && kill -9 "$p" 2>/dev/null || true
done
sleep 1
for p in $(pidof mihomo 2>/dev/null); do
    kill -9 "$p" 2>/dev/null || true
done
rm -f "$PID" 2>/dev/null || true
say "mihomo stopped"

cleanup_tun_state
cleanup_firewall
say "done"
exit 0
