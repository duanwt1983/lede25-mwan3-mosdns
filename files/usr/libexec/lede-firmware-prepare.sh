#!/bin/sh
# Avoid sysupgrade copying a multi-GB image into small tmpfs (/tmp).
# Upload lands on /data; expose the same file as /tmp/firmware.bin via bind mount.
set -eu

DATA=/data/firmware.bin
TMP=/tmp/firmware.bin

rm -f /tmp/sysupgrade.img /tmp/image.bs 2>/dev/null || true
umount "$TMP" 2>/dev/null || true
rm -f "$TMP" 2>/dev/null || true

[ -f "$DATA" ] || {
	echo "missing $DATA" >&2
	exit 1
}

: >"$TMP"
mount --bind "$DATA" "$TMP"
ls -lh "$DATA" "$TMP"
