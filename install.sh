#!/usr/bin/env sh
set -eu
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SSH_IP=${SSH_IP:-192.168.8.1}
SSH_USER=${SSH_USER:-root}
RELEASE=${MIHOMO_RELEASE:-${RELEASE:-latest}}
ARGS=""
if [ "${SSH_PASSWORD:-}" != "" ]; then
  exec python3 "$DIR/scripts/deploy.py" install --host "$SSH_IP" --user "$SSH_USER" --password "$SSH_PASSWORD" --release "$RELEASE" "$@"
else
  exec python3 "$DIR/scripts/deploy.py" install --host "$SSH_IP" --user "$SSH_USER" --release "$RELEASE" "$@"
fi
