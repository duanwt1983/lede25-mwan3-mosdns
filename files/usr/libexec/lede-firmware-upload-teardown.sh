#!/bin/sh
# End firmware upload session: drop /dat bind and restore cgi-io to /tmp.
set -eu
export PATH=/usr/sbin:/sbin:/usr/bin:/bin

. /usr/libexec/lede-firmware-cgi-io.sh

rm -f "$LEDE_FW_UPLOAD_ACTIVE" 2>/dev/null || true

if grep -q ' /dat ' /proc/mounts 2>/dev/null; then
	umount /dat 2>/dev/null || umount -l /dat 2>/dev/null || true
fi

lede_cgi_io_revert_tmp
exit 0
