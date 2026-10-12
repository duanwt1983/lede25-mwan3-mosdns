#!/bin/bash
# Upload a component pack to a gateway and apply via SSH (bypasses LuCI upload/cgi-upload).
# Usage: ./scripts/dev/push-component-pack.sh [router-ip] [password] [pack.tar.gz]
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
IP="${1:-192.168.8.1}"
PASS="${2:-password}"
PACK="${3:-$ROOT/dist/lede-component-center-hub-v1.0.5.tar.gz}"

[ -f "$PACK" ] || { echo "missing pack: $PACK" >&2; exit 1; }

cd "$ROOT/scripts/dev"
# shellcheck source=ubus.sh
. ./ubus.sh
router_open "$IP" "$PASS"
router_put "$PACK" /tmp/lede-component-upload.tar.gz
router_sh 'export PATH=/usr/sbin:/sbin:/usr/bin:/bin
chmod 644 /tmp/lede-component-upload.tar.gz
/usr/libexec/lede-component-apply file /tmp/lede-component-upload.tar.gz
echo "--- state ---"
cat /etc/lede-component-state.json 2>/dev/null || cat /tmp/lede-component-state.json 2>/dev/null
echo
tail -25 /tmp/lede-component-apply.log 2>/dev/null'
router_print result
