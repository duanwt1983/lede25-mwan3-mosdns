#!/bin/sh
# macOS port of scan-router-exec.ps1. Talks to the router over LuCI ubus.
# Usage: ./scan-router-exec.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=120

DO_FIX=0
if [ "${1:-}" = "--fix" ]; then DO_FIX=1; shift; fi
router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo "=== ROUTER $(hostname) @ $(date) ==="
echo "--- dirs ---"
for d in /etc/init.d /etc/hotplug.d/iface /etc/hotplug.d/net /etc/hotplug.d/dhcp /usr/libexec /usr/libexec/rpcd /usr/sbin; do
  [ -d "$d" ] || continue
  echo "DIR $d"
done
echo "--- missing +x (shebang files) ---"
bad=0
for d in /etc/init.d /etc/hotplug.d/iface /etc/hotplug.d/net /etc/hotplug.d/dhcp /usr/libexec /usr/libexec/rpcd /usr/sbin; do
  [ -d "$d" ] || continue
  find "$d" -type f 2>/dev/null | while read -r f; do
    head -c 2 "$f" 2>/dev/null | grep -q '^#!' || continue
    case "$f" in *.awk) continue ;; esac
    p=$(ls -l "$f" 2>/dev/null | awk '{print $1}')
    echo "$p $f"
    case "$p" in *x*) ;; *) bad=$((bad+1)) ;; esac
  done
done
echo "--- lede/custom scripts sample ---"
for f in \
  /usr/libexec/lede-autolimit /usr/libexec/lede-autolimit-loop /usr/libexec/rpcd/lede-autolimit \
  /usr/libexec/lede-autofix \
  /etc/hotplug.d/net/90-lede-wan-carrier /etc/init.d/lede-autolimit \
  /usr/libexec/wan-alert /etc/init.d/wanalert; do
  [ -e "$f" ] || { echo "MISSING $f"; continue; }
  ls -la "$f"
done
echo "--- ubus rpcd plugins ---"
ubus list 2>/dev/null | grep -E 'lede-autolimit|wanmonitor' || true
echo "--- services ---"
/etc/init.d/wanalert status 2>&1 || true
/etc/init.d/lede-autolimit status 2>&1 || true
END_REMOTE
)"
router_print
if [ "$DO_FIX" = 1 ]; then
router_sh "$(cat <<'END_REMOTE'

echo "=== FIX chmod +x shebang scripts ==="
fixed=0
for d in /etc/init.d /etc/hotplug.d/iface /etc/hotplug.d/net /etc/hotplug.d/dhcp /usr/libexec /usr/libexec/rpcd /usr/sbin; do
  [ -d "$d" ] || continue
  find "$d" -type f 2>/dev/null | while read -r f; do
    head -c 2 "$f" 2>/dev/null | grep -q '^#!' || continue
    case "$f" in *.awk) continue ;; esac
    p=$(ls -l "$f" 2>/dev/null | awk '{print $1}')
    case "$p" in *x*) continue ;; esac
    chmod +x "$f" && echo "FIXED $f" && fixed=$((fixed+1))
  done
done
for f in /usr/libexec/lede-autolimit /usr/libexec/lede-autolimit-loop /usr/libexec/rpcd/lede-autolimit; do
  [ -f "$f" ] && sed -i 's/\r$//' "$f" 2>/dev/null || true
done
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
sleep 2
echo "--- after fix: ubus ---"
ubus list 2>/dev/null | grep -E 'lede-autolimit|wanmonitor' || true
END_REMOTE
)"
router_print
fi
