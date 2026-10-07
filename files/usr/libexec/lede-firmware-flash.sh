#!/bin/sh
# Copy image into RAM tmpfs, then sysupgrade that copy.
# Image on /data lives on the boot disk — dd of=/dev/sda cannot read from sda3.
set -eu
export PATH=/usr/sbin:/sbin:/usr/bin:/bin

LOG=/tmp/lede-fw-flash.log
PIDFILE=/var/run/lede-fw-flash.pid
DATA_IMAGE=/data/firmware.bin
RAM_IMAGE=/tmp/sysupgrade.img
save=1
force=0

for arg in "$@"; do
	case "$arg" in
		-n) save=0 ;;
		--force) force=1 ;;
	esac
done

[ -f "$DATA_IMAGE" ] || {
	echo "missing $DATA_IMAGE" >&2
	exit 1
}

log() { echo "$*" >>"$LOG"; }

lede_flash_grow_tmp() {
	local img_kb need_kb mt target_kb reserve_kb max_kb cur_kb
	img_kb=$(du -k "$DATA_IMAGE" 2>/dev/null | awk '{print $1}')
	[ -n "$img_kb" ] || img_kb=0
	need_kb=$((img_kb + 262144))
	mt=$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null) || mt=0
	[ "$mt" -gt 0 ] || {
		log "LEDE_FW_COPY_FAIL no MemTotal"
		return 1
	}
	reserve_kb=$((384 * 1024))
	target_kb=$((mt * 80 / 100))
	[ "$target_kb" -ge "$need_kb" ] || target_kb=$need_kb
	max_kb=$((mt - reserve_kb))
	[ "$max_kb" -gt 0 ] || max_kb=$target_kb
	[ "$target_kb" -le "$max_kb" ] || target_kb=$max_kb
	cur_kb=$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $2}')
	[ -n "$cur_kb" ] || cur_kb=0
	log "tmpfs cur_kb=$cur_kb need_kb=$need_kb target_kb=$target_kb mem_kb=$mt"
	if [ "$cur_kb" -lt "$need_kb" ]; then
		# Prevent later upload-teardown from shrinking under the RAM copy.
		rm -f /var/run/lede-fw-upload-tmp-prev-kb 2>/dev/null || true
		mount -o remount,size="${target_kb}k" /tmp 2>/dev/null || {
			log "LEDE_FW_COPY_FAIL cannot grow /tmp tmpfs (need ${need_kb}k RAM)"
			return 1
		}
		cur_kb=$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $2}')
		log "tmpfs after grow cur_kb=$cur_kb"
	fi
	[ "${cur_kb:-0}" -ge "$need_kb" ] || {
		log "LEDE_FW_COPY_FAIL /tmp still too small ($cur_kb < $need_kb)"
		return 1
	}
	return 0
}

/usr/libexec/lede-firmware-mark-flash.sh >>"$LOG" 2>&1 || exit 1
rm -f /var/run/lede-fw-upload-active 2>/dev/null || true

lede_flash_grow_tmp || {
	echo "LEDE_FW_COPY_FAIL grow /tmp" >&2
	exit 1
}

set -- /sbin/sysupgrade
[ "$save" = 0 ] && set -- "$@" -n
[ "$force" = 1 ] && set -- "$@" --force
set -- "$@" "$RAM_IMAGE"

{
	echo "=== lede-firmware-flash background $(date -Is 2>/dev/null || date) ==="
	echo "exec $*"
	echo "note=copy $DATA_IMAGE -> $RAM_IMAGE then sysupgrade (same-disk /data cannot be dd source)"
} >>"$LOG"
[ -d /data ] && tail -5 "$LOG" >>/data/lede-fw-flash.log 2>/dev/null || true

(
	trap '' HUP INT
	umount /tmp/firmware.bin 2>/dev/null || true
	rm -f /tmp/firmware.bin /tmp/image.bs "$RAM_IMAGE" 2>/dev/null || true
	log "LEDE_FW_COPY start $(date -Is 2>/dev/null || date)"
	if ! cp -f "$DATA_IMAGE" "$RAM_IMAGE"; then
		log "LEDE_FW_COPY_FAIL cp $DATA_IMAGE -> $RAM_IMAGE"
		exit 1
	fi
	ds=$(ls -ln "$DATA_IMAGE" 2>/dev/null | awk '{print $5; exit}')
	rs=$(ls -ln "$RAM_IMAGE" 2>/dev/null | awk '{print $5; exit}')
	[ -n "$ds" ] || ds=0
	[ -n "$rs" ] || rs=1
	if [ "$ds" != "$rs" ]; then
		log "LEDE_FW_COPY_FAIL size $rs != $ds"
		exit 1
	fi
	log "LEDE_FW_COPY ok size=$rs"
	log "exec $*"
	exec "$@"
) >>"$LOG" 2>&1 &

spid=$!
echo "$spid" >"$PIDFILE"
logger -t lede-fw "background copy+sysupgrade pid=$spid $*"
echo "LEDE_FW_FLASH_STARTED pid=$spid"
exit 0
