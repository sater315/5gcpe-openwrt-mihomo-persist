#!/usr/bin/env sh
set -eu
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ACTION=${1:-install}
if [ $# -gt 0 ]; then shift; fi
SSH_IP=${SSH_IP:-192.168.8.1}
SSH_USER=${SSH_USER:-root}
RELEASE=${MIHOMO_RELEASE:-${RELEASE:-latest}}
if [ "$ACTION" = "install" ]; then
  if [ "${SSH_PASSWORD:-}" != "" ]; then
    exec python3 "$DIR/scripts/deploy.py" install --host "$SSH_IP" --user "$SSH_USER" --password "$SSH_PASSWORD" --release "$RELEASE" "$@"
  else
    exec python3 "$DIR/scripts/deploy.py" install --host "$SSH_IP" --user "$SSH_USER" --release "$RELEASE" "$@"
  fi
else
  if [ "${SSH_PASSWORD:-}" != "" ]; then
    exec python3 "$DIR/scripts/deploy.py" "$ACTION" --host "$SSH_IP" --user "$SSH_USER" --password "$SSH_PASSWORD" "$@"
  else
    exec python3 "$DIR/scripts/deploy.py" "$ACTION" --host "$SSH_IP" --user "$SSH_USER" "$@"
  fi
fi
