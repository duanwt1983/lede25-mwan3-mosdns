'use strict';

/*
 * LOCKED — RATE_DIRECTION v1 (2026-03-14)
 * Do not change mapping without re-validating topology + WAN/LAN live test.
 * All backend/UI/alert/limit code MUST use these helpers.
 *
 * User view: down=下载, up=上传. All *_bps = bits per second (UI /1e6 → Mbps).
 *
 * NIC (/proc/net/dev):
 *   PPPoE WAN (pppoe-*): download=tx delta, upload=rx delta
 *   LAN bridge (br-*):   download=rx delta, upload=tx delta
 *
 * Conntrack per client:
 *   ct.rx = reply → download, ct.tx = orig → upload
 *
 * History: series.rx=download bps, series.tx=upload bps
 */
export const RATE_DIRECTION_VERSION = 1;

function clamp_delta(v) {
	v = +v || 0;
	return v < 0 ? 0 : v;
}

function safe_dt(dt) {
	dt = +dt || 0;
	return dt >= 1 ? dt : 1;
}

export function nic_down_is_tx(dev) {
	if (!dev || dev == '')
		return true;
	if (index(dev, 'br-') == 0 || dev == 'br-lan')
		return false;
	if (index(dev, 'pppoe') == 0)
		return true;
	return true;
}

export function nic_user_bps(cur, prev, dt, dev) {
	let drx = clamp_delta(+(cur.rx || 0) - +(prev.rx || 0));
	let dtx = clamp_delta(+(cur.tx || 0) - +(prev.tx || 0));
	dt = safe_dt(dt);
	let down_bytes = nic_down_is_tx(dev) ? dtx : drx;
	let up_bytes = nic_down_is_tx(dev) ? drx : dtx;
	return {
		down_bps: int((down_bytes * 8.0) / dt),
		up_bps: int((up_bytes * 8.0) / dt),
		down_mbps: (down_bytes * 8.0) / dt / 1000000.0,
		up_mbps: (up_bytes * 8.0) / dt / 1000000.0
	};
}

export function ct_user_bps(cur, prev, dt) {
	let drx = clamp_delta(+(cur.rx || 0) - +(prev.rx || 0));
	let dtx = clamp_delta(+(cur.tx || 0) - +(prev.tx || 0));
	dt = safe_dt(dt);
	return {
		down_bps: int((drx * 8.0) / dt),
		up_bps: int((dtx * 8.0) / dt),
		down_mbps: (drx * 8.0) / dt / 1000000.0,
		up_mbps: (dtx * 8.0) / dt / 1000000.0
	};
}

export function nic_hist_down(series) {
	return series && type(series.rx) == 'array' && length(series.rx) ?
		+(series.rx[length(series.rx) - 1] || 0) : 0;
}

export function nic_hist_up(series) {
	return series && type(series.tx) == 'array' && length(series.tx) ?
		+(series.tx[length(series.tx) - 1] || 0) : 0;
}
