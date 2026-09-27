#!/bin/sh
# Sysupgrade / dd progress for LuCI (avoid generic "bytes" kernel noise).
set -eu

LOG=/tmp/lede-fw-flash.log
if [ -r "$LOG" ]; then
	echo '--- lede-fw-flash.log (tail) ---'
	tail -20 "$LOG" 2>/dev/null || true
fi

if [ -r /tmp/sysupgrade.log ]; then
	echo '--- sysupgrade.log (tail) ---'
	tail -15 /tmp/sysupgrade.log 2>/dev/null || true
fi

if command -v logread >/dev/null 2>&1; then
	logread 2>/dev/null | grep -E ' upgrade:|^upgrade:|sysupgrade|lede-fw|Partition layout|Image metadata|Full image will be written|Writing to|Writing image|Copied|dd:' | tail -30
fi

if pgrep -x dd >/dev/null 2>&1; then
	kill -USR1 "$(pgrep -x dd | head -1)" 2>/dev/null || true
	sleep 0.2
	logread 2>/dev/null | grep -Ei 'records (in|out)|copied|dd:' | tail -6
fi

for pid in $(pgrep -x dd 2>/dev/null); do
	cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
	[ -n "$cmd" ] || continue
	echo "LED_FW_DD_CMD pid=$pid $cmd"
	if [ -r "/proc/$pid/io" ]; then
		wb=$(grep '^write_bytes:' "/proc/$pid/io" 2>/dev/null | awk '{print $2}')
		[ -n "$wb" ] || wb=0
		echo "LED_FW_DD_WRITE_BYTES=$wb"
	fi
done

ps w 2>/dev/null | grep -E '[s]ysupgrade |[p]v ' | head -6 || true

exit 0
