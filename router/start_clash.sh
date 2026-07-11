#!/bin/sh
# CODEX_MIHOMO_START
PATH=/fhrom/fhshell:/usr/bin:/usr/sbin:/bin:/sbin:/fhrom/bin
LD_LIBRARY_PATH=/lib:/lib/gpl:/lib64/gpl:/lib64:/usr/lib:/fhrom/lib:/usr/lib/glib-2.0
export PATH LD_LIBRARY_PATH

CLASH_DIR=/data/clash
BIN="$CLASH_DIR/mihomo"
CONF="$CLASH_DIR/config.yaml"
LOG_DIR="$CLASH_DIR/logs"
RUN_DIR="$CLASH_DIR/run"
LOG="$LOG_DIR/clash.log"
PID="$RUN_DIR/mihomo.pid"
ENABLED="$CLASH_DIR/enabled"
LAN_CIDR=${LAN_CIDR:-192.168.8.0/24}
PROXY_PORT=${PROXY_PORT:-7890}
CTRL_PORT=${CTRL_PORT:-9090}
DNS_PORT=${DNS_PORT:-7874}
LOCK_DIR=/tmp/codex_mihomo_start.lock
STOPPING=/tmp/codex_mihomo_stopping
VALIDATE_CONFIG=${VALIDATE_CONFIG:-1}

mkdir -p "$LOG_DIR" "$RUN_DIR" "$CLASH_DIR/ui" 2>/dev/null

say() { echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)] start: $*" >> "$LOG" 2>/dev/null || true; }

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
        [ "$i" -ge 20 ] && { say "start lock timeout"; exit 1; }
        sleep 1
    done
    echo $$ > "$LOCK_DIR/pid" 2>/dev/null || true
    trap 'rm -rf "$LOCK_DIR" 2>/dev/null || true' EXIT INT TERM
}

section_enabled() {
    section="$1"
    awk -v sec="$section" '
        $0 ~ "^" sec ":[[:space:]]*$" {insec=1; next}
        insec && $0 ~ "^[^[:space:]#][^:]*:" {insec=0}
        insec && $0 ~ "^[[:space:]]*enable:[[:space:]]*true([[:space:]]*(#.*)?)?$" {found=1}
        END {exit found ? 0 : 1}
    ' "$CONF" 2>/dev/null
}

tun_enabled() { section_enabled tun; }
dns_enabled() { section_enabled dns; }

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
}

ensure_firewall() {
    command -v iptables >/dev/null 2>&1 || return 0
    iptables -N CODEX_MIHOMO_INPUT 2>/dev/null || true
    while iptables -D INPUT -j CODEX_MIHOMO_INPUT 2>/dev/null; do :; done
    iptables -I INPUT 1 -j CODEX_MIHOMO_INPUT 2>/dev/null || true
    iptables -F CODEX_MIHOMO_INPUT 2>/dev/null || true
    iptables -A CODEX_MIHOMO_INPUT -s "$LAN_CIDR" -p tcp --dport "$PROXY_PORT" -j ACCEPT 2>/dev/null || true
    iptables -A CODEX_MIHOMO_INPUT -s "$LAN_CIDR" -p tcp --dport "$CTRL_PORT" -j ACCEPT 2>/dev/null || true
    if dns_enabled; then
        iptables -A CODEX_MIHOMO_INPUT -s "$LAN_CIDR" -p tcp --dport "$DNS_PORT" -j ACCEPT 2>/dev/null || true
        iptables -A CODEX_MIHOMO_INPUT -s "$LAN_CIDR" -p udp --dport "$DNS_PORT" -j ACCEPT 2>/dev/null || true
    fi
}

ensure_tun() {
    modprobe tun 2>/dev/null || true
    if [ ! -c /dev/net/tun ]; then
        mkdir -p /dev/net 2>/dev/null || true
        mknod /dev/net/tun c 10 200 2>/dev/null || true
        chmod 600 /dev/net/tun 2>/dev/null || true
    fi
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
}

is_stopping() {
    [ -f "$STOPPING" ] || return 1
    spid=$(cat "$STOPPING" 2>/dev/null)
    if [ -n "$spid" ] && kill -0 "$spid" 2>/dev/null; then
        return 0
    fi
    rm -f "$STOPPING" 2>/dev/null || true
    return 1
}

if is_stopping; then
    say "stop in progress, skip start"
    exit 0
fi

acquire_lock

if [ ! -f "$ENABLED" ]; then
    say "enabled flag missing, skip start"
    exit 0
fi

if [ ! -x "$BIN" ]; then
    say "binary not executable: $BIN"
    exit 1
fi

if [ ! -f "$CONF" ]; then
    say "config missing: $CONF"
    exit 1
fi

if ! tun_enabled; then
    cleanup_tun_state
fi

if [ -f "$PID" ]; then
    oldpid=$(cat "$PID" 2>/dev/null)
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
        say "already running pid=$oldpid"
        ensure_firewall
        exit 0
    fi
fi

first=''
for p in $(pidof mihomo 2>/dev/null); do
    if [ -z "$first" ]; then
        first="$p"
        echo "$p" > "$PID" 2>/dev/null || true
    else
        kill "$p" 2>/dev/null || true
    fi
done
if [ -n "$first" ] && kill -0 "$first" 2>/dev/null; then
    say "found existing mihomo pid=$first"
    ensure_firewall
    exit 0
fi

if [ "$VALIDATE_CONFIG" = "1" ]; then
    say "validating config: $CONF"
    if ! "$BIN" -t -d "$CLASH_DIR" -f "$CONF" >> "$LOG" 2>&1; then
        say "config validation failed, refuse to start"
        exit 1
    fi
fi

ensure_firewall
if tun_enabled; then
    cleanup_tun_state
    ensure_tun
fi
ulimit -n 65535 2>/dev/null || true
say "starting mihomo: $BIN -d $CLASH_DIR -f $CONF"
nohup "$BIN" -d "$CLASH_DIR" -f "$CONF" >> "$LOG" 2>&1 &
newpid=$!
echo "$newpid" > "$PID"
sleep 2
if kill -0 "$newpid" 2>/dev/null; then
    say "started pid=$newpid"
    exit 0
fi
say "start failed pid=$newpid"
rm -f "$PID" 2>/dev/null || true
exit 1
