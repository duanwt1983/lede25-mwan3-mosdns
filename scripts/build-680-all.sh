#!/bin/bash
# Sync overlay to 192.168.6.80 and start incremental build in background.
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/scripts/build-host-680.env"
TARGET="${1:-${BUILD_HOST:-dwt@192.168.6.80}}"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  set -a && . "$ENV_FILE" && set +a
  export SSHPASS
fi

if [ -z "${SSHPASS:-}" ]; then
  echo "Missing SSHPASS. Create $ENV_FILE (see build-host-680.env.example)" >&2
  exit 1
fi

exec "$ROOT/scripts/trigger-remote-incremental.sh" "$TARGET"
