#!/bin/sh
# Record pending sysupgrade so the next boot can remove the image and log success.
# Must finish in seconds — do NOT sha256 multi-GB images here (LuCI exec will timeout).
set -eu

DATA=/data/firmware.bin
PENDING=/data/.lede-fw-flash-pending
SUCCESS=/etc/lede-fw-last-flash-success

[ -f "$DATA" ] || exit 1

old_rev=$(grep DISTRIB_REVISION /etc/openwrt_release 2>/dev/null | cut -d= -f2 | tr -d "'\"")
old_rel=$(grep DISTRIB_RELEASE /etc/openwrt_release 2>/dev/null | cut -d= -f2 | tr -d "'\"")
size=$(stat -c '%s' "$DATA" 2>/dev/null || ls -ln "$DATA" | awk '{print $5}')

mkdir -p /data
cat >"$PENDING" <<EOF
started=$(date -Is 2>/dev/null || date)
size=$size
sha256=skipped
old_release=$old_rel
old_revision=$old_rev
EOF

rm -f "$SUCCESS"
: > /tmp/lede-fw-flash.log 2>/dev/null || true
: > /data/lede-fw-flash.log 2>/dev/null || true
{
	echo "time=$(date -Is 2>/dev/null || date)"
	echo "action=mark_flash_pending"
	echo "image=$DATA size=$size"
	echo "note=fast mark (no full-image sha256 before sysupgrade)"
} >> /tmp/lede-fw-flash.log
exit 0
