#!/usr/bin/env sh
set -eu
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CONFIG="$DIR/config.example.yaml"
if [ ! -f "$CONFIG" ]; then
  echo "missing $CONFIG" >&2
  exit 1
fi
echo "=== Disable TUN and restore normal mixed-port proxy ==="
exec "$DIR/deploy.sh" install --config "$CONFIG" --overwrite-config "$@"
