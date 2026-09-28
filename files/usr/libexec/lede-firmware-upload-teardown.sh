#!/bin/sh
# End firmware upload session: restore /tmp tmpfs size (if we grew it).
set -eu
export PATH=/usr/sbin:/sbin:/usr/bin:/bin

LEDE_FW_UPLOAD_ACTIVE=/var/run/lede-fw-upload-active
LEDE_FW_TMP_PREV=/var/run/lede-fw-upload-tmp-prev-kb

rm -f "$LEDE_FW_UPLOAD_ACTIVE" 2>/dev/null || true

if [ -f "$LEDE_FW_TMP_PREV" ]; then
	prev_kb=$(cat "$LEDE_FW_TMP_PREV" 2>/dev/null)
	rm -f "$LEDE_FW_TMP_PREV"
	if [ -n "$prev_kb" ]; then
		mount -o remount,size="${prev_kb}k" /tmp 2>/dev/null || \
			mount -o remount /tmp 2>/dev/null || true
	fi
fi

exit 0
