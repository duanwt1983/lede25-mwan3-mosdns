#!/bin/sh
# LuCI entry: log then exec real sysupgrade (dd hooks live in /lib/upgrade/lede-flash-dd.sh).
set -eu
LOG=/tmp/lede-fw-flash.log

{
	echo "=== sysupgrade start $(date -Is 2>/dev/null || date) ==="
	echo "cmd=/sbin/sysupgrade $*"
	echo "note=LuCI will disconnect during dd; LEDE reboot line is only in stage2/log, not in browser"
} >>"$LOG"
[ -d /data ] && tail -20 "$LOG" >>/data/lede-fw-flash.log 2>/dev/null || true
logger -t lede-fw "sysupgrade $*"

exec /sbin/sysupgrade "$@"
