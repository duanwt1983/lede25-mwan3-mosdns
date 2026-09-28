#!/bin/sh
# On-demand prep for multi-GB LuCI cgi-upload → /data/firmware.bin (call before upload/validate).
# Occasional use: grow /tmp tmpfs in RAM for nginx/uWSGI/cgi-io spool; teardown restores size.
set -eu
export PATH=/usr/sbin:/sbin:/usr/bin:/bin

LEDE_FW_UPLOAD_ACTIVE=/var/run/lede-fw-upload-active
LEDE_FW_TMP_PREV=/var/run/lede-fw-upload-tmp-prev-kb

[ -x /usr/libexec/lede-firmware-restore-upgrade.sh ] && \
	/usr/libexec/lede-firmware-restore-upgrade.sh || true

if ! grep -q ' /data ' /proc/mounts 2>/dev/null; then
	echo "lede-firmware-upload-env: /data partition not mounted yet" >&2
	exit 1
fi

for f in /etc/nginx/uci.conf /etc/nginx/uci.conf.template; do
	[ -f "$f" ] || continue
	if grep -q 'client_max_body_size' "$f"; then
		sed -i 's/client_max_body_size[^;]*;/client_max_body_size 0;/g' "$f"
	else
		sed -i '/http {/a\        client_max_body_size 0;' "$f" 2>/dev/null || true
	fi
done

lede_upload_tmpfs_bump() {
	[ -f "$LEDE_FW_TMP_PREV" ] && return 0
	local mt cur_kb target_kb reserve_kb min_kb max_kb
	mt=$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null) || return 0
	[ -n "$mt" ] || return 0
	reserve_kb=$((384 * 1024))
	min_kb=$((2600 * 1024))
	target_kb=$(( mt * 80 / 100 ))
	[ "$target_kb" -ge "$min_kb" ] || target_kb=$min_kb
	max_kb=$(( mt - reserve_kb ))
	[ "$max_kb" -gt "$target_kb" ] || target_kb=$max_kb
	cur_kb=$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $2}')
	[ -n "$cur_kb" ] || return 0
	[ "$target_kb" -gt "$cur_kb" ] || return 0
	echo "$cur_kb" >"$LEDE_FW_TMP_PREV"
	mount -o remount,size="${target_kb}k" /tmp 2>/dev/null || {
		rm -f "$LEDE_FW_TMP_PREV"
		echo "lede-firmware-upload-env: could not grow /tmp tmpfs (need ~2.6G+ RAM headroom)" >&2
		return 1
	}
}

lede_upload_tmpfs_bump

mkdir -p "$(dirname "$LEDE_FW_UPLOAD_ACTIVE")"
: >"$LEDE_FW_UPLOAD_ACTIVE"

/etc/init.d/nginx reload 2>/dev/null || true

rm -f /tmp/sysupgrade.img /tmp/image.bs 2>/dev/null || true
exit 0
