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

mkdir -p "$LOG_DIR" "$RUN_DIR" "$CLASH_DIR/ui" 2>/dev/null

say() { echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)] $*" >> "$LOG"; }

ensure_firewall() {
    command -v iptables >/dev/null 2>&1 || return 0
    iptables -N CODEX_MIHOMO_INPUT 2>/dev/null || true
    iptables -C INPUT -j CODEX_MIHOMO_INPUT 2>/dev/null || iptables -I INPUT 1 -j CODEX_MIHOMO_INPUT 2>/dev/null || true
    iptables -C CODEX_MIHOMO_INPUT -s "$LAN_CIDR" -p tcp --dport "$PROXY_PORT" -j ACCEPT 2>/dev/null || iptables -A CODEX_MIHOMO_INPUT -s "$LAN_CIDR" -p tcp --dport "$PROXY_PORT" -j ACCEPT 2>/dev/null || true
    iptables -C CODEX_MIHOMO_INPUT -s "$LAN_CIDR" -p tcp --dport "$CTRL_PORT" -j ACCEPT 2>/dev/null || iptables -A CODEX_MIHOMO_INPUT -s "$LAN_CIDR" -p tcp --dport "$CTRL_PORT" -j ACCEPT 2>/dev/null || true
    iptables -C CODEX_MIHOMO_INPUT -s "$LAN_CIDR" -p tcp --dport "$DNS_PORT" -j ACCEPT 2>/dev/null || iptables -A CODEX_MIHOMO_INPUT -s "$LAN_CIDR" -p tcp --dport "$DNS_PORT" -j ACCEPT 2>/dev/null || true
    iptables -C CODEX_MIHOMO_INPUT -s "$LAN_CIDR" -p udp --dport "$DNS_PORT" -j ACCEPT 2>/dev/null || iptables -A CODEX_MIHOMO_INPUT -s "$LAN_CIDR" -p udp --dport "$DNS_PORT" -j ACCEPT 2>/dev/null || true
}

ensure_tun() {
    # TUN is required only when config.yaml enables tun.enable=true.
    # Creating /dev/net/tun is harmless in normal mixed-port mode and fixes devices
    # that support TUN in-kernel but do not create the character device at boot.
    modprobe tun 2>/dev/null || true
    if [ ! -c /dev/net/tun ]; then
        mkdir -p /dev/net 2>/dev/null || true
        mknod /dev/net/tun c 10 200 2>/dev/null || true
        chmod 600 /dev/net/tun 2>/dev/null || true
    fi
    sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
}

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

if [ -f "$PID" ]; then
    oldpid=$(cat "$PID" 2>/dev/null)
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
        say "already running pid=$oldpid"
        ensure_firewall
        exit 0
    fi
fi

# Avoid duplicate instances when pid file was lost.
for p in $(pidof mihomo 2>/dev/null); do
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
        echo "$p" > "$PID"
        say "found existing mihomo pid=$p"
        ensure_firewall
        exit 0
    fi
done

ensure_firewall
ensure_tun
ulimit -n 65535 2>/dev/null || true
say "starting mihomo: $BIN -d $CLASH_DIR -f $CONF"
nohup "$BIN" -d "$CLASH_DIR" -f "$CONF" >> "$LOG" 2>&1 &
newpid=$!
echo "$newpid" > "$PID"
sleep 1
if kill -0 "$newpid" 2>/dev/null; then
    say "started pid=$newpid"
    exit 0
fi
say "start failed pid=$newpid"
exit 1
