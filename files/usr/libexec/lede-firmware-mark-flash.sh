#!/bin/sh
# Record pending sysupgrade so the next boot can remove the image and log success.
set -eu

DATA=/data/firmware.bin
PENDING=/data/.lede-fw-flash-pending
SUCCESS=/etc/lede-fw-last-flash-success

[ -f "$DATA" ] || exit 1

old_rev=$(grep DISTRIB_REVISION /etc/openwrt_release 2>/dev/null | cut -d= -f2 | tr -d "'\"")
old_rel=$(grep DISTRIB_RELEASE /etc/openwrt_release 2>/dev/null | cut -d= -f2 | tr -d "'\"")
size=$(wc -c <"$DATA" | tr -d ' ')
sha=$(sha256sum "$DATA" 2>/dev/null | awk '{print $1}')

mkdir -p /data
cat >"$PENDING" <<EOF
started=$(date -Is 2>/dev/null || date)
size=$size
sha256=$sha
old_release=$old_rel
old_revision=$old_rev
EOF

rm -f "$SUCCESS"
: > /tmp/lede-fw-flash.log 2>/dev/null || true
{
	echo "time=$(date -Is 2>/dev/null || date)"
	echo "action=mark_flash_pending"
	echo "image=$DATA size=$size sha256=$sha"
	echo "note=x86 等平台 sysupgrade 阶段通常会 fork dd 写整盘，下方日志来自 logread 与 /proc/*/io"
} >> /tmp/lede-fw-flash.log
exit 0
