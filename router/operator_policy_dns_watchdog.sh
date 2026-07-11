#!/bin/sh
# CODEX_OPERATOR_POLICY_DNS_WATCHDOG
PATH=/fhrom/fhshell:/usr/bin:/usr/sbin:/bin:/sbin:/fhrom/bin
export PATH
BASE=/data/clash/operator_policy_dns
FLAG="$BASE/disabled"
PID=/tmp/codex_operator_policy_dns_watchdog.pid
LOG=/data/clash/logs/operator_policy_dns.log
INTERVAL=${OPDNS_INTERVAL:-30}

echo $$ > "$PID" 2>/dev/null || true
mkdir -p /data/clash/logs "$BASE" 2>/dev/null || true
echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)] operator-policy-dns-watchdog start pid=$$ interval=$INTERVAL" >> "$LOG" 2>/dev/null || true
while true; do
    if [ ! -f "$FLAG" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)] operator-policy-dns marker missing, watchdog exit" >> "$LOG" 2>/dev/null || true
        rm -f "$PID" 2>/dev/null || true
        exit 0
    fi
    [ -x /data/clash/operator_policy_dns.sh ] && /bin/sh /data/clash/operator_policy_dns.sh apply >/dev/null 2>&1 || true
    sleep "$INTERVAL"
done
