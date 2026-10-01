#!/bin/bash
# Open frps tunnel ports on the center host (19100–19999/tcp). Safe to re-run.
set -euo pipefail

RANGE="${1:-19100-19999/tcp}"

if ! command -v firewall-cmd >/dev/null 2>&1; then
  echo "firewall-cmd not found; skip (no firewalld)" >&2
  exit 0
fi

if ! firewall-cmd --state >/dev/null 2>&1; then
  echo "firewalld not running; skip" >&2
  exit 0
fi

if firewall-cmd --permanent --query-port="$RANGE" 2>/dev/null; then
  echo "Already open: $RANGE"
else
  firewall-cmd --permanent --add-port="$RANGE"
  echo "Added permanent port: $RANGE"
fi

firewall-cmd --reload
firewall-cmd --query-port="$RANGE"
echo "frp tunnel ports OK"
