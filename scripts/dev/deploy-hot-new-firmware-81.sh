#!/bin/sh
# Hot-sync recent overlay + frpc 0.71 to a running 8.1 gateway (LuCI ubus upload).
# Usage: ./scripts/dev/deploy-hot-new-firmware-81.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=300

IP="${1:-192.168.8.1}"
PASS="${2:-${LEDE_ROUTER_PASS:-password}}"

router_open "$IP" "$PASS"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

put() {
	router_put "$ROOT/files/$1" "/$1" "${3:-}"
}

# Topology / wan-alert CPU fix
put www/luci-static/resources/view/status/index.js
put www/luci-static/resources/view/status/ratechart.js
put usr/share/ucode/lede-bandix.uc
put usr/share/ucode/lede-metrics.uc
put usr/share/ucode/lede-wan.uc
put usr/share/ucode/lede-watch.uc
put usr/libexec/rpcd/wanmonitor 755

# Regional center frpc stack
put usr/libexec/lede-center-frpc 755
put etc/init.d/lede-center-frpc 755
put etc/hotplug.d/iface/35-lede-center-frpc
put etc/config/lede-center
put www/luci-static/resources/view/system/remote-v2.js
# CA import needs curl + openssl on gateway

# Sysupgrade keep / nginx bind fixes (overlay for next upgrade)
put usr/libexec/lede-mgmt-bind 755
put lib/upgrade/keep.d/lede-custom
put etc/uci-defaults/99-custom

FRP_VER=0.71.0
FRP_CACHE="${TMPDIR:-/tmp}/frp_${FRP_VER}_hot"
mkdir -p "$FRP_CACHE"
router_sh 'uname -m'
ARCH=$(router_stdout | tr -d '\r\n')
case "$ARCH" in
x86_64) FRP_ARCH=linux_amd64 ;;
aarch64) FRP_ARCH=linux_arm64 ;;
*)
	echo "unsupported router arch: $ARCH" >&2
	exit 1
	;;
esac
TARBALL="$FRP_CACHE/frp_${FRP_VER}_${FRP_ARCH}.tar.gz"
FRPC_BIN="$FRP_CACHE/frpc"
if [ ! -x "$FRPC_BIN" ]; then
	curl -sfL "https://github.com/fatedier/frp/releases/download/v${FRP_VER}/frp_${FRP_VER}_${FRP_ARCH}.tar.gz" -o "$TARBALL"
	tar -xzf "$TARBALL" -C "$FRP_CACHE" "frp_${FRP_VER}_${FRP_ARCH}/frpc"
	mv "$FRP_CACHE/frp_${FRP_VER}_${FRP_ARCH}/frpc" "$FRPC_BIN"
	chmod 755 "$FRPC_BIN"
fi
router_put "$FRPC_BIN" /usr/bin/frpc 755

router_sh "$(cat <<'END_REMOTE'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
chmod 755 /usr/libexec/lede-center-frpc /usr/libexec/lede-mgmt-bind \
	/usr/libexec/rpcd/wanmonitor /etc/init.d/lede-center-frpc 2>/dev/null || true
/usr/bin/frpc --version 2>/dev/null || true
if [ -x /usr/libexec/lede-center-frpc ] && uci -q get lede-center.main.enabled >/dev/null 2>&1; then
  if [ "$(uci -q get lede-center.main.enabled)" = "1" ]; then
    /usr/libexec/lede-center-frpc apply 2>&1 || true
  fi
fi
[ -x /sbin/luci-clear-cache ] && /sbin/luci-clear-cache 2>/dev/null || true
/etc/init.d/rpcd restart 2>/dev/null || true
sleep 2
/etc/init.d/wanalert restart 2>/dev/null || true
echo HOT_OK
END_REMOTE
)"
router_print verify
