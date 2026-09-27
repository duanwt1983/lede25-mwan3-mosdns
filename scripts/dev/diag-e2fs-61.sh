#!/bin/sh
# macOS port of diag-e2fs-61.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-e2fs-61.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

router_open "${1:-192.168.6.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
for t in resize2fs e2fsck mkfs.ext4 tune2fs dumpe2fs; do echo -n "$t="; command -v $t || echo MISSING; done
find /usr /sbin -name 'resize2fs' 2>/dev/null
opkg files e2fsprogs 2>/dev/null | grep resize || true
opkg list | grep -i resize || true
END_REMOTE
)"
router_print
