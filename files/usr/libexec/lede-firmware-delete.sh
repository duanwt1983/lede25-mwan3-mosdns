#!/bin/sh
set -eu
umount /tmp/firmware.bin 2>/dev/null || true
rm -f /data/firmware.bin /tmp/firmware.bin /tmp/sysupgrade.img /tmp/image.bs /data/.lede-fw-flash-pending 2>/dev/null || true
exit 0
