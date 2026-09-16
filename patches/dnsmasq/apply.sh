#!/bin/sh
# Bump Lean dnsmasq (2.91) to latest stable 2.93 + OpenWrt patches.
set -e
ROOT="${1:-.}"
PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"
MK="$(find "$ROOT/package/network/services/dnsmasq" -name Makefile -type f 2>/dev/null | head -n 1)"
[ -n "$MK" ] || { echo "dnsmasq Makefile not found"; exit 1; }
PKG_DIR="$(dirname "$MK")"

sed -i \
	-e 's/^PKG_UPSTREAM_VERSION:=.*/PKG_UPSTREAM_VERSION:=2.93/' \
	-e 's/^PKG_RELEASE:=.*/PKG_RELEASE:=3/' \
	-e 's/^PKG_HASH:=.*/PKG_HASH:=0c00d4e5c97c8306e5fb932b348b34269c9c29a0e7df0e8e82958b407092bc19/' \
	"$MK"

mkdir -p "$PKG_DIR/patches"
for p in 100-remove-old-runtime-kernel-support.patch 200-ubus_dns.patch; do
	[ -f "$PATCH_DIR/$p" ] || { echo "missing patch: $PATCH_DIR/$p"; exit 1; }
	cp "$PATCH_DIR/$p" "$PKG_DIR/patches/$p"
done

grep -q 'PKG_UPSTREAM_VERSION:=2.93' "$MK" || { echo "dnsmasq version bump failed"; exit 1; }
echo "dnsmasq -> 2.93 ($MK)"
