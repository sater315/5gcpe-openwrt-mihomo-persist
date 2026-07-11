#!/bin/sh
# CODEX_MIHOMO_SERVICE
PATH=/fhrom/fhshell:/usr/bin:/usr/sbin:/bin:/sbin:/fhrom/bin
LD_LIBRARY_PATH=/lib:/lib/gpl:/lib64/gpl:/lib64:/usr/lib:/fhrom/lib:/usr/lib/glib-2.0
export PATH LD_LIBRARY_PATH

LOG=/tmp/codex_service_persist.log
CLASH_DIR=/data/clash
WDPID=/tmp/codex_mihomo_watchdog.pid

{
  echo "=== codex service_persist start $(date) ==="
  if [ -x "$CLASH_DIR/start_clash.sh" ]; then
    /bin/sh "$CLASH_DIR/start_clash.sh"
  else
    echo "missing $CLASH_DIR/start_clash.sh"
  fi
  if [ -x "$CLASH_DIR/watchdog_clash.sh" ] && [ -f "$CLASH_DIR/enabled" ]; then
    oldpid=''
    [ -f "$WDPID" ] && oldpid=$(cat "$WDPID" 2>/dev/null)
    if [ -z "$oldpid" ] || ! kill -0 "$oldpid" 2>/dev/null; then
      nohup /bin/sh "$CLASH_DIR/watchdog_clash.sh" >/tmp/codex_mihomo_watchdog.out 2>&1 &
      echo $! > "$WDPID"
      echo "watchdog started $(cat "$WDPID" 2>/dev/null)"
    else
      echo "watchdog already running $oldpid"
    fi
  fi
  echo "=== codex service_persist done $(date) ==="
} >> "$LOG" 2>&1

exit 0
