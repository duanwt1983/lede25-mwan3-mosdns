#!/bin/sh
# Boot / post-/data: ensure dirs exist; undo stale /dat bind + cgi-io patch from kept overlay.
set -eu
export PATH=/usr/sbin:/sbin:/usr/bin:/bin

. /usr/libexec/lede-firmware-cgi-io.sh

mode=${1:-boot}

mkdir -p /dat
chmod 755 /dat 2>/dev/null || true

if grep -q ' /data ' /proc/mounts 2>/dev/null; then
	mkdir -p /data/nginx-body /data/cgi-tmp
	chmod 700 /data/nginx-body /data/cgi-tmp 2>/dev/null || true
fi

if [ -f "$LEDE_FW_UPLOAD_ACTIVE" ]; then
	exit 0
fi

if grep -q ' /dat ' /proc/mounts 2>/dev/null; then
	umount /dat 2>/dev/null || umount -l /dat 2>/dev/null || true
fi

lede_cgi_io_revert_tmp
exit 0
