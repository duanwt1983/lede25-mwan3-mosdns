#!/bin/sh
# macOS port of deploy-lansec.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-lansec.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

# Old-firmware debug only. New images install lede-lansec from files/ overlay.
# Deploy LAN security backend + page. Does not restart network/mosdns/mwan3.

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_put "$ROOT/files/usr/libexec/lede-lansec" '/usr/libexec/lede-lansec'
router_put "$ROOT/files/etc/init.d/lede-lansec" '/etc/init.d/lede-lansec'
router_put "$ROOT/files/etc/hotplug.d/iface/29-lede-lansec" '/etc/hotplug.d/iface/29-lede-lansec'
router_put "$ROOT/files/usr/libexec/wan-alert" '/usr/libexec/wan-alert'
router_put "$ROOT/files/usr/share/ucode/lede-watch.uc" '/usr/share/ucode/lede-watch.uc'
router_put "$ROOT/files/www/luci-static/resources/view/network/lansec.js" '/www/luci-static/resources/view/network/lansec.js'
router_put "$ROOT/files/www/luci-static/resources/view/status/alertlog.js" '/www/luci-static/resources/view/status/alertlog.js'
router_put "$ROOT/files/usr/share/luci/menu.d/luci-lede-lansec.json" '/usr/share/luci/menu.d/luci-lede-lansec.json'
router_put "$ROOT/files/usr/share/rpcd/acl.d/luci-lede-lansec.json" '/usr/share/rpcd/acl.d/luci-lede-lansec.json'
router_put "$ROOT/files/etc/uci-defaults/60-lede-lansec" '/etc/uci-defaults/60-lede-lansec'

router_sh "$(cat <<'END_REMOTE'
chmod 755 /usr/libexec/lede-lansec /etc/init.d/lede-lansec /etc/hotplug.d/iface/29-lede-lansec /usr/libexec/wan-alert
for f in /usr/libexec/lede-lansec /etc/init.d/lede-lansec /etc/hotplug.d/iface/29-lede-lansec /usr/libexec/wan-alert /usr/share/ucode/lede-watch.uc /www/luci-static/resources/view/network/lansec.js /www/luci-static/resources/view/status/alertlog.js; do
  [ -f "$f" ] && sed -i "s/\r$//" "$f"
done
rm -f /tmp/lede-lansec.state /tmp/lede-lansec-evt.json
uci -q get lede-lansec.main.log_page_size >/dev/null || uci set lede-lansec.main.log_page_size=20
while uci -q delete lede-lansec.@nat_allow[0] 2>/dev/null; do :; done
while uci -q delete lede-lansec.@nat_block[0] 2>/dev/null; do :; done
while uci -q delete lede-lansec.@ignore[0] 2>/dev/null; do :; done
uci -q delete lede-lansec.main.nat_enabled
uci -q delete lede-lansec.main.nat_ttl
uci -q delete lede-lansec.main.nat_log
uci -q delete lede-lansec.main.nat_notify
uci commit lede-lansec
/etc/init.d/lede-lansec enable
/etc/init.d/lede-lansec restart
[ -x /etc/init.d/wanalert ] && /etc/init.d/wanalert restart
/usr/libexec/lede-lansec apply
/usr/libexec/lede-lansec prune
rm -f /tmp/lede-lansec-pending.json
sleep 1
echo PREP_OK
ip -4 addr show br-lan 2>/dev/null | awk "/inet /{print \"LAN \" \$2}"
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
echo === files ===
ls -l /usr/libexec/lede-lansec /etc/init.d/lede-lansec
echo === apply ===
/usr/libexec/lede-lansec apply; echo apply=$?
echo === status ===
test -f /tmp/lede-lansec-status.json && cat /tmp/lede-lansec-status.json
echo
echo === nft ===
nft list tables 2>/dev/null | grep lede_lansec || echo no_lansec_table
nft list table inet lede_lansec 2>/dev/null | grep -E 'nat_ttl|ttl set' && echo TTL_STILL_ON || echo TTL_REMOVED
echo === backend ===
grep -c "enabled', '0'" /usr/libexec/lede-lansec
grep -c 'purge_legacy_nat' /usr/libexec/lede-lansec
grep -c 'mac_norm' /usr/libexec/lede-lansec
echo === uci ===
uci show lede-lansec | grep -E 'dhcp_|arp_|nat_|enabled' || true
echo === pending ===
cat /etc/lede-lansec-pending.json 2>/dev/null || echo MISSING
echo === svc ===
pgrep -af lede-lansec || true
echo === lan ===
ip -4 addr show br-lan 2>/dev/null | awk "/inet /{print}"
END_REMOTE
)"
router_print
