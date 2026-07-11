#!/usr/bin/env sh
set -eu
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SSH_IP=${SSH_IP:-192.168.8.1}
SSH_USER=${SSH_USER:-root}
if [ "${SSH_PASSWORD:-}" != "" ]; then
  exec python3 "$DIR/scripts/deploy.py" uninstall --host "$SSH_IP" --user "$SSH_USER" --password "$SSH_PASSWORD" "$@"
else
  exec python3 "$DIR/scripts/deploy.py" uninstall --host "$SSH_IP" --user "$SSH_USER" "$@"
fi
