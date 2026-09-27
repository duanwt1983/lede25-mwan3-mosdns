#!/bin/sh
# LuCI entry: log then exec real sysupgrade (dd hooks live in /lib/upgrade/lede-flash-dd.sh).
set -eu
LOG=/tmp/lede-fw-flash.log

{
	echo "=== sysupgrade start $(date -Is 2>/dev/null || date) ==="
	echo "cmd=/sbin/sysupgrade $*"
} >>"$LOG"
logger -t lede-fw "sysupgrade $*"

exec /sbin/sysupgrade "$@"
