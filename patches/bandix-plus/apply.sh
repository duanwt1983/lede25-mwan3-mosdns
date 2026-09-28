#!/bin/bash
# Install LEDE bandix-plus package: source build + count-forwarded-only.patch
set -euo pipefail

OVERLAY="$(cd "$(dirname "$0")/../.." && pwd)"
SELF="$(cd "$(dirname "$0")" && pwd)"
# diy-part2 runs with cwd = OpenWrt TOPDIR (see build-incremental.sh / build-offline.sh).
OWRT="${LEDE_OPENWRT:-$(pwd)}"
PKG="$OWRT/package/bandix-plus"

if [ ! -d "$PKG" ]; then
	echo "ERROR: package/bandix-plus missing under OpenWrt tree ($OWRT)" >&2
	echo "  (run openwrt-bandix-plus clone in diy-part2 first; cwd must be openwrt TOPDIR)" >&2
	exit 1
fi

mkdir -p "$PKG/patches"
install -m 0644 "$SELF/count-forwarded-only.patch" "$PKG/patches/100-count-forwarded-only.patch"
install -m 0755 "$SELF/lede-build-bandix.sh" "$PKG/lede-build-bandix.sh"
install -m 0644 "$SELF/Makefile" "$PKG/Makefile"

grep -Fq 'LEDE_BANDIX_COUNT_FORWARDED' "$PKG/Makefile" || {
	echo "ERROR: bandix-plus Makefile missing LEDE marker" >&2
	exit 1
}
[ -f "$PKG/patches/100-count-forwarded-only.patch" ] || {
	echo "ERROR: bandix-plus eBPF patch not installed" >&2
	exit 1
}

PATCHED_BIN="$PKG/lede-patched/bandix-plus"
STAMP="$PKG/lede-patched/.patch-stamp"
PATCH_MD5=$(md5sum "$SELF/count-forwarded-only.patch" | awk '{print $1}')
BUILD_SCRIPT="$OVERLAY/scripts/build-bandix-plus-patched.sh"
mkdir -p "$PKG/lede-patched"
if [ ! -x "$BUILD_SCRIPT" ]; then
	echo "ERROR: missing $BUILD_SCRIPT" >&2
	exit 1
fi
if [ -f "$PATCHED_BIN" ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$PATCH_MD5" ]; then
	echo "bandix-plus: reusing lede-patched binary (patch unchanged)"
else
	bash "$BUILD_SCRIPT" "$PATCHED_BIN"
	echo "$PATCH_MD5" > "$STAMP"
fi
[ -f "$PATCHED_BIN" ] || { echo "ERROR: bandix-plus patched binary not built" >&2; exit 1; }

echo "bandix-plus: patched build ready (PKG_RELEASE 2, count-forwarded-only)"
