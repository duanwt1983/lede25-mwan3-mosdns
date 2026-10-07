#!/bin/sh
# Fast LuCI check on /data/firmware.bin only (no bind/prepare).
# Must finish in well under LuCI XHR ~20s. Do not truncate or remount the image.
set -eu
export PATH=/usr/sbin:/sbin:/usr/bin:/bin

DATA=/data/firmware.bin
LOG=/tmp/lede-firmware-validate.log
STATE=/tmp/lede-fw-validate.state

log() { echo "$*" | tee -a "$LOG"; }

: >"$LOG"
echo "status=running" >"$STATE"

[ -f "$DATA" ] || {
	log "ERROR missing $DATA"
	log "LEDE_FW_VALIDATE result=fail"
	echo "status=fail" >"$STATE"
	exit 2
}

# This image has no busybox `stat` applet — GNU `stat -c` fails and used to yield size=0.
size=$(ls -ln "$DATA" 2>/dev/null | awk '{print $5; exit}')
[ -n "$size" ] || size=0
log "size=$size path=$DATA"

if [ "$size" -lt 33554432 ]; then
	log "ERROR image too small or truncated"
	log "LEDE_FW_VALIDATE result=fail"
	log "LEDE_FW_VALIDATE hint=请重新上传固件到 /data/firmware.bin"
	echo "status=fail" >"$STATE"
	exit 1
fi

magic=$(hexdump -n 2 -e '1/1 "%02x"' "$DATA" 2>/dev/null || true)
mbr=$(hexdump -s 510 -n 2 -e '1/1 "%02x"' "$DATA" 2>/dev/null || true)
log "magic=$magic mbr510=$mbr"

ok=0
hint=""
case "$magic" in
	1f8b)
		ok=1
		hint="gzip 镜像（.img.gz）"
		;;
esac
if [ "$mbr" = "55aa" ] || [ "$mbr" = "aa55" ]; then
	ok=1
	hint="x86 整盘 MBR 镜像"
fi

if [ "$ok" -ne 1 ]; then
	log "LEDE_FW_VALIDATE result=fail"
	log "LEDE_FW_VALIDATE hint=不是 gzip 也不是 MBR 整盘镜像（请确认 .img / .img.gz 已传完整）"
	echo "status=fail" >"$STATE"
	exit 1
fi

log "LEDE_FW_VALIDATE valid=1 forceable=1 size=$size"
log "LEDE_FW_VALIDATE result=pass"
log "LEDE_FW_VALIDATE hint=$hint；完整校验在确认刷写后于后台由 sysupgrade 执行"
echo "status=pass" >"$STATE"
exit 0
