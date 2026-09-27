#!/bin/sh
# macOS port of deploy-lansec-ui.ps1. Talks to the router over LuCI ubus.
# Usage: ./deploy-lansec-ui.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

# Deploy LAN security LuCI page only. No backend, no network/mosdns/mwan3 restart.
# Old-firmware debug only. New images install lede-lansec from files/ overlay.

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh 'test -s /etc/config/lede-lansec && echo yes || echo no'
if [ "$(router_stdout | tr -d '[:space:]')" != yes ]; then
	router_put "$ROOT/files/etc/config/lede-lansec" /etc/config/lede-lansec
	router_sh 'chmod 600 /etc/config/lede-lansec'
else
	echo 'KEEP existing /etc/config/lede-lansec'
fi

router_put "$ROOT/files/www/luci-static/resources/view/network/lansec.js" '/www/luci-static/resources/view/network/lansec.js'
router_put "$ROOT/files/usr/share/luci/menu.d/luci-lede-lansec.json" '/usr/share/luci/menu.d/luci-lede-lansec.json'
router_put "$ROOT/files/usr/share/rpcd/acl.d/luci-lede-lansec.json" '/usr/share/rpcd/acl.d/luci-lede-lansec.json'
router_put "$ROOT/files/etc/uci-defaults/60-lede-lansec" '/etc/uci-defaults/60-lede-lansec'

router_sh "$(cat <<'END_REMOTE'
test -s /etc/config/lede-lansec && echo yes || echo no
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
/bin/chmod 600
END_REMOTE
)"
router_print
router_sh "$(cat <<'END_REMOTE'
chmod 755 /etc/uci-defaults/60-lede-lansec
for f in \
  /www/luci-static/resources/view/network/lansec.js \
  /usr/share/luci/menu.d/luci-lede-lansec.json \
  /usr/share/rpcd/acl.d/luci-lede-lansec.json \
  /etc/uci-defaults/60-lede-lansec
do
  [ -f "$f" ] && sed -i "s/\r$//" "$f"
done
sh /etc/uci-defaults/60-lede-lansec
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache /tmp/luci-indexcache.* 2>/dev/null || true
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
echo === files ===
ls -l /www/luci-static/resources/view/network/lansec.js /usr/share/luci/menu.d/luci-lede-lansec.json /usr/share/rpcd/acl.d/luci-lede-lansec.json /etc/config/lede-lansec
echo === markers ===
grep -c "lede-lansec" /www/luci-static/resources/view/network/lansec.js
grep -c "admin/network/lansec" /usr/share/luci/menu.d/luci-lede-lansec.json
echo === uci ===
uci -q get lede-lansec.main.enabled
uci -q get lede-lansec.main.dhcp_ban
uci -q get lede-lansec.main.dhcp_notify
uci -q get lede-lansec.main.arp_drop_gw
echo === lan ===
ip -4 addr show br-lan 2>/dev/null | awk "/inet /{print}"
END_REMOTE
)"
router_print
