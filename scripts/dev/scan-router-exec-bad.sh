#!/bin/sh
# macOS port of scan-router-exec-bad.ps1. Talks to the router over LuCI ubus.
# Usage: ./scan-router-exec-bad.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo "=== 8.1 still broken (no owner +x, shebang) ==="
n=0
for d in /etc/init.d /etc/hotplug.d/iface /etc/hotplug.d/net /etc/hotplug.d/dhcp /usr/libexec /usr/libexec/rpcd /usr/sbin; do
  [ -d "$d" ] || continue
  find "$d" -type f 2>/dev/null | while read -r f; do
    head -c 2 "$f" 2>/dev/null | grep -q '^#!' || continue
    case "$f" in *.awk) continue ;; esac
    p=$(ls -l "$f" | awk '{print $1}')
    echo "$p" | grep -q '^....x' && continue
    echo "BAD $p $f"
    n=$((n+1))
  done
done
echo "=== LEDE custom key files ==="
for f in \
  /etc/hotplug.d/iface/28-bandix-plus-restart \
  /etc/hotplug.d/dhcp/30-lede-mwan3-mac \
  /etc/hotplug.d/net/90-lede-wan-carrier \
  /usr/libexec/lede-autolimit /usr/libexec/rpcd/lede-autolimit \
  /usr/libexec/lede-autofix \
  /usr/sbin/wan-fail-dump /usr/sbin/wan-fail-watch; do
  [ -f "$f" ] && ls -la "$f"
done
END_REMOTE
)"
router_print
