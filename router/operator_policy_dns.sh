#!/bin/sh
# CODEX_OPERATOR_POLICY_DNS
# Disable/restore carrier policy-routing rules and carrier DNS on this 5GCPE.
# Runtime-safe: changes are reversible and stored under /data/clash/operator_policy_dns.

PATH=/fhrom/fhshell:/usr/bin:/usr/sbin:/bin:/sbin:/fhrom/bin
export PATH

BASE=/data/clash/operator_policy_dns
BACKUPS="$BASE/backups"
FLAG="$BASE/disabled"
LAST="$BASE/last_backup"
LOG=/data/clash/logs/operator_policy_dns.log
DNS_SERVERS=${DNS_SERVERS:-"223.5.5.5 119.29.29.29 1.1.1.1"}
OPERATOR_DNS_SERVERS=${OPERATOR_DNS_SERVERS:-"211.138.240.110 211.138.245.188"}
ACTION=${1:-status}

mkdir -p "$BASE" "$BACKUPS" /data/clash/logs /tmp/resolv.conf.d 2>/dev/null || true
say() { echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)] operator-policy-dns: $*" | tee -a "$LOG" 2>/dev/null; }

write_dns_list() {
    f="$1"
    list="$2"
    : > "$f" 2>/dev/null || return 0
    for ns in $list; do echo "nameserver $ns" >> "$f" 2>/dev/null || true; done
}

write_dns_file() {
    write_dns_list "$1" "$DNS_SERVERS"
}

backup_state() {
    TS=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo now)
    BK="$BACKUPS/$TS"
    mkdir -p "$BK" 2>/dev/null || true
    ip rule show > "$BK/ip_rule.txt" 2>/dev/null || true
    ip route show table main > "$BK/route_main.txt" 2>/dev/null || true
    ip route show table 60 > "$BK/route_60.txt" 2>/dev/null || true
    ip route show table 80 > "$BK/route_80.txt" 2>/dev/null || true
    ip route show table 100 > "$BK/route_100.txt" 2>/dev/null || true
    for f in /tmp/resolv.conf /var/resolv.conf /tmp/resolv.conf.d/resolv.conf.auto; do
        [ -f "$f" ] && cp "$f" "$BK/$(echo "$f" | tr / _).bak" 2>/dev/null || true
    done
    echo "$BK" > "$LAST" 2>/dev/null || true
    say "backup=$BK"
}

kill_dnsmasq_hup() {
    pids=$(pidof dnsmasq 2>/dev/null || true)
    [ -n "$pids" ] && kill -HUP $pids 2>/dev/null || true
}

disable_dns() {
    write_dns_file /tmp/resolv.conf
    write_dns_file /var/resolv.conf
    write_dns_file /tmp/resolv.conf.d/resolv.conf.auto
    kill_dnsmasq_hup
}

disable_policy() {
    for i in 1 2 3 4 5; do
        ip rule del pref 60 2>/dev/null || true
        ip rule del pref 80 2>/dev/null || true
        ip rule del pref 100 2>/dev/null || true
    done
}

disable_all() {
    backup_state
    disable_dns
    disable_policy
    echo "disabled $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" > "$FLAG" 2>/dev/null || true
    say "disabled carrier policy rules and DNS"
}

restore_dns_from_backup() {
    # On this 5GCPE, carrier DNS observed from the modem stack is:
    # 211.138.240.110 / 211.138.245.188.  Use explicit carrier DNS on restore
    # because later backups may already contain public DNS after disable mode.
    write_dns_list /tmp/resolv.conf "$OPERATOR_DNS_SERVERS"
    write_dns_list /var/resolv.conf "$OPERATOR_DNS_SERVERS"
    mkdir -p /tmp/resolv.conf.d 2>/dev/null || true
    write_dns_list /tmp/resolv.conf.d/resolv.conf.auto "$OPERATOR_DNS_SERVERS"
    kill_dnsmasq_hup
}

restore_policy_dynamic() {
    WAN_IF=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
    WAN_GW=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')
    WAN_IP=''
    [ -n "$WAN_IF" ] && WAN_IP=$(ip -4 addr show dev "$WAN_IF" 2>/dev/null | awk '/inet /{sub(/\/.*$/,"",$2); print $2; exit}')
    LAN_NET=$(ip -4 route show dev br0 2>/dev/null | awk '/192\.168\./{print $1; exit}')
    [ -z "$LAN_NET" ] && LAN_NET=192.168.8.0/24

    for i in 1 2 3 4 5; do
        ip rule del pref 60 2>/dev/null || true
        ip rule del pref 80 2>/dev/null || true
        ip rule del pref 100 2>/dev/null || true
    done
    ip route flush table 60 2>/dev/null || true
    ip route flush table 80 2>/dev/null || true
    ip route flush table 100 2>/dev/null || true

    ip route add table 60 "$LAN_NET" dev br0 scope link 2>/dev/null || true
    if [ -n "$WAN_GW" ] && [ -n "$WAN_IF" ]; then
        ip route add table 100 default via "$WAN_GW" dev "$WAN_IF" 2>/dev/null || true
    fi
    if [ -n "$WAN_IF" ]; then
        WAN_NET=$(ip route show table main dev "$WAN_IF" scope link 2>/dev/null | awk 'NR==1{print $1; exit}')
        [ -n "$WAN_NET" ] && ip route add table 100 "$WAN_NET" dev "$WAN_IF" scope link 2>/dev/null || true
    fi
    ip route add table 100 "$LAN_NET" dev br0 scope link 2>/dev/null || true

    ip rule add pref 60 lookup 60 2>/dev/null || true
    ip rule add pref 80 lookup 80 2>/dev/null || true
    [ -n "$WAN_IP" ] && ip rule add pref 100 from "$WAN_IP" lookup 100 2>/dev/null || true
    ip rule add pref 100 fwmark 0x4000000/0xfc000000 lookup 100 2>/dev/null || true
    [ -n "$WAN_IF" ] && ip rule add pref 100 oif "$WAN_IF" lookup 100 2>/dev/null || true
}

restore_all() {
    rm -f "$FLAG" 2>/dev/null || true
    restore_dns_from_backup
    restore_policy_dynamic
    say "restored carrier policy rules and DNS"
}

status_all() {
    echo '--- marker ---'
    if [ -f "$FLAG" ]; then cat "$FLAG"; else echo 'operator policy/dns disable marker: OFF'; fi
    echo '--- ip rule ---'
    ip rule show 2>/dev/null || true
    echo '--- route table 60 ---'
    ip route show table 60 2>/dev/null || true
    echo '--- route table 80 ---'
    ip route show table 80 2>/dev/null || true
    echo '--- route table 100 ---'
    ip route show table 100 2>/dev/null || true
    echo '--- dns files ---'
    for f in /tmp/resolv.conf /var/resolv.conf /tmp/resolv.conf.d/resolv.conf.auto; do
        echo "# $f"; cat "$f" 2>/dev/null || true
    done
    echo '--- dnsmasq ---'
    pidof dnsmasq 2>/dev/null || true
    echo '--- sanity ---'
    ping -c 1 -W 2 223.5.5.5 2>&1 | sed -n '1,5p' || true
    nslookup baidu.com 2>&1 | sed -n '1,12p' || true
}

case "$ACTION" in
    disable|off)
        disable_all
        status_all
        ;;
    apply|enforce)
        if [ -f "$FLAG" ]; then
            disable_dns
            disable_policy
            say "enforced disabled carrier policy rules and DNS"
        fi
        ;;
    restore|on)
        restore_all
        status_all
        ;;
    status|*)
        status_all
        ;;
esac
