#!/bin/sh
# macOS port of fix-router-exec.ps1. Talks to the router over LuCI ubus.
# Usage: ./fix-router-exec.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo BEFORE; for f in /etc/hotplug.d/iface/28-bandix-plus-restart /etc/hotplug.d/dhcp/30-lede-mwan3-mac /usr/sbin/wan-fail-dump /usr/sbin/wan-fail-watch /usr/libexec/lede-dzbsaas-capture /etc/hotplug.d/net/90-lede-wan-carrier /usr/libexec/lede-autolimit /usr/libexec/rpcd/lede-autolimit; do [ -f "$f" ] && ls -la "$f"; done
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
for d in /etc/init.d /etc/hotplug.d/iface /etc/hotplug.d/net /etc/hotplug.d/dhcp /usr/libexec /usr/libexec/rpcd /usr/sbin; do [ -d "$d" ] || continue; find "$d" -type f 2>/dev/null; done | while read -r f; do head -c 2 "$f" 2>/dev/null | grep -q "^#!" || continue; case "$f" in *.awk) continue;; esac; ls -l "$f" | awk "{print \$1}" | grep -q "^....x" && continue; chmod 755 "$f" && echo FIXED "$f"; done
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
for f in /usr/libexec/lede-autolimit /usr/libexec/lede-autolimit-loop /usr/libexec/rpcd/lede-autolimit; do [ -f "$f" ] && sed -i "s/\\r$//" "$f"; done; echo AFTER; for f in /etc/hotplug.d/iface/28-bandix-plus-restart /etc/hotplug.d/dhcp/30-lede-mwan3-mac /usr/sbin/wan-fail-dump /usr/sbin/wan-fail-watch /usr/libexec/lede-dzbsaas-capture /etc/hotplug.d/net/90-lede-wan-carrier /usr/libexec/lede-autolimit /usr/libexec/rpcd/lede-autolimit; do [ -f "$f" ] && ls -la "$f"; done
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
ubus list 2>/dev/null | grep -E "lede-autolimit|wanmonitor" || true
END_REMOTE
)"
router_print
