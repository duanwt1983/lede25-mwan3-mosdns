#!/bin/sh
# macOS port of deploy-safe-module-fixes.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-safe-module-fixes.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

# Sync display/accounting/safety fixes to 192.168.8.1.
# Does not restart network, firewall, mosdns, or mwan3.

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_put "$ROOT/files/usr/share/ucode/lede-bandix.uc" '/usr/share/ucode/lede-bandix.uc'
router_put "$ROOT/files/usr/libexec/rpcd/wanmonitor" '/usr/libexec/rpcd/wanmonitor'
router_put "$ROOT/files/usr/share/ucode/lede-autolimit.uc" '/usr/share/ucode/lede-autolimit.uc'
router_put "$ROOT/files/usr/share/ucode/lede-watch.uc" '/usr/share/ucode/lede-watch.uc'
router_put "$ROOT/files/usr/libexec/wan-alert" '/usr/libexec/wan-alert'
router_put "$ROOT/files/www/luci-static/resources/view/status/wanalert-page.js" '/www/luci-static/resources/view/status/wanalert-page.js'
router_put "$ROOT/files/usr/libexec/packet-cap" '/usr/libexec/packet-cap'
router_put "$ROOT/files/www/luci-static/resources/view/network/packetcap.js" '/www/luci-static/resources/view/network/packetcap.js'
router_put "$ROOT/files/www/luci-static/resources/view/status/index.js" '/www/luci-static/resources/view/status/index.js'

router_sh "$(cat <<'END_REMOTE'
chmod 755 /usr/libexec/rpcd/wanmonitor /usr/libexec/wan-alert /usr/libexec/packet-cap
for f in \
  /usr/share/ucode/lede-bandix.uc \
  /usr/libexec/rpcd/wanmonitor \
  /usr/share/ucode/lede-autolimit.uc \
  /usr/share/ucode/lede-watch.uc \
  /usr/libexec/wan-alert \
  /www/luci-static/resources/view/status/wanalert-page.js \
  /usr/libexec/packet-cap \
  /www/luci-static/resources/view/network/packetcap.js \
  /www/luci-static/resources/view/status/index.js
do
  [ -f "$f" ] && sed -i "s/\r$//" "$f"
done
rmdir /tmp/wan-alert.lock 2>/dev/null || true
/etc/init.d/lede-autolimit reload >/dev/null 2>&1 || /etc/init.d/lede-autolimit restart >/dev/null 2>&1 || true
/etc/init.d/wanalert restart
echo PREP_OK
ip -4 addr show br-lan 2>/dev/null | awk "/inet /{print \"LAN \" \$2}"
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
/etc/init.d/rpcd restart
END_REMOTE
)"
router_print
sleep 3
router_open "$ROUTER_IP" "$ROUTER_PASS"
echo RELOGIN_OK
router_sh "$(cat <<'END_REMOTE'
echo === markers ===
grep -c "bplus_iface_is_lan" /usr/share/ucode/lede-bandix.uc
grep -c "all_down_sent" /usr/share/ucode/lede-watch.uc
grep -c "overlay_hit" /usr/share/ucode/lede-watch.uc
grep -c "function alert_log_path" /usr/libexec/wan-alert
grep -c "MAX_CAP_SEC" /usr/libexec/packet-cap
grep -c "_pollIv" /www/luci-static/resources/view/status/index.js
grep -c "lede-log" /www/luci-static/resources/view/status/wanalert-page.js
grep -c "bandix_list_schedules" /usr/share/ucode/lede-autolimit.uc
echo === sizes ===
wc -c /usr/share/ucode/lede-bandix.uc /usr/libexec/rpcd/wanmonitor /usr/share/ucode/lede-autolimit.uc /usr/share/ucode/lede-watch.uc /usr/libexec/wan-alert /usr/libexec/packet-cap /www/luci-static/resources/view/status/index.js /www/luci-static/resources/view/status/wanalert-page.js /www/luci-static/resources/view/network/packetcap.js
echo === services ===
pgrep -af "wan-alert|lede-autolimit" || true
ubus list 2>/dev/null | grep -E "wanmonitor|lede-autolimit" || true
echo === lan ===
ip -4 addr show br-lan 2>/dev/null | awk "/inet /{print}"
ubus call network.interface.lan status 2>/dev/null | grep -E "\"up\"|\"address\"" | head -n 8 || true
echo === pulse ===
ubus call wanmonitor pulse 2>/dev/null | head -c 400; echo
END_REMOTE
)"
router_print
