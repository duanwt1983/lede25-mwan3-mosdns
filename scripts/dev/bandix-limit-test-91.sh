#!/bin/bash
# Single-client IPv4 rate-limit sanity test (Mac on LAN -> 9.1 Bandix).
set -euo pipefail
ROUTER="${1:-192.168.9.1}"
PASS="${2:-password}"
MAC='5c:1b:f4:9e:2d:2c'
IFACE='br-lan'
LIMIT_DOWN_KBPS=5000
LIMIT_UP_KBPS=2000
IPERF_HOST="${IPERF_HOST:-bouygues.iperf.fr}"
IPERF_SEC=12

ubus_call() {
	local method=$1 obj=$2
	shift 2
	jq -n --arg t "$TOKEN" --arg m "$method" --arg o "$obj" --argjson p "${4:-{}}" \
		'{jsonrpc:"2.0",id:1,method:"call",params:[$t,$o,$m,$p]}' \
	| curl -fsSk -H 'Content-Type: application/json' --data-binary @- "https://${ROUTER}/ubus"
}

login() {
	TOKEN=$(jq -n --arg pass "$PASS" \
		'{jsonrpc:"2.0",id:1,method:"call",params:["00000000000000000000000000000000","session","login",{username:"root",password:$pass,timeout:600}]}' \
	| curl -fsSk -H 'Content-Type: application/json' --data-binary @- "https://${ROUTER}/ubus" \
	| jq -r '.result[1].ubus_rpc_session // .result[1].data.ubus_rpc_session')
	[ -n "$TOKEN" ] && [ "$TOKEN" != null ]
}

metrics_v4() {
	ubus_call getDevices luci.bandix_plus | jq -r \
		'.result[1].data[] | select(.mac=="'"$MAC"'") | .metrics | "\(.down_v4_bps) \(.up_v4_bps)"'
}

kbps_to_Bps() { echo $(( $1 * 1000 / 8 )); }

run_iperf_down() {
	iperf3 -c "$IPERF_HOST" -p 5200 -R -t "$IPERF_SEC" -J 2>/dev/null \
	| jq -r '.end.sum_received.bits_per_second // .end.sum_sent.bits_per_second // 0'
}

run_iperf_up() {
	iperf3 -c "$IPERF_HOST" -p 5200 -t "$IPERF_SEC" -J 2>/dev/null \
	| jq -r '.end.sum_sent.bits_per_second // 0'
}

clear_schedules() {
	local ids
	ids=$(ubus_call getSchedules luci.bandix_plus | jq -r '.result[1].data[]?.id // empty')
	for id in $ids; do
		jq -n --arg t "$TOKEN" --arg id "$id" \
			'{jsonrpc:"2.0",id:1,method:"call",params:[$t,"luci.bandix_plus","deleteSchedule",{id:$id}]}' \
		| curl -fsSk -H 'Content-Type: application/json' --data-binary @- "https://${ROUTER}/ubus" >/dev/null
	done
}

apply_limit() {
	jq -n \
		--arg iface "$IFACE" --arg mac "$MAC" \
		--argjson d4 "$LIMIT_DOWN_KBPS" --argjson u4 "$LIMIT_UP_KBPS" \
		'{iface:$iface,mac:$mac,time_slot:{start:"00:00",end:"23:59",days:[1,2,3,4,5,6,7]},down_v4_kbps:$d4,down_v6_kbps:0,up_v4_kbps:$u4,up_v6_kbps:0}' \
	| jq --arg t "$TOKEN" '{jsonrpc:"2.0",id:1,method:"call",params:[$t,"luci.bandix_plus","createSchedule",.]}' \
	| curl -fsSk -H 'Content-Type: application/json' --data-binary @- "https://${ROUTER}/ubus" | jq -e '.result[1].ok == true' >/dev/null
	sleep 2
}

phase() {
	local name=$1
	echo ""
	echo "======== $name ========"
}

login
echo "Router $ROUTER  client MAC $MAC"
echo "Target limits: down=${LIMIT_DOWN_KBPS} kbps  up=${LIMIT_UP_KBPS} kbps (IPv4)"
echo "Expected caps (approx): down=$(kbps_to_Bps $LIMIT_DOWN_KBPS) B/s  up=$(kbps_to_Bps $LIMIT_UP_KBPS) B/s"

clear_schedules
phase "A baseline (no schedule)"
echo -n "Bandix metrics before load: "; metrics_v4
echo "iperf download (client RX) ${IPERF_SEC}s..."
B_DOWN=$(run_iperf_down || echo 0)
echo "  measured bps: $B_DOWN ($((${B_DOWN:-0}/1000000)) Mbps)"
echo -n "Bandix during/after down: "; metrics_v4
echo "iperf upload (client TX) ${IPERF_SEC}s..."
B_UP=$(run_iperf_up || echo 0)
echo "  measured bps: $B_UP ($((${B_UP:-0}/1000000)) Mbps)"
echo -n "Bandix after up: "; metrics_v4

apply_limit
phase "B limited (device schedule active)"
echo -n "Schedules: "
ubus_call getSchedules luci.bandix_plus | jq -c '.result[1].data'
echo "iperf download ${IPERF_SEC}s..."
L_DOWN=$(run_iperf_down || echo 0)
echo "  measured bps: $L_DOWN ($((${L_DOWN:-0}/1000000)) Mbps)"
echo -n "Bandix metrics: "; metrics_v4
echo "iperf upload ${IPERF_SEC}s..."
L_UP=$(run_iperf_up || echo 0)
echo "  measured bps: $L_UP ($((${L_UP:-0}/1000000)) Mbps)"
echo -n "Bandix metrics: "; metrics_v4

phase "C summary"
python3 - <<PY
b_down, l_down = float("${B_DOWN:-0}"), float("${L_DOWN:-0}")
b_up, l_up = float("${B_UP:-0}"), float("${L_UP:-0}")
lim_d = ${LIMIT_DOWN_KBPS} * 1000
lim_u = ${LIMIT_UP_KBPS} * 1000
def chk(name, meas, lim, base):
    if meas <= 0:
        print(f"{name}: no measurement")
        return
    ratio = meas / lim if lim else 0
    print(f"{name}: {meas/1e6:.2f} Mbps vs limit {lim/1e6:.2f} Mbps (ratio {ratio:.2f})")
    if base > 0:
        print(f"  vs baseline {base/1e6:.2f} Mbps (×{meas/base:.2f})")
    ok = 0.55 <= ratio <= 1.15 if lim > 0 else True
    print(f"  within ~55–115% of limit: {'YES' if ok else 'NO'}")
chk("Download", l_down, lim_d, b_down)
chk("Upload", l_up, lim_u, b_up)
PY

clear_schedules
echo "Schedules cleared."
