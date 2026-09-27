#!/bin/bash
# 30-minute burn-in on a LEDE router: CPU + LAN NIC load + detailed sampling.
# Detects unexpected reboots (uptime regression / SSH drop + low uptime).
#
# Usage:
#   ./stress-burnin-30m.sh [router-ip] [password] [minutes]
#   ROUTER=192.168.9.1 PASS=password MINUTES=30 ./stress-burnin-30m.sh
#
# Optional: LAN_IP=your-mac-on-lan  (for iperf3 server on Mac toward router client)
# Requires: sshpass, ssh, curl; iperf3 on Mac (brew install iperf3) recommended.

set -euo pipefail

iso_date() {
	date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S
}

ROUTER="${1:-${ROUTER:-192.168.9.1}}"
PASS="${2:-${PASS:-password}}"
MINUTES="${3:-${MINUTES:-30}}"
DURATION=$((MINUTES * 60))
INTERVAL="${INTERVAL:-10}"

HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
STAMP=$(date +%Y%m%d-%H%M%S)
OUT="${OUT:-$ROOT/stress-logs/${ROUTER}_${STAMP}}"
REMOTE="/tmp/stress-burnin-remote.sh"

mkdir -p "$OUT"
LOG="$OUT/runner.log"
SAMPLE="$OUT/samples.tsv"
EVENTS="$OUT/events.log"
SUMMARY="$OUT/summary.txt"

SSH_OPTS=(
	-o PubkeyAuthentication=no
	-o PreferredAuthentications=password
	-o StrictHostKeyChecking=no
	-o UserKnownHostsFile=/dev/null
	-o ConnectTimeout=12
	-o ServerAliveInterval=15
	-o ServerAliveCountMax=4
)

ssh_r() {
	SSHPASS="$PASS" sshpass -e ssh "${SSH_OPTS[@]}" "root@${ROUTER}" "$@"
}

scp_r() {
	SSHPASS="$PASS" sshpass -e scp "${SSH_OPTS[@]}" "$@"
}

log() {
	printf '%s %s\n' "$(iso_date)" "$*" | tee -a "$LOG"
}

# Mac LAN IP toward router (for iperf3 -s on Mac, router runs -c -R).
detect_lan_ip() {
	if [ -n "${LAN_IP:-}" ]; then
		echo "$LAN_IP"
		return
	fi
	local ip iface
	ip=$(route -n get "$ROUTER" 2>/dev/null | awk '/source address:/{print $3; exit}')
	[ -n "$ip" ] && { echo "$ip"; return; }
	iface=$(route -n get "$ROUTER" 2>/dev/null | awk '/interface:/{print $2; exit}')
	[ -n "$iface" ] && ipconfig getifaddr "$iface" 2>/dev/null
}

LAN_IP=$(detect_lan_ip || true)

if ! command -v sshpass >/dev/null 2>&1; then
	echo "Install sshpass (brew install sshpass)" >&2
	exit 1
fi

if ! command -v iperf3 >/dev/null 2>&1; then
	if [ "${SKIP_BREW:-0}" != 1 ] && command -v brew >/dev/null 2>&1; then
		log "iperf3 missing on Mac; trying brew install (SKIP_BREW=1 to skip)..."
		brew install iperf3 || log "WARN: iperf3 install failed — parallel HTTPS + router local load only"
	else
		log "WARN: no iperf3 — network stress will use parallel HTTPS only"
	fi
fi

log "Output directory: $OUT"
log "Router: $ROUTER  Duration: ${MINUTES}m  Sample interval: ${INTERVAL}s  LAN_IP: ${LAN_IP:-unknown}"

# Baseline snapshot
ssh_r 'sh -s' << 'SNAP' > "$OUT/baseline.txt" 2>&1 || true
set +e
echo "=== $(date '+%Y-%m-%dT%H:%M:%S') baseline ==="
uname -a
uptime
free
grep -c ^processor /proc/cpuinfo
cat /proc/loadavg
ip -br addr
ip -br link
dmesg | tail -40
logread | tail -60
[ -f /tmp/lede-reboot-reason ] && echo "reboot_reason=$(cat /tmp/lede-reboot-reason)"
[ -x /usr/libexec/lede-hwinfo ] && /usr/libexec/lede-hwinfo 2>/dev/null | head -c 8000
SNAP

scp_r "$HERE/stress-burnin-remote.sh" "root@${ROUTER}:${REMOTE}"
ssh_r "chmod +x ${REMOTE}; rm -f /tmp/lede-stress-burnin.pid; touch /tmp/lede-stress-burnin.pid"

# iperf3 server on Mac (router pulls from LAN when iperf3 exists on router)
IPERF_PID=""
if command -v iperf3 >/dev/null 2>&1 && [ -n "$LAN_IP" ]; then
	iperf3 -s -p 5201 >> "$OUT/iperf3-server.log" 2>&1 &
	IPERF_PID=$!
	log "iperf3 server on ${LAN_IP}:5201 pid=$IPERF_PID"
fi

# Try install iperf3 on router for reverse mode (best effort)
ssh_r 'opkg update >/dev/null 2>&1; opkg install iperf3 >/dev/null 2>&1; command -v iperf3 || true' \
	> "$OUT/router-iperf3.txt" 2>&1 || true

# Start remote CPU stress (background on router)
ssh_r "nohup ${REMOTE} ${DURATION} '${LAN_IP}' 8 >> /tmp/lede-stress-burnin.log 2>&1 & echo remote_pid=\$!" \
	| tee -a "$LOG" || true

# Mac → router HTTPS flood (nginx + CPU on router)
HTTPS_PIDS=""
_https_n=0
while [ "$_https_n" -lt 16 ]; do
	(
		end=$((SECONDS + DURATION))
		while [ "$SECONDS" -lt "$end" ]; do
			curl -sk --max-time 5 "https://${ROUTER}/" -o /dev/null 2>/dev/null || true
			curl -sk --max-time 5 "https://${ROUTER}/cgi-bin/luci/" -o /dev/null 2>/dev/null || true
		done
	) &
	HTTPS_PIDS="$HTTPS_PIDS $!"
	_https_n=$((_https_n + 1))
done
log "Started 16 parallel HTTPS load workers on Mac"

printf 'ts\treachable\tuptime_s\tload1\tmem_avail_kb\tcpu_busy_pct\t' > "$SAMPLE"
printf 'rx_bytes\ttx_bytes\trx_delta\ttx_delta\tdrop_delta\terr_delta\t' >> "$SAMPLE"
printf 'notes\n' >> "$SAMPLE"

last_uptime=""
last_rx="" last_tx="" last_drop="" last_err=""
start_ts=$(date +%s)
end_ts=$((start_ts + DURATION))

sample_once() {
	local ts line reachable uptime load1 mem cpu rx tx drop err
	ts=$(iso_date)
	if ! line=$(ssh_r 'read u _ </proc/uptime; l=$(cut -d" " -f1 /proc/loadavg); m=$(awk "/MemAvailable/ {print \$2}" /proc/meminfo); \
		read _ c1 </proc/stat; sleep 1; read _ c2 </proc/stat; \
		c=$(awk -v a="$c1" -v b="$c2" "BEGIN{
		  split(a,x); split(b,y); idle1=x[5]; idle2=y[5]; t1=t2=0;
		  for(i=2;i<=length(x);i++) t1+=x[i]; for(i=2;i<=length(y);i++) t2+=y[i];
		  d=t2-t1; di=idle2-idle1; if(d>0) print int(100*(d-di)/d); else print 0}"); \
		rx=$(awk "BEGIN{s=0} /:/ {next} {s+=\$2} END{print s}" /proc/net/dev); \
		tx=$(awk "BEGIN{s=0} /:/ {next} {s+=\$10} END{print s}" /proc/net/dev); \
		dr=$(awk "BEGIN{s=0} /:/ {next} {s+=\$5} END{print s}" /proc/net/dev); \
		er=$(awk "BEGIN{s=0} /:/ {next} {s+=\$4} END{print s}" /proc/net/dev); \
		printf "OK %s %s %s %s %s %s %s %s\n" "$u" "$l" "$m" "$c" "$rx" "$tx" "$dr" "$er"' 2>/dev/null); then
		reachable=0
		printf '%s\t0\t\t\t\t\t\t\t\t\t\tssh_fail\n' "$ts" >> "$SAMPLE"
		echo "$ts SSH_FAIL" >> "$EVENTS"
		return
	fi
	read -r reachable uptime load1 mem cpu rx tx drop err <<< "$line"
	reachable=1
	local rdx=0 tdx=0 drd=0 erd=0 note=""
	if [ -n "$last_uptime" ] && [ -n "$uptime" ]; then
		# uptime decreased => reboot
		if awk -v a="$uptime" -v b="$last_uptime" 'BEGIN{exit !(a+5 < b)}'; then
			note="REBOOT_DETECTED"
			echo "$ts REBOOT uptime=${uptime} was=${last_uptime}" >> "$EVENTS"
			ssh_r 'dmesg | tail -30; logread | tail -40; cat /tmp/lede-reboot-reason 2>/dev/null' \
				> "$OUT/reboot-${ts//[:]/}.txt" 2>&1 || true
		fi
	fi
	if [ -n "$last_rx" ]; then rdx=$((rx - last_rx)); fi
	if [ -n "$last_tx" ]; then tdx=$((tx - last_tx)); fi
	if [ -n "$last_drop" ]; then drd=$((drop - last_drop)); fi
	if [ -n "$last_err" ]; then erd=$((err - last_err)); fi
	last_uptime=$uptime last_rx=$rx last_tx=$tx last_drop=$drop last_err=$err
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
		"$ts" "$reachable" "$uptime" "$load1" "$mem" "$cpu" "$rx" "$tx" "$rdx" "$tdx" "$drd" "$erd" "$note" >> "$SAMPLE"
}

log "Sampling started (until $(date -r "$end_ts" 2>/dev/null || iso_date))"

while [ "$(date +%s)" -lt "$end_ts" ]; do
	sample_once
	sleep "$INTERVAL"
done

log "Stopping load generators..."
for p in $HTTPS_PIDS; do kill "$p" 2>/dev/null || true; done
[ -n "$IPERF_PID" ] && kill "$IPERF_PID" 2>/dev/null || true
ssh_r 'rm -f /tmp/lede-stress-burnin.pid; kill $(jobs -p) 2>/dev/null; pkill -f "openssl speed" 2>/dev/null; pkill -f stress-burnin-remote 2>/dev/null; true' \
	>> "$LOG" 2>&1 || true

ssh_r 'sh -s' << 'SNAP' > "$OUT/final.txt" 2>&1 || true
set +e
echo "=== $(date '+%Y-%m-%dT%H:%M:%S') final ==="
uptime
free
cat /proc/loadavg
ip -br link
dmesg | tail -50
logread | tail -80
cat /tmp/lede-stress-burnin.log 2>/dev/null | tail -30
SNAP

# Summary stats
awk -F'\t' 'NR>1 && $2==1 {cpu+=$6; n++; if($6>max)max=$6; load+=$4} END{
 if(n>0) printf("samples=%d avg_cpu_busy=%.1f max_cpu_busy=%.0f avg_load1=%.2f\n", n, cpu/n, max, load/n)
}' "$SAMPLE" > "$SUMMARY" || true
grep -c REBOOT "$EVENTS" 2>/dev/null | awk '{print "reboot_events=" $1}' >> "$SUMMARY" || echo reboot_events=0 >> "$SUMMARY"

log "Done. Artifacts in $OUT"
cat "$SUMMARY" | tee -a "$LOG"
