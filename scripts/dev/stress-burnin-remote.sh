#!/bin/sh
# Run ON the router (OpenWrt/LEDE). CPU + optional iperf client toward LAN host.
set -eu

DURATION="${1:-1800}"
IPERF_TARGET="${2:-}"
IPERF_STREAMS="${3:-8}"
STAMP="/tmp/lede-stress-burnin.pid"
LOG="/tmp/lede-stress-burnin.log"

cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 4)
[ "$cores" -gt 0 ] 2>/dev/null || cores=4

echo "stress-burnin start $(date '+%Y-%m-%dT%H:%M:%S') duration=${DURATION}s cores=${cores} iperf_target=${IPERF_TARGET:-none}" >> "$LOG"

# CPU: openssl RSA (heavy) one loop per core.
i=0
while [ "$i" -lt "$cores" ]; do
	(
		while [ -f "$STAMP" ]; do
			openssl speed -seconds 2 rsa4096 2>/dev/null || openssl speed -seconds 2 rsa2048 2>/dev/null || true
		done
	) &
	i=$((i + 1))
done

# Extra md5 on urandom for sustained load if openssl throttles.
(
	while [ -f "$STAMP" ]; do
		md5sum /dev/urandom >/dev/null 2>&1 || head -c 65536 /dev/urandom | md5sum >/dev/null 2>&1 || true
	done
) &

# Memory churn (small; avoid OOM on 4G box).
(
	while [ -f "$STAMP" ]; do
		head -c 4194304 /dev/urandom | md5sum >/dev/null 2>&1 || true
		sleep 1
	done
) &

if [ -n "$IPERF_TARGET" ] && command -v iperf3 >/dev/null 2>&1; then
	(
		iperf3 -c "$IPERF_TARGET" -p 5201 -t "$DURATION" -P "$IPERF_STREAMS" -R >> "$LOG" 2>&1 || true
	) &
elif [ -n "$IPERF_TARGET" ]; then
	echo "iperf3 not installed on router; LAN load relies on host-side clients" >> "$LOG"
fi

# Local HTTPS loops (nginx/uhttpd + stack) even without iperf3.
j=0
while [ "$j" -lt 4 ]; do
	(
		while [ -f "$STAMP" ]; do
			curl -sk --max-time 3 https://127.0.0.1/ -o /dev/null 2>/dev/null \
				|| wget -q -O /dev/null --no-check-certificate https://127.0.0.1/ 2>/dev/null \
				|| true
		done
	) &
	j=$((j + 1))
done

sleep "$DURATION" 2>/dev/null || sleep "$DURATION"
rm -f "$STAMP"
kill $(jobs -p) 2>/dev/null || true
wait 2>/dev/null || true
echo "stress-burnin end $(date '+%Y-%m-%dT%H:%M:%S')" >> "$LOG"
