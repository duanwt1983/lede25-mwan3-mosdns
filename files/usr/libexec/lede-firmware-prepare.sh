#!/bin/sh
# Expose /data/firmware.bin as /tmp/firmware.bin via bind mount.
# Never truncate DATA: if umount fails, : > TMP would wipe the image on /data.
set -eu

DATA=/data/firmware.bin
TMP=/tmp/firmware.bin

[ -f "$DATA" ] || {
	echo "missing $DATA" >&2
	exit 1
}

ds=$(ls -ln "$DATA" 2>/dev/null | awk '{print $5; exit}')
[ -n "$ds" ] || ds=0
if [ "$ds" -lt 33554432 ]; then
	echo "image too small or truncated: $DATA size=$ds" >&2
	exit 1
fi

_is_bind() {
	grep -q " $TMP " /proc/mounts 2>/dev/null
}

if _is_bind; then
	ts=$(ls -ln "$TMP" 2>/dev/null | awk '{print $5; exit}')
	[ -n "$ts" ] || ts=0
	if [ "$ts" = "$ds" ]; then
		ls -lh "$DATA" "$TMP"
		exit 0
	fi
	umount "$TMP" 2>/dev/null || umount -l "$TMP" 2>/dev/null || true
fi

if _is_bind; then
	echo "cannot unmount $TMP (in use); leave existing bind" >&2
	ls -lh "$DATA" "$TMP"
	exit 0
fi

rm -f /tmp/sysupgrade.img /tmp/image.bs 2>/dev/null || true
rm -f "$TMP" 2>/dev/null || true
: >"$TMP"
mount --bind "$DATA" "$TMP"
ls -lh "$DATA" "$TMP"
