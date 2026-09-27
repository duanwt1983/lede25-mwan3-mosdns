#!/bin/sh
# Hot-deploy Samba4 overlay (no firmware rebuild). Same files as files/ in this repo.
#
# Usage:
#   ./scripts/dev/deploy-samba4-overlay.sh [router-ip] [password]
#
# Requires: curl, jq, python3 (LuCI ubus). Or set USE_SSH=1 and sshpass for plain SCP.

set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
IP="${1:-192.168.9.1}"
PASS="${2:-password}"

FILES="
usr/libexec/lede-samba-policy
usr/libexec/lede-samba-sync
etc/init.d/lede-samba-policy
etc/init.d/lede-samba-sync
etc/init.d/samba4
etc/hotplug.d/block/20-smb
etc/hotplug.d/block/21-lede-samba-policy
www/luci-static/resources/view/samba4.js
usr/share/ucitrack/luci-app-samba4.json
www/luci-static/resources/view/system/flash.js
usr/share/luci/menu.d/zzz-lede-flash-menu.json
usr/share/rpcd/acl.d/zzz-lede-flash-acl.json
usr/libexec/lede-component-apply
usr/libexec/lede-component-list-packs
usr/libexec/rpcd/lede-component
"

put_one() {
	local rel=$1 dest=$2
	[ -f "$ROOT/files/$rel" ] || { echo "missing $ROOT/files/$rel" >&2; return 1; }
	if [ "${USE_SSH:-0}" = 1 ]; then
		SSHPASS=$PASS sshpass -e scp -o PubkeyAuthentication=no \
			-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
			"$ROOT/files/$rel" "root@${IP}:$dest"
	else
		router_put "$ROOT/files/$rel" "$dest"
	fi
}

REMOTE_SETUP=$(cat <<'EOF'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
chmod 755 \
	/usr/libexec/lede-samba-policy \
	/usr/libexec/lede-samba-sync \
	/etc/init.d/lede-samba-policy \
	/etc/init.d/lede-samba-sync \
	/etc/init.d/samba4 \
	/etc/hotplug.d/block/20-smb \
	/etc/hotplug.d/block/21-lede-samba-policy 2>/dev/null || true
/etc/init.d/lede-samba-dedupe disable 2>/dev/null || true
rm -f /usr/libexec/lede-samba-dedupe /etc/init.d/lede-samba-dedupe
/etc/init.d/lede-samba-policy enable 2>/dev/null || true
/etc/init.d/lede-samba-sync enable 2>/dev/null || true
/usr/libexec/lede-samba-policy
# Align UCI enabled with smbd (does not change init.d enable unless you save in LuCI)
/usr/libexec/lede-samba-sync
chmod 755 /usr/libexec/lede-component-apply /usr/libexec/lede-component-list-packs 2>/dev/null || true
/etc/init.d/rpcd restart 2>/dev/null || true
rm -rf /tmp/luci-*cache* 2>/dev/null || true
[ -x /sbin/luci-clear-cache ] && /sbin/luci-clear-cache 2>/dev/null || true
echo "--- verify ---"
echo "uci_enabled=$(uci -q get samba4.@samba[0].enabled 2>/dev/null || echo ?)"
echo "smbd_pids=$(pgrep -x smbd 2>/dev/null | wc -l | tr -d ' ')"
echo "autoshare=$(uci -q get samba4.@samba[0].autoshare 2>/dev/null || echo ?)"
uci -q show samba4 2>/dev/null | grep sambashare || echo "no sambashare sections"
echo DEPLOY_SAMBA_OK
EOF
)

if [ "${USE_SSH:-0}" = 1 ]; then
	command -v sshpass >/dev/null 2>&1 || { echo "need sshpass for USE_SSH=1" >&2; exit 1; }
	for rel in $FILES; do
		put_one "$rel" "/$rel"
	done
	SSHPASS=$PASS sshpass -e ssh -o PubkeyAuthentication=no \
		-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		"root@${IP}" "$REMOTE_SETUP"
else
	# shellcheck disable=SC1091
	. "$HERE/ubus.sh"
	export UBUS_TIMEOUT=120
	router_open "$IP" "$PASS"
	printf 'LOGIN_OK %s\n' "$IP"
	for rel in $FILES; do
		put_one "$rel" "/$rel"
	done
	router_sh "$REMOTE_SETUP"
	router_print
fi

echo "Done. Hard-refresh LuCI. Component upgrades: 系统 → 备份与更新 → 操作."
