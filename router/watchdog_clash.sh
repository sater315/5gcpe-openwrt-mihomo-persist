#!/bin/sh
# CODEX_MIHOMO_WATCHDOG
PATH=/fhrom/fhshell:/usr/bin:/usr/sbin:/bin:/sbin:/fhrom/bin
export PATH
CLASH_DIR=/data/clash
LOG="$CLASH_DIR/logs/watchdog.log"
PID=/tmp/codex_mihomo_watchdog.pid
INTERVAL=${INTERVAL:-60}

echo $$ > "$PID"
mkdir -p "$CLASH_DIR/logs" "$CLASH_DIR/run" 2>/dev/null

echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)] watchdog start pid=$$ interval=$INTERVAL" >> "$LOG"
while true; do
    if [ ! -f "$CLASH_DIR/enabled" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)] enabled flag missing, watchdog exit" >> "$LOG"
        rm -f "$PID" 2>/dev/null
        exit 0
    fi
    /bin/sh "$CLASH_DIR/start_clash.sh" >> "$LOG" 2>&1 || true
    sleep "$INTERVAL"
done
