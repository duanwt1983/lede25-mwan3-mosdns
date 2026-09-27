#!/bin/bash
# Patch flash.js for component upgrade + bake overlay LuCI into feed packages.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD="$(cd "${1:-.}" && pwd)"
PATCH="$ROOT/patches/luci-mod-system/patch-flash-component.py"
OUT="$ROOT/files/www/luci-static/resources/view/system/flash.js"
UP="$ROOT/tmp-flash-upstream.js"

if [ ! -f "$OUT" ] || ! grep -q handleLedeComponentUrl "$OUT" 2>/dev/null; then
	SRC=""
	for p in \
		"$UP" \
		"$BUILD/feeds/luci/modules/luci-mod-system/htdocs/luci-static/resources/view/system/flash.js" \
		"$BUILD/package/luci-mod-system/htdocs/luci-static/resources/view/system/flash.js" \
		"$ROOT/../feeds/luci/modules/luci-mod-system/htdocs/luci-static/resources/view/system/flash.js"
	do
		[ -f "$p" ] && SRC=$p && break
	done

	if [ -z "$SRC" ]; then
		echo "luci-mod-system: no upstream flash.js for patch (overlay must ship flash.js)"
	else
		python3 "$PATCH" "$SRC" "$OUT"
		echo "luci-mod-system: patched flash.js -> $OUT"
	fi
else
	echo "luci-mod-system: flash.js overlay OK"
fi

bake_view() {
	local rel="$1" label="$2"
	local src="$ROOT/files/www/luci-static/resources/view/$rel"
	[ -f "$src" ] || { echo "WARN: missing overlay view $src"; return 0; }
	find "$BUILD/feeds" "$BUILD/package" -path "*/view/$rel" -type f 2>/dev/null \
	| while IFS= read -r f; do
		[ -n "$f" ] || continue
		cp "$src" "$f"
		echo "$label: baked $rel -> $f"
	done
}

bake_view "system/flash.js" "luci-mod-system"
bake_view "samba4.js" "luci-app-samba4"

# Samba4 server init + hotplug from overlay (same as rootfs files/)
install_overlay_file() {
	local rel="$1"
	local src="$ROOT/files/$rel"
	[ -f "$src" ] || return 0
	local dest=""
	case "$rel" in
		etc/init.d/samba4)
			dest=$(find "$BUILD/feeds" "$BUILD/package" -path '*/samba4-server/*/init.d/samba4' -type f 2>/dev/null | head -n 1)
			;;
		etc/hotplug.d/block/20-smb)
			dest=$(find "$BUILD/feeds" "$BUILD/package" -path '*/samba4-server/*/hotplug.d/block/20-smb' -type f 2>/dev/null | head -n 1)
			;;
	esac
	if [ -n "$dest" ] && [ -f "$dest" ]; then
		install -m 755 "$src" "$dest"
		echo "samba4-server: baked $rel -> $dest"
	fi
}

install_overlay_file etc/init.d/samba4
install_overlay_file etc/hotplug.d/block/20-smb
