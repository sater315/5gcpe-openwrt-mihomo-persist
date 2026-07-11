#!/usr/bin/env sh
set -eu
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SSH_IP=${SSH_IP:-192.168.8.1}
SSH_USER=${SSH_USER:-root}
echo "=== 5GCPE Mihomo one-click deploy ==="
echo "Target: $SSH_USER@$SSH_IP"
echo "Bundled resource: resources/mihomo-linux-arm64-v1.19.28.gz"
python3 -c 'import paramiko' 2>/dev/null || python3 -m pip install --user paramiko
if [ "${SSH_PASSWORD:-}" != "" ]; then
  exec python3 "$DIR/scripts/deploy.py" install --host "$SSH_IP" --user "$SSH_USER" --password "$SSH_PASSWORD" --wait-timeout 120 "$@"
else
  exec python3 "$DIR/scripts/deploy.py" install --host "$SSH_IP" --user "$SSH_USER" --wait-timeout 120 "$@"
fi
