'use strict';
'require view';
'require poll';
'require rpc';
'require ui';
'require lede-theme-page as ledeTheme';
'require tools.topo-bandix-devlist as TopoBandixDevList';

const NS = 'http://www.w3.org/2000/svg';

const callSnapshot = rpc.declare({
	object: 'wanmonitor',
	method: 'snapshot',
	expect: {}
});

const callPulse = rpc.declare({
	object: 'wanmonitor',
	method: 'pulse',
	expect: {}
});

const callBandixDevices = rpc.declare({
	object: 'luci.bandix_plus',
	method: 'getDevices',
	params: [ 'iface', 'period' ],
	expect: {}
});

const callBandixSchedules = rpc.declare({
	object: 'luci.bandix_plus',
	method: 'getSchedules',
	expect: {}
});

const callLayoutGet = rpc.declare({
	object: 'wanmonitor',
	method: 'layout_get',
	expect: {}
});

const callLayoutSet = rpc.declare({
	object: 'wanmonitor',
	method: 'layout_set',
	params: [ 'layout' ]
});

const callWanRestart = rpc.declare({
	object: 'wanmonitor',
	method: 'wan_restart',
	params: [ 'name' ]
});

const callGatewayReboot = rpc.declare({
	object: 'wanmonitor',
	method: 'gateway_reboot',
	params: [ 'source' ]
});

const callBoard = rpc.declare({
	object: 'system',
	method: 'board',
	expect: {}
});

const FIELD_CATALOG = {
	internet: [
		{ id: 'title', label: '名称' },
		{ id: 'hint', label: '说明' }
	],
	nic: [
		{ id: 'name', label: '接口名' },
		{ id: 'speed', label: '网卡速率' },
		{ id: 'status', label: '状态' },
		{ id: 'proto', label: '协议' },
		{ id: 'ip', label: 'IP 地址' },
		{ id: 'rate', label: '上下行速率' },
		{ id: 'lat', label: '延迟' },
		{ id: 'uptime', label: '已连接时长' }
	],
	gateway: [
		{ id: 'title', label: '名称' },
		{ id: 'role', label: '角色' },
		{ id: 'lanip', label: 'LAN 地址' },
		{ id: 'cpu', label: 'CPU' },
		{ id: 'temp', label: '温度' },
		{ id: 'conn', label: '连接数' },
		{ id: 'wans', label: 'WAN 口' }
	],
	switch: [
		{ id: 'title', label: '名称' },
		{ id: 'hint', label: '说明' },
		{ id: 'rate', label: 'LAN 合计速率' },
		{ id: 'online', label: '在线终端' },
		{ id: 'rank', label: '客户端排行' }
	],
	host: [
		{ id: 'name', label: '客户端名称' },
		{ id: 'ip', label: 'IP' },
		{ id: 'mac', label: 'MAC' },
		{ id: 'rate', label: '上下行速率' },
		{ id: 'online', label: '在线状态' }
	],
	wan_sum: [
		{ id: 'title', label: '总带宽标题' },
		{ id: 'rate', label: '上下行速率' }
	],
	link_inet_wan: [
		{ id: 'name', label: '线路名' },
		{ id: 'status', label: '状态' },
		{ id: 'rate', label: '上下行速率' },
		{ id: 'usage', label: '宽带使用率' },
		{ id: 'lat', label: '延迟' }
	],
	link_wan_gw: [
		{ id: 'name', label: '线路名' },
		{ id: 'rate', label: '上下行速率' },
		{ id: 'lat', label: '延迟' }
	],
	link_gw_sw: [
		{ id: 'name', label: '名称' },
		{ id: 'rate', label: '上下行速率' },
		{ id: 'lat', label: '延迟' }
	],
	link_sw_cli: [
		{ id: 'name', label: '终端名' },
		{ id: 'rate', label: '上下行速率' },
		{ id: 'lat', label: '延迟' }
	]
};

const FIELD_DEFAULTS = {
	internet: [],
	nic: ['name'],
	gateway: ['title', 'role', 'lanip'],
	switch: ['title', 'hint', 'online', 'rank'],
	host: ['ip', 'rate'],
	wan_sum: ['title', 'rate'],
	link_inet_wan: ['rate'],
	link_wan_gw: ['rate'],
	link_gw_sw: ['rate'],
	link_sw_cli: []
};

function svgEl(name, attrs, children) {
	const e = document.createElementNS(NS, name);
	Object.keys(attrs || {}).forEach(k => {
		if (attrs[k] == null || attrs[k] === '')
			return;
		e.setAttribute(k, String(attrs[k]));
	});
	(children || []).forEach(c => {
		if (c)
			e.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
	});
	return e;
}

/* Input is always bits per second (bytes_delta * 8 / seconds). */
function fmtBitrate(bps) {
	const p = bitrateParts(bps);
	return p.num + ' ' + p.unit;
}

function bitrateParts(bps) {
	if (!isFinite(bps) || bps < 0)
		bps = 0;
	let v = bps / 1e6;
	let decimals = 0;
	if (v >= 10000)
		decimals = 0;
	else if (v >= 1000)
		decimals = 1;
	else if (v >= 100)
		decimals = 2;
	else if (v >= 10)
		decimals = 3;
	else if (v > 0)
		decimals = 4;
	let num = v.toFixed(decimals);
	if (num.indexOf('.') >= 0)
		num = num.replace(/(\.\d*?)0+$/, '$1').replace(/\.$/, '');
	return { num: num, unit: 'Mbps' };
}

function usagePct(bps, mbit) {
	const cap = Number(mbit) * 1e6;
	if (!(cap > 0) || !isFinite(bps) || bps < 0)
		return null;
	return Math.min(999, Math.round((bps / cap) * 100));
}

function usageColor(pct) {
	if (pct < 50)
		return '#16a34a';
	if (pct < 80)
		return '#d97706';
	return '#dc2626';
}

function padFig(s, w, dir) {
	s = String(s);
	const sp = '\u2007';
	while (s.length < w)
		s = dir === 'end' ? s + sp : sp + s;
	return s;
}

const RATE_NUM_W = 6;
const RATE_UNIT_W = 6;
const CLI_PITCH = 28;
const CLI_TOPN_MAX = 30;
const TOPO_CANVAS = { w: 1280, h: 520 };
const TOPO_TEMPLATE = {
	internet: { x: 120, y: 240, w: 405, h: 211 },
	gateway: { x: 408, y: 238.5, w: 68, h: 344 },
	switch: { x: 672, y: 240, w: 68, h: 344 },
	'cli-stack': { x: 888, y: 240 },
	'wan-sum': { x: 120, y: 184 },
	wanSum: { dx: 0, dy: -56 },
	inetJackDx: 80,
	wanFan: 16,
	lanStackDx: 182
};

const TOPO_NIC_TEMPLATE = {
	'nic:lan': { rel: 1, x: 48, y: 1.5, s: 0.5, rot: 90 },
	'nic:Wan_1': { rel: 1, x: -48, y: -118.5, s: 0.5, rot: -90 },
	'nic:Wan_2': { rel: 1, x: -48, y: 1.5, s: 0.55, rot: -90 },
	'nic:Wan_3': { rel: 1, x: -48, y: 121.5, s: 0.5, rot: -90 }
};

const TOPO_FIELDS_TEMPLATE = {
	switch: [],
	gateway: [],
	'wan-sum': ['rate'],
	'cli-list': ['ip', 'rate', 'name'],
	'nic:Wan_1': ['name', 'ip'],
	'nic:Wan_2': ['name', 'ip'],
	'nic:Wan_3': ['name', 'ip'],
	'link:inet:Wan_1': ['rate'],
	'link:inet:Wan_3': ['rate']
};

const TOPO_LINKS_TEMPLATE = {
	_lanDir: 2,
	'link:lan': {
		x1: 456, y1: 240, x2: 648, y2: 240,
		labelX: 552, labelY: 240
	},
	'link:inet:Wan_1': {
		x1: 96, y1: 216, x2: 360, y2: 120,
		labelX: 264, labelY: 120
	},
	'link:inet:Wan_2': {
		x1: 96, y1: 240, x2: 360, y2: 240,
		labelX: 288, labelY: 240
	},
	'link:inet:Wan_3': {
		x1: 96, y1: 264, x2: 360, y2: 360,
		labelX: 264, labelY: 360
	}
};

const TOPO_DEFAULT_TOPN = 6;

function topoPosFallback() {
	const fallback = {};
	Object.keys(TOPO_TEMPLATE).forEach(k => {
		const t = TOPO_TEMPLATE[k];
		if (!t || !isFinite(t.x))
			return;
		fallback[k] = { x: t.x, y: t.y };
		if (isFinite(t.w))
			fallback[k].w = t.w;
		if (isFinite(t.h))
			fallback[k].h = t.h;
	});
	Object.keys(TOPO_NIC_TEMPLATE).forEach(k => {
		fallback[k] = Object.assign({}, TOPO_NIC_TEMPLATE[k]);
	});
	return fallback;
}

function clientHostname(c) {
	if (!c)
		return '';
	let h = c.hostname != null ? String(c.hostname).trim() : '';
	if (h && h !== '-')
		return h;
	h = c.name != null ? String(c.name).trim() : '';
	const ip = c.ip != null ? String(c.ip).trim() : '';
	if (h && h !== '-' && h !== ip)
		return h;
	return '';
}

function bandixUnwrap(r, fallback) {
	if (r == null)
		return fallback;
	if (typeof r === 'string') {
		try { r = JSON.parse(r); } catch (e) { return fallback; }
	}
	if (r.ok === false)
		return fallback;
	return r.data == null ? fallback : r.data;
}

function bandixDeviceIface(d) {
	if (!d || typeof d !== 'object')
		return '';
	let v = d.logical_iface != null ? String(d.logical_iface).trim() : '';
	if (v)
		return v;
	v = d.iface != null ? String(d.iface).trim() : '';
	if (v)
		return v;
	return d.ifname != null ? String(d.ifname).trim() : '';
}

function bandixMetricBps(m, down) {
	m = m || {};
	if (down)
		return (+m.down_v4_bps || 0) + (+m.down_v6_bps || 0);
	return (+m.up_v4_bps || 0) + (+m.up_v6_bps || 0);
}

function bandixFirstIpv4(d) {
	const arr = d && d.ipv4;
	if (!arr || !arr.length)
		return '';
	return String(arr[0]).split('/')[0].trim();
}

function bandixClientLabel(d) {
	let h = d && d.hostname != null ? String(d.hostname).trim() : '';
	if (h && h !== '-')
		return h;
	return '';
}

function bandixClientsFromDevices(devices) {
	const clients = [];
	let online = 0;
	(devices || []).forEach(function(d) {
		if (!d || typeof d !== 'object')
			return;
		const iface = bandixDeviceIface(d);
		if (iface && iface !== 'br-lan')
			return;
		const mac = String(d.mac || '').trim().toLowerCase();
		const ip = bandixFirstIpv4(d);
		if (!mac && !ip)
			return;
		const met = d.metrics || {};
		const down = bandixMetricBps(met, true);
		const up = bandixMetricBps(met, false);
		const cum = d.cumulative || {};
		const label = bandixClientLabel(d);
		const on = d.online === true || d.online === 1 || d.online === '1';
		if (on)
			online++;
		clients.push({
			mac: mac,
			ip: ip,
			hostname: label,
			name: label,
			online: on,
			down_bps: down,
			up_bps: up,
			rx_bytes: (+cum.down_v4_bytes || 0) + (+cum.down_v6_bytes || 0),
			tx_bytes: (+cum.up_v4_bytes || 0) + (+cum.up_v6_bytes || 0)
		});
	});
	clients.sort(function(a, b) {
		return ((+b.down_bps || 0) + (+b.up_bps || 0)) - ((+a.down_bps || 0) + (+a.up_bps || 0))
			|| ((b.online ? 1 : 0) - (a.online ? 1 : 0));
	});
	return { clients: clients, online: online, leases: clients.length };
}

const RATE_FONT = 'ui-monospace, SFMono-Regular, Consolas, "Liberation Mono", monospace';

function rateOf(prev, now, field) {
	if (!prev || !now)
		return null;
	const t0 = Number(prev.wall != null ? prev.wall : prev.ts);
	const t1 = Number(now.wall != null ? now.wall : now.ts);
	const dt = (t1 - t0) / 1000;
	if (!(dt > 0.3))
		return null;
	const d = Number(now[field]) - Number(prev[field]);
	if (!(d >= 0) || !isFinite(d))
		return null;
	return (d * 8) / dt;
}

function holdRate(prev, next, zeros, key) {
	const p = +prev || 0;
	if (next == null || !isFinite(next))
		return p;
	if (next > 800) {
		zeros[key] = 0;
		return next;
	}
	if (p > 8000) {
		zeros[key] = (zeros[key] || 0) + 1;
		if (zeros[key] < 5)
			return p;
	}
	zeros[key] = 0;
	return next;
}

function nicOf(nics, w) {
	if (!nics || !w)
		return null;
	const name = w.name || '';
	const dev = w.device || '';
	let best = '';
	let score = -1;
	for (const k in nics) {
		let s = -1;
		if (dev && k === dev)
			s = 50;
		if (name && k === name)
			s = 60;
		if (name && k.indexOf(name) >= 0)
			s = Math.max(s, 40);
		if (/^(pppoe|pptp|l2tp|tun|wg)-/.test(k) && name && k.indexOf(name) >= 0)
			s = 80;
		if (s > score) {
			score = s;
			best = k;
		}
	}
	return score >= 0 ? nics[best] : null;
}

function lastHist(snap, name, field) {
	const tip = snap && snap.rates && snap.rates.series_tip && snap.rates.series_tip[name];
	if (tip && tip[field] != null)
		return Number(tip[field]) || 0;
	const s = snap && snap.rates && snap.rates.series && snap.rates.series[name];
	const a = s && s[field];
	if (!a || !a.length)
		return 0;
	return Number(a[a.length - 1]) || 0;
}

const COL_RX = '#22c55e';
const COL_TX = '#2563eb';
const COL_LINK_IDLE = '#64748b';
const COL_LINK_IDLE_GLOW = '#94a3b8';
/* Below this bps treat link as idle: still draw the pipe (WAN live threshold is 200). */
const LINK_IDLE_BPS = 200;
const LINK_IDLE_FLOW_PX = 36;

function linkTrafficIdle(rx, tx, limit) {
	const lim = limit != null ? limit : LINK_IDLE_BPS;
	return Math.max(0, Number(rx) || 0) <= lim && Math.max(0, Number(tx) || 0) <= lim;
}

function flowShouldIdle(flow) {
	if (!flow)
		return false;
	if (flow.linkUp === false)
		return false;
	if (flow.idleLink)
		return true;
	return (Number(flow.bps) || 0) <= LINK_IDLE_BPS;
}

function utilPct(bps, capMbps) {
	const cap = Math.max(0, Number(capMbps) || 0) * 1e6;
	if (cap > 0)
		return Math.min(1, Math.max(0, (Number(bps) || 0) / cap));
	const mbit = (Number(bps) || 0) / 1e6;
	if (mbit < 0.002)
		return 0;
	if (mbit < 8)
		return 0.18;
	if (mbit < 40)
		return 0.38;
	if (mbit < 120)
		return 0.58;
	return 0.82;
}

function utilColor(bps, capMbps) {
	return flowSpeedStyle(bps, capMbps).color;
}

/* 每档用完全不同的色相，不用同色系深浅渐变；上下行各档也互不相同 */
const FLOW_TIER_RX = [
	'#94a3b8',
	'#059669',
	'#d97706',
	'#dc2626',
	'#db2777'
];

const FLOW_TIER_TX = [
	'#64748b',
	'#2563eb',
	'#7c3aed',
	'#0891b2',
	'#65a30d'
];

function flowSpeedTier(bps) {
	const mbit = Math.max(0, Number(bps) || 0) / 1e6;
	if (mbit < 0.0005)
		return 0;
	if (mbit < 1)
		return 1;
	if (mbit < 10)
		return 2;
	if (mbit < 50)
		return 3;
	return 4;
}

function flowTierColor(bps, dir) {
	const tier = flowSpeedTier(bps);
	const palette = dir === 'tx' ? FLOW_TIER_TX : FLOW_TIER_RX;
	return palette[tier];
}

function flowDirFromId(id) {
	if (!id)
		return null;
	if (id.endsWith(':tx'))
		return 'tx';
	if (id.endsWith(':rx'))
		return 'rx';
	return null;
}

function flowAnimRatio(bps) {
	const mbit = Math.max(0, Number(bps) || 0) / 1e6;
	return mbit / 100;
}

function flowSpeedStyle(bps, capMbps, dir) {
	const raw = Math.max(0, Number(bps) || 0);
	const tier = flowSpeedTier(raw);
	const color = flowTierColor(raw, dir);
	if (tier === 0)
		return { color: color, px: 0, tier: tier };
	const anim = Math.min(1, flowAnimRatio(raw));
	const px = Math.max(22, Math.min(240, (14 + anim * 100) * 2));
	return { color: color, px: px, tier: tier };
}

function applyFlowStyle(flow, bps, capMbps, live) {
	if (!flow)
		return;
	const raw = Math.max(0, Number(bps) || 0);
	flow.bps = raw;
	flow.cap = capMbps || 0;
	const dir = flow.dir || flowDirFromId(flow.id);
	const st = flowSpeedStyle(raw, capMbps, dir);
	flow.color = st.color;
	flow.px = st.px;
}

function linkRoute(x1, y1, x2, y2) {
	if (Math.abs(y1 - y2) < 1.5 || Math.abs(x1 - x2) < 1.5)
		return [{ x: x1, y: y1 }, { x: x2, y: y2 }];
	return orthoHVH(x1, y1, x2, y2, (x1 + x2) / 2);
}

const GRID = 24;

function snapVal(v, on) {
	if (!on)
		return v;
	return Math.round(Number(v) / GRID) * GRID;
}

function fan(cy, i, n, step) {
	if (!(n > 1))
		return cy;
	return cy + (i - (n - 1) / 2) * step;
}

function curveCtrl(x1, y1, x2, y2, bulge) {
	const mx = (x1 + x2) / 2, my = (y1 + y2) / 2;
	const dx = x2 - x1, dy = y2 - y1;
	const len = Math.hypot(dx, dy) || 1;
	return { cx: mx - dy / len * bulge, cy: my + dx / len * bulge };
}

function qPoint(t, x1, y1, cx, cy, x2, y2) {
	const u = 1 - t;
	return {
		x: u * u * x1 + 2 * u * t * cx + t * t * x2,
		y: u * u * y1 + 2 * u * t * cy + t * t * y2
	};
}

function qAngle(t, x1, y1, cx, cy, x2, y2) {
	const dx = 2 * (1 - t) * (cx - x1) + 2 * t * (x2 - cx);
	const dy = 2 * (1 - t) * (cy - y1) + 2 * t * (y2 - cy);
	return Math.atan2(dy, dx) * 180 / Math.PI;
}

function perpOffset(x1, y1, x2, y2, d) {
	const dx = x2 - x1, dy = y2 - y1;
	const len = Math.hypot(dx, dy) || 1;
	const nx = -dy / len * d, ny = dx / len * d;
	return { x1: x1 + nx, y1: y1 + ny, x2: x2 + nx, y2: y2 + ny };
}

function polyLen(pts) {
	let n = 0;
	for (let i = 1; i < pts.length; i++)
		n += Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y);
	return n;
}

function polyAt(pts, u) {
	const total = polyLen(pts) || 1;
	let dist = Math.max(0, Math.min(1, u)) * total;
	for (let i = 1; i < pts.length; i++) {
		const x1 = pts[i - 1].x, y1 = pts[i - 1].y, x2 = pts[i].x, y2 = pts[i].y;
		const seg = Math.hypot(x2 - x1, y2 - y1) || 1e-6;
		if (dist <= seg) {
			const t = dist / seg;
			return {
				x: x1 + (x2 - x1) * t,
				y: y1 + (y2 - y1) * t,
				ang: Math.atan2(y2 - y1, x2 - x1) * 180 / Math.PI
			};
		}
		dist -= seg;
	}
	const a = pts[pts.length - 2], b = pts[pts.length - 1];
	return { x: b.x, y: b.y, ang: Math.atan2(b.y - a.y, b.x - a.x) * 180 / Math.PI };
}

function offsetPoly(pts, d) {
	const out = [];
	for (let i = 0; i < pts.length; i++) {
		let nx = 0, ny = 0, c = 0;
		if (i > 0) {
			const dx = pts[i].x - pts[i - 1].x, dy = pts[i].y - pts[i - 1].y;
			const len = Math.hypot(dx, dy) || 1;
			nx += -dy / len;
			ny += dx / len;
			c++;
		}
		if (i + 1 < pts.length) {
			const dx = pts[i + 1].x - pts[i].x, dy = pts[i + 1].y - pts[i].y;
			const len = Math.hypot(dx, dy) || 1;
			nx += -dy / len;
			ny += dx / len;
			c++;
		}
		c = c || 1;
		out.push({ x: pts[i].x + nx / c * d, y: pts[i].y + ny / c * d });
	}
	return out;
}

function polyPoints(pts) {
	return pts.map(p => p.x + ',' + p.y).join(' ');
}

function reversePts(pts) {
	return pts.slice().reverse();
}

function orthoHVH(x1, y1, x2, y2, mx) {
	const mid = mx != null ? mx : (x1 + x2) / 2;
	return [
		{ x: x1, y: y1 },
		{ x: mid, y: y1 },
		{ x: mid, y: y2 },
		{ x: x2, y: y2 }
	];
}

function polyMid(pts) {
	return polyAt(pts, 0.5);
}

function railsStraight(x1, y1, x2, y2, d) {
	const dx = x2 - x1, dy = y2 - y1, len = Math.hypot(dx, dy) || 1;
	const nx = -dy / len * d, ny = dx / len * d;
	return {
		a: [{ x: x1 + nx, y: y1 + ny }, { x: x2 + nx, y: y2 + ny }],
		b: [{ x: x1 - nx, y: y1 - ny }, { x: x2 - nx, y: y2 - ny }]
	};
}

function railsHVH(x1, y1, x2, y2, mx, d) {
	if (Math.abs(y1 - y2) < 1)
		return {
			a: [{ x: x1, y: y1 + d }, { x: x2, y: y2 + d }],
			b: [{ x: x1, y: y1 - d }, { x: x2, y: y2 - d }]
		};
	if (Math.abs(x1 - x2) < 1)
		return {
			a: [{ x: x1 + d, y: y1 }, { x: x2 + d, y: y2 }],
			b: [{ x: x1 - d, y: y1 }, { x: x2 - d, y: y2 }]
		};
	const mid = mx != null ? mx : (x1 + x2) / 2;
	const sy = y2 >= y1 ? 1 : -1;
	return {
		a: [
			{ x: x1, y: y1 + d },
			{ x: mid + d * sy, y: y1 + d },
			{ x: mid + d * sy, y: y2 + d },
			{ x: x2, y: y2 + d }
		],
		b: [
			{ x: x1, y: y1 - d },
			{ x: mid - d * sy, y: y1 - d },
			{ x: mid - d * sy, y: y2 - d },
			{ x: x2, y: y2 - d }
		]
	};
}

const ETH_PORT = 'M37.8,5.9l-1.9-4.1c-0.2-0.4-0.5-0.7-0.8-1c-0.5-0.2-0.9-0.3-1.3-0.3H16.1c-0.4,0-0.9,0.1-1.2,0.4c-0.4,0.2-0.7,0.6-0.8,1L12.2,6c-0.2,0.4-0.5,0.7-0.8,1c-0.4,0.2-0.8,0.4-1.2,0.4H3.3C2.7,7.2,2.1,7.5,1.7,7.9C1.2,8.3,1,8.9,1,9.5v27.7c0,0.6,0.2,1.2,0.7,1.6c0.4,0.4,1,0.7,1.6,0.7h43.4c0.6,0,1.2-0.2,1.6-0.7c0.4-0.4,0.7-1,0.7-1.6V9.5c0-0.3-0.1-0.6-0.2-0.9c-0.1-0.3-0.3-0.5-0.5-0.7c-0.2-0.2-0.5-0.4-0.7-0.5c-0.3-0.1-0.6-0.2-0.9-0.2h-6.9c-0.4,0-0.9-0.1-1.2-0.4C38.2,6.6,37.9,6.3,37.8,5.9z';

const TOPO_ICON = {
	cloud: { src: 'vendor/topo-icons/cloud.svg', w: 76, h: 54 },
	router: { src: 'vendor/topo-icons/router.svg', w: 98, h: 40 },
	switch: { src: 'vendor/topo-icons/switch.svg', w: 120, h: 88 },
	host: { src: 'vendor/topo-icons/client-pc.svg', w: 48, h: 36 },
	phone: { src: 'vendor/topo-icons/client-phone.svg', w: 30, h: 50 },
	'xiaomi-phone': { src: 'vendor/topo-icons/client-xiaomi-phone.svg', w: 30, h: 50 },
	'apple-phone': { src: 'vendor/topo-icons/client-apple-phone.svg', w: 30, h: 50 },
	'huawei-phone': { src: 'vendor/topo-icons/client-huawei-phone.svg', w: 30, h: 50 },
	'windows-pc': { src: 'vendor/topo-icons/client-windows-pc.svg', w: 48, h: 36 },
	'macos-pc': { src: 'vendor/topo-icons/client-macos-pc.svg', w: 48, h: 36 },
	'huawei-ap': { src: 'vendor/topo-icons/client-huawei-ap.svg', w: 40, h: 40 },
	nvr: { src: 'vendor/topo-icons/client-nvr.svg', w: 44, h: 36 }
};

const HUAWEI_OUI = {
	f40e11: 1, '00e0fc': 1, '04c06f': 1, '286ed4': 1, '4846fb': 1,
	'643e8c': 1, '708cb6': 1, '80717a': 1, '9c28ef': 1, ace215: 1, c8d15e: 1
};

function topoIconKind(kind, client) {
	if (kind === 'client' || kind === 'host')
		return clientIconKind(client);
	return kind;
}

function topoIconScale(kind) {
	if (kind === 'router')
		return 1.85;
	if (kind === 'switch')
		return 1.7;
	if (kind === 'cloud')
		return 1.55;
	if (kind === 'phone' || /phone$/.test(kind) || kind === 'huawei-ap' || kind === 'nvr')
		return 1.15;
	return 1.25;
}

function topoUseIconSkin(kind, key) {
	return kind === 'cloud' || kind === 'router' || kind === 'switch'
		|| key === 'internet' || key === 'gateway' || key === 'switch';
}

function macOui6(mac) {
	const m = String(mac || '').replace(/[^0-9a-fA-F]/g, '').toLowerCase();
	return m.length >= 6 ? m.slice(0, 6) : '';
}

function macRandomized(mac) {
	const m = String(mac || '').replace(/[^0-9a-fA-F]/g, '');
	if (m.length < 2)
		return false;
	return (parseInt(m.slice(0, 2), 16) & 0x02) !== 0;
}

function clientIconKind(c) {
	if (!c)
		return 'host';
	const n = String(clientHostname(c) || c.name || c.hostname || '').toLowerCase();
	const mac = String(c.mac || '');
	const oui = macOui6(mac);
	if (/tilink|tiandy|hikvision|ezviz|dahua|\bnvr\b|\bdvr\b|\bipc\b|camera|录像|\bh6c[-_]/.test(n))
		return 'nvr';
	if (/\bap\b|access.?point|wifi.?ap|wireless.?ap/.test(n))
		return 'huawei-ap';
	if (/iphone|ipad/.test(n))
		return 'apple-phone';
	if (/macbook|imac|mac-mini|macos|macintosh/.test(n))
		return 'macos-pc';
	if (/xiaomi|redmi|\bmi[-_]|\bmi\d|poco|mix\d/.test(n))
		return 'xiaomi-phone';
	if (/huawei|honor|rong-yao|[a-z0-9]{2,6}-a[ln]\d{2}|[a-z0-9]{2,6}-tl\d{2}/.test(n))
		return 'huawei-phone';
	if (/desktop-|laptop-|windows|\bwin-|\bpc-/.test(n))
		return 'windows-pc';
	if (/vivo|oppo|oneplus|iqoo|galaxy|pixel|android|phone|mobile/.test(n))
		return 'phone';
	if (!n && !macRandomized(mac)) {
		if (HUAWEI_OUI[oui])
			return 'huawei-ap';
		if (oui === '00e04c')
			return 'windows-pc';
	}
	return 'host';
}

function nicFace(x, y, rot, s) {
	const rad = (Number(rot) || 0) * Math.PI / 180;
	const d = 20 * (s || 1);
	return { x: x + Math.sin(rad) * d, y: y + Math.cos(rad) * d };
}

function speedColor(mbps, up) {
	if (up === false)
		return '#dc2626';
	const n = Number(mbps) || 0;
	if (n >= 8000)
		return '#7c3aed';
	if (n >= 2000)
		return '#2563eb';
	if (n >= 800)
		return '#16a34a';
	if (n >= 10)
		return '#ca8a04';
	return '#64748b';
}

function speedTag(mbps) {
	const n = Number(mbps) || 0;
	if (n >= 8000)
		return '10G';
	if (n >= 2000)
		return '2.5G';
	if (n >= 800)
		return '1G';
	if (n >= 80)
		return '100M';
	if (n > 0)
		return n + 'M';
	return '';
}

function healthColor(h) {
	if (h === 'ok')
		return '#16a34a';
	if (h === 'warn')
		return '#ca8a04';
	return '#dc2626';
}

function trunc(s, n) {
	s = String(s || '');
	return s.length > n ? s.slice(0, n - 1) + '…' : s;
}

function protoLabel(p) {
	p = (p || '').toLowerCase();
	if (p === 'pppoe')
		return 'PPPoE';
	if (p === 'dhcp')
		return 'DHCP';
	if (p === 'static')
		return '静态';
	return p || '-';
}

function fmtLatency(v) {
	if (v == null || v === '')
		return '—';
	const n = Number(v);
	if (!isFinite(n))
		return String(v);
	return (n < 10 ? n.toFixed(1) : n.toFixed(0)) + ' ms';
}

function fmtBootUptime(s) {
	s = Math.floor(Number(s) || 0);
	if (s < 0)
		s = 0;
	const d = Math.floor(s / 86400);
	const h = Math.floor((s % 86400) / 3600);
	const m = Math.floor((s % 3600) / 60);
	const sec = s % 60;
	if (d)
		return d + '天 ' + h + '小时 ' + m + '分';
	if (h)
		return h + '小时 ' + m + '分';
	if (m)
		return m + '分 ' + sec + '秒';
	return sec + '秒';
}

const WEEKDAY_ZH = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];

function pad2(n) {
	n = Math.floor(Number(n) || 0);
	return (n < 10 ? '0' : '') + n;
}

function fmtStatusClock(ms) {
	const d = new Date(ms);
	if (!isFinite(d.getTime()))
		return '--';
	return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) + ' '
		+ pad2(d.getHours()) + '：' + pad2(d.getMinutes()) + '：' + pad2(d.getSeconds()) + ' '
		+ WEEKDAY_ZH[d.getDay()];
}

function parseRouterClockMs(sys) {
	sys = sys || {};
	let day = sys.clock_day || '';
	let hms = sys.clock_hms || '';
	if ((!day || !hms) && sys.clock) {
		const m = /^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2})$/.exec(String(sys.clock));
		if (m) {
			day = m[1];
			hms = m[2];
		}
	}
	const dm = /^(\d{4})-(\d{2})-(\d{2})$/.exec(day);
	const tm = /^(\d{2}):(\d{2}):(\d{2})$/.exec(hms);
	if (!dm || !tm)
		return null;
	const ms = new Date(+dm[1], +dm[2] - 1, +dm[3], +tm[1], +tm[2], +tm[3]).getTime();
	return isFinite(ms) ? ms : null;
}

function fmtUptime(s) {
	s = Math.floor(Number(s) || 0);
	const d = Math.floor(s / 86400);
	const h = Math.floor((s % 86400) / 3600);
	const m = Math.floor((s % 3600) / 60);
	if (d)
		return d + '天' + h + '时';
	if (h)
		return h + '时' + m + '分';
	return m + '分钟';
}

function strokeW(bps) {
	return 2.6;
}

function flowDash(px) {
	const run = Math.max(5, Math.min(9, 8 - px * 0.015));
	const gap = Math.max(6, run * 1.15);
	return run.toFixed(1) + ' ' + gap.toFixed(1);
}

function flowStrokeWidth(px) {
	return { main: 2.4 };
}

function flowCount(bps) {
	const mbit = Math.max(0, Number(bps) || 0) / 1e6;
	if (mbit < 0.00005)
		return 0;
	if (mbit >= 100)
		return 3;
	return 2;
}

function memPct(info) {
	const mem = (info && info.memory) || {};
	const total = Number(mem.total) || 0;
	const avail = Number(mem.available != null ? mem.available : mem.free) || 0;
	return total ? Math.round((Math.max(0, total - avail) / total) * 100) : 0;
}

function isRpcAbort(e) {
	const m = e && e.message ? String(e.message) : String(e || '');
	return /aborted/i.test(m) || e === '0' || (e && e.name === 'AbortError');
}

function rpcSafe(promise, fallback) {
	return Promise.resolve(promise).catch(function(e) {
		if (isRpcAbort(e))
			return fallback;
		throw e;
	});
}

return view.extend({
	title: null,
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	prev: null,
	polling: false,
	animating: false,
	board: {},
	info: {},
	flows: [],
	selected: null,
	selectedKind: null,
	pos: {},
	fields: {},
	snapGrid: true,
	posKey: 'lede-topo-pos-v1',
	fieldKey: 'lede-topo-fields-v2',
	snapKey: 'lede-topo-snap',
	linkKey: 'lede-topo-links-v6',
	lockKey: 'lede-topo-lock',
	links: {},
	layoutLock: false,

	loadStore(key, fallback) {
		try {
			return Object.assign(fallback, JSON.parse(localStorage.getItem(key) || '{}') || {});
		}
		catch (e) {
			return fallback;
		}
	},

	saveStore(key, obj) {
		try {
			localStorage.setItem(key, JSON.stringify(obj || {}));
		}
		catch (e) {}
	},

	layoutPayload() {
		return {
			saved: 1,
			pos: this.pos || {},
			fields: this.fields || {},
			links: this.links || {},
			snap: this.snapGrid ? '1' : '0',
			lock: this.layoutLock ? '1' : '0',
			topn: this.topN()
		};
	},

	writeLayoutLocal() {
		this.saveStore(this.posKey, this.pos);
		this.saveStore(this.fieldKey, this.fields);
		this.saveStore(this.linkKey, this.links);
		this.saveSnap();
		this.saveLock();
		this.saveTopN();
	},

	schedulePersist() {
		this.writeLayoutLocal();
		if (this._persistTimer)
			clearTimeout(this._persistTimer);
		this._persistTimer = setTimeout(L.bind(function() {
			this._persistTimer = null;
			callLayoutSet(this.layoutPayload()).catch(() => {});
		}, this), 400);
	},

	confirmAction(title, text, run) {
		ui.showModal(title, [
			E('p', {}, text),
			E('div', { 'class': 'right' }, [
				E('button', { 'class': 'btn', 'click': ui.hideModal }, '取消'),
				E('button', {
					'class': 'btn cbi-button cbi-button-negative',
					'click': function() {
						ui.hideModal();
						run();
					}
				}, '确定')
			])
		]);
	},

	restartWan(name) {
		const self = this;
		this.confirmAction('重启网卡', '确定重启 WAN 口 ' + name + '？该线路会短暂掉线。', function() {
			callWanRestart(name).catch(function() {});
		});
	},

	rebootGateway() {
		this.confirmAction('重启网关', '确定重启网关设备？所有网络会中断，稍后自动恢复。', function() {
			callGatewayReboot('overview').catch(function() {});
		});
	},

	drawRestartChip(layer, x, y, label, onClick) {
		const w = 40, h = 16;
		const g = svgEl('g', { style: 'cursor:pointer' });
		g.appendChild(svgEl('rect', {
			x: x - w / 2, y: y, width: w, height: h, rx: 3,
			fill: '#2563eb', stroke: '#1d4ed8', 'stroke-width': 0.6,
			'pointer-events': 'all'
		}));
		g.appendChild(svgEl('text', {
			x: x, y: y + 12, 'text-anchor': 'middle',
			'font-size': 10, 'font-weight': 700, fill: '#fff',
			'pointer-events': 'none'
		}, [label]));
		g.addEventListener('click', function(ev) {
			ev.stopPropagation();
			ev.preventDefault();
			onClick();
		});
		g.addEventListener('pointerdown', function(ev) {
			ev.stopPropagation();
		});
		layer.appendChild(g);
	},

	hydrateLayout(src, fromServer) {
		const fallback = topoPosFallback();
		src = src || {};
		if (fromServer && src.saved) {
			this.pos = Object.assign({}, fallback, src.pos || {});
			this.fields = Object.assign({}, TOPO_FIELDS_TEMPLATE, src.fields && typeof src.fields === 'object' ? src.fields : {});
			this.links = Object.assign({}, TOPO_LINKS_TEMPLATE, src.links && typeof src.links === 'object' ? src.links : {});
			this.snapGrid = src.snap == null ? true : src.snap !== '0' && src.snap !== false;
			this.layoutLock = src.lock === '1' || src.lock === true;
			const n = Number(src.topn);
			this._topN = (n >= 1 && n <= CLI_TOPN_MAX) ? Math.floor(n) : TOPO_DEFAULT_TOPN;
			this.migrateLanFlowDir();
			this.migrateGwSwSize();
			this.migrateWanSumLayout();
			this.writeLayoutLocal();
			return;
		}
		this.loadPos();
		this.loadFields();
		this.loadSnap();
		this.loadLock();
		this.loadTopN();
		this.loadLinks();
		let hadLocal = false;
		try {
			hadLocal = !!(localStorage.getItem(this.posKey) || localStorage.getItem(this.linkKey) || localStorage.getItem(this.fieldKey));
		} catch (e) {}
		if (hadLocal)
			this.schedulePersist();
		this.migrateLanFlowDir();
		this.migrateGwSwSize();
		this.migrateWanSumLayout();
	},

	loadPos() {
		this.pos = this.loadStore(this.posKey, topoPosFallback());
	},
	savePos() {
		this.writeLayoutLocal();
		if (this._persistTimer) {
			clearTimeout(this._persistTimer);
			this._persistTimer = null;
		}
		callLayoutSet(this.layoutPayload()).catch(() => {});
	},
	loadFields() { this.fields = this.loadStore(this.fieldKey, TOPO_FIELDS_TEMPLATE); },
	saveFields() { this.schedulePersist(); },
	loadSnap() {
		try {
			const v = localStorage.getItem(this.snapKey);
			this.snapGrid = v == null ? true : v !== '0';
		} catch (e) {
			this.snapGrid = true;
		}
	},
	saveSnap() {
		try { localStorage.setItem(this.snapKey, this.snapGrid ? '1' : '0'); } catch (e) {}
	},
	loadLock() {
		try {
			this.layoutLock = localStorage.getItem(this.lockKey) === '1';
		} catch (e) {
			this.layoutLock = false;
		}
	},
	saveLock() {
		try { localStorage.setItem(this.lockKey, this.layoutLock ? '1' : '0'); } catch (e) {}
	},
	loadLinks() { this.links = this.loadStore(this.linkKey, TOPO_LINKS_TEMPLATE); },
	saveLinks() { this.schedulePersist(); },

	migrateLanFlowDir() {
		this.links = this.links || {};
		if (this.links._lanDir === 2)
			return;
		const L = this.links['link:lan'];
		if (L && isFinite(L.x1) && isFinite(L.x2))
			this.links['link:lan'] = { x1: L.x2, y1: L.y2, x2: L.x1, y2: L.y1 };
		this.links._lanDir = 2;
		this.schedulePersist();
	},

	migrateWanSumLayout() {
		let changed = false;
		if (!this.fields)
			this.fields = {};
		let cur = this.fields['wan-sum'];
		if (!Array.isArray(cur) || cur.indexOf('rate') < 0) {
			cur = Array.isArray(cur) ? cur.slice() : (FIELD_DEFAULTS.wan_sum || []).slice();
			if (cur.indexOf('title') < 0)
				cur.unshift('title');
			if (cur.indexOf('rate') < 0)
				cur.push('rate');
			this.fields['wan-sum'] = cur;
			changed = true;
		}
		const sum = (this.pos || {})['wan-sum'];
		/* User-placed WAN summary position is stored in /etc/lede-topo.json. */
		if (sum && (sum.user === 1 || sum.user === true || sum.user === '1'))
			return changed ? this.schedulePersist() : undefined;
		const inet = (this.pos || {}).internet;
		if (inet && isFinite(inet.x) && isFinite(inet.y)) {
			const wantX = inet.x + TOPO_TEMPLATE.wanSum.dx;
			const wantY = inet.y + TOPO_TEMPLATE.wanSum.dy;
			if (!sum || !isFinite(sum.x) || !isFinite(sum.y)) {
				this.patchPos('wan-sum', { x: wantX, y: wantY });
				changed = true;
			}
		}
		if (changed)
			this.schedulePersist();
	},

	migrateGwSwSize() {
		const MKEY = 'lede-topo-gwsw-size-v4';
		try {
			if (localStorage.getItem(MKEY) === '1')
				return;
		} catch (e) {}
		let changed = false;
		['gateway', 'switch'].forEach(k => {
			const tmpl = TOPO_TEMPLATE[k];
			if (!tmpl)
				return;
			const p = (this.pos || {})[k] || {};
			const w = Number(p.w), h = Number(p.h);
			const near = function(a, b) {
				return isFinite(a) && Math.abs(a - b) < 3;
			};
			if (!near(w, tmpl.w) || !near(h, tmpl.h)) {
				this.patchPos(k, { w: tmpl.w, h: tmpl.h });
				changed = true;
			}
		});
		try { localStorage.setItem(MKEY, '1'); } catch (e) {}
		if (changed)
			this.schedulePersist();
	},

	linkGeom(key, x1, y1, x2, y2) {
		const L = (this.links || {})[key] || {};
		return {
			x1: x1,
			y1: y1 + (L.ay != null && isFinite(L.ay) ? L.ay : 0),
			x2: x2,
			y2: y2 + (L.by != null && isFinite(L.by) ? L.by : 0),
			mx: L.mx != null && isFinite(L.mx) ? L.mx : (x1 + x2) / 2
		};
	},

	nicState(key, host, dx, dy, defRot) {
		const tmpl = TOPO_NIC_TEMPLATE[key] || {};
		const p = Object.assign({}, tmpl, (this.pos || {})[key] || {});
		let x, y;
		if (p.rel && isFinite(p.x) && isFinite(p.y)) {
			x = host.x + p.x;
			y = host.y + p.y;
		} else if (isFinite(p.x) && isFinite(p.y)) {
			x = p.x;
			y = p.y;
		} else {
			x = host.x + dx;
			y = host.y + dy;
		}
		const rot = isFinite(p.rot) ? p.rot : defRot;
		const s = (p.s >= 0.4 && p.s <= 3) ? p.s : 1;
		const face = nicFace(x, y, rot, s);
		return { x, y, rot, s, jackX: face.x, jackY: face.y };
	},

	patchNic(key, patch) {
		this.pos = this.pos || {};
		const cur = Object.assign({ rel: 1 }, this.pos[key] || {}, patch);
		this.pos[key] = cur;
	},

	nodeScale(key) {
		const s = (this.pos[key] || {}).s;
		if (s >= 0.5 && s <= 2.8)
			return s;
		return 1;
	},

	nodeBox(key, kind, nlines) {
		const n = Math.max(1, nlines || 1);
		const tmpl = TOPO_TEMPLATE[key] || {};
		const defW = tmpl.w || (kind === 'router' ? 68 : (kind === 'switch' ? 68 : (kind === 'cloud' ? 148 : 158)));
		const defH = tmpl.h || (kind === 'router' ? 344 : (kind === 'switch' ? 344 : (kind === 'cloud' ? 118 : 70 + n * 13)));
		const p = (this.pos || {})[key] || {};
		const s = (p.s >= 0.5 && p.s <= 2.8) ? p.s : 1;
		const pw = Number(p.w), ph = Number(p.h);
		const minW = (key === 'gateway' || key === 'switch') ? 64 : 70;
		let w = (pw >= minW && pw <= 960) ? pw : defW * s;
		let h = (ph >= 48 && ph <= 960) ? ph : Math.max(defH, (kind === 'cloud' ? 72 : 70 + n * 13) * s);
		if (key === 'gateway' || key === 'switch') {
			const near = function(a, b) {
				return isFinite(a) && Math.abs(a - b) < 4;
			};
			if (near(w, defW) && near(h, defH))
				return { w: w, h: h };
			if (h < 250 || w > 90)
				return { w: defW * s, h: defH * s };
		}
		return { w: w, h: h };
	},

	patchPos(key, patch, opts) {
		this.pos = this.pos || {};
		const next = Object.assign({}, this.pos[key] || {}, patch);
		if (opts && opts.user)
			next.user = 1;
		this.pos[key] = next;
	},

	topN() {
		const n = Number(this._topN);
		if (n >= 1 && n <= CLI_TOPN_MAX)
			return Math.floor(n);
		return TOPO_DEFAULT_TOPN;
	},

	loadTopN() {
		try {
			const v = Number(localStorage.getItem('lede-topo-topn'));
			this._topN = (v >= 1 && v <= CLI_TOPN_MAX) ? v : TOPO_DEFAULT_TOPN;
		} catch (e) {
			this._topN = TOPO_DEFAULT_TOPN;
		}
	},
	saveTopN() {
		try { localStorage.setItem('lede-topo-topn', String(this.topN())); } catch (e) {}
	},

	fieldStoreKey(key, kind) {
		if (kind === 'host' || (key && (key.indexOf('cli:') === 0 || key === 'cli-more' || key === 'cli-list')))
			return 'cli-list';
		if (kind === 'link_sw_cli' || (key && key.indexOf('link:cli:') === 0) || key === 'link:cli-more')
			return 'link:cli-all';
		return key;
	},

	isClientSel(key, kind) {
		return kind === 'host' || kind === 'link_sw_cli' ||
			(key && (key.indexOf('cli:') === 0 || key.indexOf('link:cli:') === 0 ||
				key === 'cli-more' || key === 'link:cli-more'));
	},

	shown(key, kind) {
		const store = this.fieldStoreKey(key, kind);
		if (this.fields && Object.prototype.hasOwnProperty.call(this.fields, store))
			return (this.fields[store] || []).slice();
		return (FIELD_DEFAULTS[kind] || []).slice();
	},

	hasField(key, kind, id) {
		return this.shown(key, kind).indexOf(id) >= 0;
	},

	toggleField(key, kind, id, on) {
		let cur = this.shown(key, kind);
		if (on && cur.indexOf(id) < 0)
			cur.push(id);
		if (!on)
			cur = cur.filter(x => x !== id);
		this.fields[this.fieldStoreKey(key, kind)] = cur;
		this.saveFields();
	},

	xy(key, x, y) {
		const p = (this.pos || {})[key];
		if (p && isFinite(p.x) && isFinite(p.y))
			return { x: p.x, y: p.y };
		if (key === 'wan-sum' && isFinite(x) && isFinite(y))
			return { x: x, y: y };
		const t = TOPO_TEMPLATE[key];
		if (t && isFinite(t.x) && isFinite(t.y))
			return { x: t.x, y: t.y };
		return { x: x, y: y };
	},

	clientToSvg(svg, cx, cy) {
		const pt = svg.createSVGPoint();
		pt.x = cx;
		pt.y = cy;
		const m = svg.getScreenCTM();
		if (!m)
			return { x: cx, y: cy };
		const p = pt.matrixTransform(m.inverse());
		return { x: p.x, y: p.y };
	},

	load() {
		return Promise.all([
			rpcSafe(callSnapshot(), {}),
			rpcSafe(callBoard(), {}),
			rpcSafe(callLayoutGet(), {})
		]).then(function(res) {
			return [ res[0] || {}, res[1] || {}, res[2] || {} ];
		}).catch(function(e) {
			if (isRpcAbort(e))
				return [ {}, {}, {} ];
			throw e;
		});
	},

	mergeBandixSnap(snap) {
		if (!snap)
			return snap;
		const devs = this._bandixDevices;
		if (!devs || !devs.length)
			return snap;
		const cl = bandixClientsFromDevices(devs);
		return Object.assign({}, snap, {
			clients: cl.clients,
			clients_sum: Object.assign({}, snap.clients_sum || {}, {
				online: cl.online,
				leases: cl.leases
			})
		});
	},

	overlayBandixClientRates(live, zeros) {
		const devs = this._bandixDevices;
		if (!devs || !devs.length || !live)
			return;
		devs.forEach(function(d) {
			const iface = bandixDeviceIface(d);
			if (iface && iface !== 'br-lan')
				return;
			const mac = String(d.mac || '').trim().toLowerCase();
			const ip = bandixFirstIpv4(d);
			const met = d.metrics || {};
			const down = bandixMetricBps(met, true);
			const up = bandixMetricBps(met, false);
			const ids = [];
			if (mac)
				ids.push(mac);
			if (ip)
				ids.push(ip);
			ids.forEach(function(id) {
				const old = live.clients[id] || {};
				live.clients[id] = {
					rx: holdRate(old.rx, down, zeros, 'bc:' + id + ':d'),
					tx: holdRate(old.tx, up, zeros, 'bc:' + id + ':u')
				};
			});
		});
	},

	refreshBandixClients(showErr) {
		if (this._bandixBusy)
			return Promise.resolve();
		this._bandixBusy = true;
		const self = this;
		const q = (TopoBandixDevList.getQuery && this._bandixDevListMounted)
			? TopoBandixDevList.getQuery() : { iface: '', period: '' };
		return Promise.all([
			callBandixDevices(q.iface, q.period).catch(function(e) {
				if (showErr && e && !/aborted/i.test(String(e.message || e)))
					ui.addNotification(null, E('p', {}, 'Bandix 设备列表刷新失败：' + (e.message || String(e))), 'warning');
				return null;
			}),
			callBandixSchedules().catch(function() { return null; })
		]).then(function(res) {
			self._bandixDevices = bandixUnwrap(res[0], self._bandixDevices || []);
			self._bandixSchedules = bandixUnwrap(res[1], self._bandixSchedules || []);
			if (self._bandixDevListMounted)
				TopoBandixDevList.setSharedData(self._bandixDevices, self._bandixSchedules);
			if (self.prev)
				self.paint(self.mergeBandixSnap(self.prev), self.info);
		}).finally(function() {
			self._bandixBusy = false;
		});
	},

	defs() {
		const arrow = function(id, color) {
			const m = svgEl('marker', {
				id: id, markerWidth: '8', markerHeight: '8',
				refX: '7', refY: '4', orient: 'auto', markerUnits: 'userSpaceOnUse'
			});
			m.appendChild(svgEl('polygon', {
				points: '0,1 8,4 0,7', fill: color,
			}));
			return m;
		};
		const pcb = svgEl('linearGradient', { id: 'nic-pcb', x1: '0', y1: '0', x2: '0', y2: '1' });
		pcb.appendChild(svgEl('stop', { offset: '0%', 'stop-color': '#3d8a45' }));
		pcb.appendChild(svgEl('stop', { offset: '100%', 'stop-color': '#1f5a28' }));
		const metal = svgEl('linearGradient', { id: 'nic-metal', x1: '0', y1: '0', x2: '0', y2: '1' });
		metal.appendChild(svgEl('stop', { offset: '0%', 'stop-color': '#d9dee6' }));
		metal.appendChild(svgEl('stop', { offset: '45%', 'stop-color': '#8e96a3' }));
		metal.appendChild(svgEl('stop', { offset: '100%', 'stop-color': '#5c6570' }));
		const gold = svgEl('linearGradient', { id: 'nic-gold', x1: '0', y1: '0', x2: '0', y2: '1' });
		gold.appendChild(svgEl('stop', { offset: '0%', 'stop-color': '#f3d27a' }));
		gold.appendChild(svgEl('stop', { offset: '100%', 'stop-color': '#b8860b' }));
		const eth = svgEl('symbol', { id: 'eth-port', viewBox: '0 0 50 40' });
		eth.appendChild(svgEl('path', {
			d: ETH_PORT,
			fill: 'none',
			stroke: 'currentColor',
			'stroke-width': '2.2',
			'stroke-linejoin': 'round'
		}));
		const gridPat = svgEl('pattern', {
			id: 'topo-grid', width: '24', height: '24', patternUnits: 'userSpaceOnUse'
		});
		gridPat.appendChild(svgEl('circle', {
			cx: '1', cy: '1', r: '0.85', fill: '#94a3b8', opacity: '0.28'
		}));
		return svgEl('defs', {}, [
			gridPat,
			svgEl('filter', { id: 'topo-card-shadow', x: '-8%', y: '-8%', width: '116%', height: '118%' }, [
				svgEl('feDropShadow', {
					dx: '0', dy: '2', stdDeviation: '3',
					'flood-color': '#0f172a', 'flood-opacity': '0.12'
				})
			]),
			svgEl('filter', { id: 'topo-glow' }, [
				svgEl('feGaussianBlur', { stdDeviation: '1.6', result: 'b' }),
				svgEl('feMerge', {}, [
					svgEl('feMergeNode', { in: 'b' }),
					svgEl('feMergeNode', { in: 'SourceGraphic' })
				])
			]),
			svgEl('filter', { id: 'topo-current-glow', x: '-120%', y: '-120%', width: '340%', height: '340%' }, [
				svgEl('feGaussianBlur', { stdDeviation: '3.8', result: 'b' }),
				svgEl('feMerge', {}, [
					svgEl('feMergeNode', { in: 'b' }),
					svgEl('feMergeNode', { in: 'b' }),
					svgEl('feMergeNode', { in: 'b' }),
					svgEl('feMergeNode', { in: 'SourceGraphic' })
				])
			]),
			pcb, metal, gold, eth,
			arrow('topo-arrow-rx', COL_RX),
			arrow('topo-arrow-tx', COL_TX)
		]);
	},

	icon(kind, x, y, color, s, client, sel) {
		s = (s > 0.2 && s < 8) ? s : 1;
		const ik = topoIconKind(kind, client);
		if (ik === 'cloud') {
			const g = svgEl('g', {
				class: 'topo-device-icon topo-cloud-icon',
				transform: 'translate(' + x + ',' + y + ') scale(' + s + ')'
			});
			if (sel) {
				g.appendChild(svgEl('rect', {
					x: -24, y: -18, width: 48, height: 38, rx: 8,
					fill: 'rgba(37,99,235,0.06)', stroke: '#2563eb', 'stroke-width': 1.6
				}));
			}
			const stroke = '#cbd5e1';
			g.appendChild(svgEl('ellipse', {
				cx: -10, cy: 4, rx: 16, ry: 11,
				fill: '#ffffff', stroke: stroke, 'stroke-width': 1.1, opacity: '0.98'
			}));
			g.appendChild(svgEl('ellipse', {
				cx: 12, cy: 6, rx: 14, ry: 10,
				fill: '#ffffff', stroke: stroke, 'stroke-width': 1.1, opacity: '0.98'
			}));
			g.appendChild(svgEl('ellipse', {
				cx: 0, cy: -6, rx: 13, ry: 11,
				fill: '#f8fafc', stroke: stroke, 'stroke-width': 1.1, opacity: '0.98'
			}));
			return g;
		}
		const spec = TOPO_ICON[ik];
		if (spec) {
			const w = spec.w * s;
			const h = spec.h * s;
			const url = L.resource(spec.src);
			const g = svgEl('g', { class: 'topo-device-icon' });
			if (sel) {
				g.appendChild(svgEl('rect', {
					x: x - w / 2 - 8,
					y: y - h / 2 - 8,
					width: w + 16,
					height: h + 16,
					rx: 12,
					fill: 'rgba(37,99,235,0.08)',
					stroke: '#2563eb',
					'stroke-width': 2.2
				}));
			}
			const fo = svgEl('foreignObject', {
				x: x - w / 2,
				y: y - h / 2,
				width: w,
				height: h
			});
			const root = document.createElementNS('http://www.w3.org/1999/xhtml', 'div');
			root.setAttribute('xmlns', 'http://www.w3.org/1999/xhtml');
			root.style.cssText = 'width:100%;height:100%;margin:0;padding:0;line-height:0;overflow:visible;';
			const img = document.createElement('img');
			img.src = url;
			img.alt = ik;
			img.draggable = false;
			img.style.cssText = 'width:100%;height:100%;object-fit:contain;display:block;pointer-events:none;'
				+ (client && client.online === false
					? 'opacity:0.42;filter:grayscale(1);'
					: 'filter:drop-shadow(0 3px 6px rgba(15,23,42,.28));');
			root.appendChild(img);
			fo.appendChild(root);
			g.appendChild(fo);
			return g;
		}
		const g = svgEl('g', { transform: 'translate(' + x + ',' + y + ') scale(' + s + ')', fill: color, stroke: 'none' });
		if (kind === 'wan') {
			g.appendChild(svgEl('rect', { x: -18, y: -8, width: 36, height: 16, rx: 4 }));
			g.appendChild(svgEl('circle', { cx: -8, cy: 0, r: 3, fill: '#fff' }));
			g.appendChild(svgEl('circle', { cx: 8, cy: 0, r: 3, fill: '#fff' }));
		} else {
			g.appendChild(svgEl('rect', { x: -11, y: -8, width: 22, height: 14, rx: 2 }));
			g.appendChild(svgEl('rect', { x: -6, y: 6, width: 12, height: 3, rx: 1 }));
		}
		return g;
	},

	pick(kind, key, bag) {
		const out = [];
		this.shown(key, kind).forEach(id => {
			const v = bag[id];
			if (v == null || v === '')
				return;
			if (Array.isArray(v))
				v.forEach(x => out.push(x));
			else
				out.push(String(v));
		});
		return out;
	},

	addFlow(pts, bps, color, id, capMbps, dir, idleLink, linkUp) {
		const flowDir = dir || flowDirFromId(id);
		const raw = Math.max(0, Number(bps) || 0);
		const st = flowSpeedStyle(raw, capMbps, flowDir);
		const up = linkUp !== false;
		const idle = up && (!!idleLink || raw <= LINK_IDLE_BPS);
		this.flows.push({
			pts: pts,
			bps: raw,
			color: st.px > 0 ? st.color : (color || COL_LINK_IDLE),
			px: idle && raw <= LINK_IDLE_BPS ? LINK_IDLE_FLOW_PX : st.px,
			id: id || '',
			cap: capMbps || 0,
			dir: flowDir,
			idleLink: idle,
			linkUp: up
		});
	},

	linkEnds(key, x1, y1, x2, y2) {
		const L = (this.links || {})[key] || {};
		if (isFinite(L.x1) && isFinite(L.y1) && isFinite(L.x2) && isFinite(L.y2))
			return { x1: L.x1, y1: L.y1, x2: L.x2, y2: L.y2 };
		return { x1: x1, y1: y1, x2: x2, y2: y2 };
	},

	patchLink(key, patch) {
		this.links = this.links || {};
		this.links[key] = Object.assign({}, this.links[key] || {}, patch);
	},

	setLinkEnds(key, x1, y1, x2, y2) {
		this.patchLink(key, {
			x1: snapVal(x1, this.snapGrid),
			y1: snapVal(y1, this.snapGrid),
			x2: snapVal(x2, this.snapGrid),
			y2: snapVal(y2, this.snapGrid)
		});
	},

	linkRateAnchor(key, mid) {
		const L = (this.links || {})[key] || {};
		if (isFinite(L.labelX) && isFinite(L.labelY))
			return { x: L.labelX, y: L.labelY };
		return { x: mid.x, y: mid.y + 3 };
	},

	setLinkRatePos(key, x, y) {
		this.patchLink(key, {
			labelX: snapVal(x, this.snapGrid),
			labelY: snapVal(y, this.snapGrid)
		});
	},

	drawPoly(layer, pts, idleLink) {
		const attr = polyPoints(pts);
		const idle = !!idleLink;
		if (idle) {
			layer.appendChild(svgEl('polyline', {
				points: attr,
				fill: 'none',
				stroke: COL_LINK_IDLE_GLOW,
				'stroke-width': '6',
				'stroke-linecap': 'round',
				'stroke-linejoin': 'round',
				opacity: '0.22',
				class: 'topo-link-idle-glow'
			}));
		}
		layer.appendChild(svgEl('polyline', {
			points: attr,
			fill: 'none',
			stroke: COL_LINK_IDLE,
			'stroke-width': idle ? '3' : '1.8',
			'stroke-linecap': 'round',
			'stroke-linejoin': 'round',
			'stroke-dasharray': idle ? '8 5' : '4 6',
			opacity: idle ? '0.88' : '0.34',
			class: 'topo-link-track' + (idle ? ' topo-link-idle' : '')
		}));
	},

	portBadge(layer, x, y, text, side) {
		if (!text)
			return;
		const label = trunc(String(text), 14);
		const padX = 5, padY = 3, fs = 9;
		const tw = label.length * 5.4 + padX * 2;
		const th = fs + padY * 2;
		const ox = side === 'left' ? -tw - 4 : (side === 'right' ? 4 : -tw / 2);
		const oy = -th / 2;
		const g = svgEl('g', {
			class: 'topo-port-badge',
			transform: 'translate(' + x + ',' + y + ')'
		});
		g.appendChild(svgEl('rect', {
			x: ox, y: oy, width: tw, height: th, rx: 3,
			fill: '#1e293b', opacity: '0.94'
		}));
		g.appendChild(svgEl('text', {
			x: ox + tw / 2, y: oy + th / 2 + 3,
			'text-anchor': 'middle',
			'font-size': fs,
			'font-family': RATE_FONT,
			'font-weight': 650,
			fill: '#f8fafc'
		}, [label]));
		layer.appendChild(g);
	},

	deviceArt(kind, cx, cy, w, h, tone, client) {
		const g = svgEl('g', { class: 'topo-device-art' });
		const x = cx - w / 2;
		const y = cy - h / 2;
		const ok = tone !== 'bad' && tone !== 'warn';
		if (kind === 'client' || kind === 'host') {
			const phone = client && /phone$/.test(clientIconKind(client));
			if (phone) {
				g.appendChild(svgEl('rect', {
					x: cx - w * 0.18, y: cy - h * 0.42, width: w * 0.36, height: h * 0.84, rx: 4,
					fill: '#334155', stroke: '#0f172a', 'stroke-width': 1.2
				}));
				g.appendChild(svgEl('rect', {
					x: cx - w * 0.14, y: cy - h * 0.34, width: w * 0.28, height: h * 0.62, rx: 2,
					fill: '#64748b'
				}));
			} else {
				g.appendChild(svgEl('rect', {
					x: x + 2, y: y + h * 0.18, width: w - 4, height: h * 0.72, rx: 2,
					fill: '#475569', stroke: '#1e293b', 'stroke-width': 1.2
				}));
				g.appendChild(svgEl('rect', {
					x: x + w * 0.28, y: y + 2, width: w * 0.44, height: h * 0.22, rx: 1,
					fill: '#64748b', stroke: '#334155', 'stroke-width': 1
				}));
			}
			return g;
		}
		if (kind === 'router' || kind === 'switch') {
			const body = svgEl('g', {});
			body.appendChild(svgEl('rect', {
				x: x, y: y, width: w, height: h, rx: 5,
				fill: '#b8c2cc', stroke: '#475569', 'stroke-width': 1.6
			}));
			body.appendChild(svgEl('rect', {
				x: x + 4, y: y + 4, width: w - 8, height: h - 8, rx: 3,
				fill: '#1e293b', stroke: '#334155', 'stroke-width': 1
			}));
			body.appendChild(svgEl('rect', {
				x: x + 8, y: y + 8, width: w - 16, height: 14, rx: 2,
				fill: '#0f172a', stroke: '#475569', 'stroke-width': 0.8
			}));
			const ledN = Math.max(4, Math.min(10, Math.floor((w - 12) / 6)));
			for (let i = 0; i < ledN; i++) {
				const span = Math.max(w - 24, 1);
				body.appendChild(svgEl('circle', {
					cx: x + 12 + (ledN <= 1 ? 0 : i * span / (ledN - 1)),
					cy: y + 15,
					r: 2.2,
					fill: ok ? '#22c55e' : (tone === 'warn' ? '#eab308' : '#ef4444')
				}));
			}
			const rows = 3;
			const cols = Math.max(6, Math.min(16, Math.floor((w - 20) / 4)));
			const portW = Math.min(8, (w - 28) / cols);
			const portH = 6;
			const rowGap = 12;
			const portTop = y + h - 18 - (rows - 1) * rowGap;
			for (let row = 0; row < rows; row++) {
				for (let col = 0; col < cols; col++) {
					const px = x + 10 + col * ((w - 20) / cols);
					const py = portTop - row * rowGap;
					body.appendChild(svgEl('rect', {
						x: px, y: py, width: portW, height: portH, rx: 0.8,
						fill: '#020617', stroke: '#64748b', 'stroke-width': 0.5
					}));
					if (col % 2 === 0)
						body.appendChild(svgEl('rect', {
							x: px + 1.5, y: py - 3.5, width: Math.max(2.5, portW - 3), height: 2.2,
							fill: ok ? '#22c55e' : '#64748b'
						}));
				}
			}
			for (let i = 0; i < 8; i++)
				body.appendChild(svgEl('circle', {
					cx: x + w - 10, cy: y + 18 + i * 8, r: 2, fill: '#334155'
				}));
			g.appendChild(body);
			return g;
		}
		const body = svgEl('g', {});
		body.appendChild(svgEl('rect', {
			x: x, y: y, width: w, height: h, rx: 4,
			fill: '#94a3b8', stroke: '#475569', 'stroke-width': 1.4
		}));
		g.appendChild(body);
		return g;
	},

	bindLineClick(layer, x1, y1, x2, y2, key, kind) {
		const self = this;
		const hit = svgEl('line', {
			x1: x1, y1: y1, x2: x2, y2: y2,
			stroke: 'transparent',
			'stroke-width': 18,
			'stroke-linecap': 'round',
			style: 'cursor:pointer'
		});
		hit.addEventListener('click', function(ev) {
			ev.stopPropagation();
			self.selected = key;
			self.selectedKind = kind;
			self.fillDetail();
			if (self.model)
				self.rebuild(document.getElementById('topo-svg'), self.model);
		});
		layer.appendChild(hit);
	},

	bindLineMove(layer, x1, y1, x2, y2, key, kind) {
		const self = this;
		const hit = svgEl('line', {
			x1: x1, y1: y1, x2: x2, y2: y2,
			stroke: 'transparent',
			'stroke-width': 18,
			'stroke-linecap': 'round',
			style: self.layoutLock ? 'cursor:pointer' : 'cursor:grab'
		});
		hit.addEventListener('click', function(ev) {
			ev.stopPropagation();
			if (self._didDrag) {
				self._didDrag = false;
				return;
			}
			self.selected = key;
			self.selectedKind = kind;
			self.fillDetail();
			if (self.model)
				self.rebuild(document.getElementById('topo-svg'), self.model);
		});
		hit.addEventListener('pointerdown', function(ev) {
			if (ev.button || self.layoutLock)
				return;
			ev.stopPropagation();
			ev.preventDefault();
			const svg = document.getElementById('topo-svg');
			if (!svg)
				return;
			self._didDrag = false;
			self._dragging = true;
			const p0 = self.clientToSvg(svg, ev.clientX, ev.clientY);
			try { hit.setPointerCapture(ev.pointerId); } catch (e) {}
			function move(e) {
				const p = self.clientToSvg(svg, e.clientX, e.clientY);
				self.setLinkEnds(key, x1 + p.x - p0.x, y1 + p.y - p0.y, x2 + p.x - p0.x, y2 + p.y - p0.y);
				self._didDrag = true;
				if (!self._dragRaf) {
					self._dragRaf = requestAnimationFrame(function() {
						self._dragRaf = 0;
						if (self.model)
							self.rebuild(svg, self.model);
					});
				}
			}
			function up() {
				window.removeEventListener('pointermove', move);
				window.removeEventListener('pointerup', up);
				self._dragging = false;
				if (self._didDrag)
					self.saveLinks();
			}
			window.addEventListener('pointermove', move);
			window.addEventListener('pointerup', up);
		});
		layer.appendChild(hit);
	},

	bindLinkRateDrag(hit, key, kind, mid, anchor) {
		const self = this;
		hit.addEventListener('click', function(ev) {
			ev.stopPropagation();
			if (self._didDrag) {
				self._didDrag = false;
				return;
			}
			self.selected = key;
			self.selectedKind = kind;
			self.fillDetail();
			if (self.model)
				self.rebuild(document.getElementById('topo-svg'), self.model);
		});
		hit.addEventListener('pointerdown', function(ev) {
			if (ev.button || self.layoutLock)
				return;
			ev.stopPropagation();
			ev.preventDefault();
			const svg = document.getElementById('topo-svg');
			if (!svg)
				return;
			self._didDrag = false;
			self._dragging = true;
			self.selected = key;
			self.selectedKind = kind;
			const p0 = self.clientToSvg(svg, ev.clientX, ev.clientY);
			const a0 = { x: anchor.x, y: anchor.y };
			try { hit.setPointerCapture(ev.pointerId); } catch (e) {}
			function move(e) {
				const p = self.clientToSvg(svg, e.clientX, e.clientY);
				self.setLinkRatePos(key, a0.x + p.x - p0.x, a0.y + p.y - p0.y);
				self._didDrag = true;
				if (!self._dragRaf) {
					self._dragRaf = requestAnimationFrame(function() {
						self._dragRaf = 0;
						if (self.model)
							self.rebuild(svg, self.model);
					});
				}
			}
			function up() {
				window.removeEventListener('pointermove', move);
				window.removeEventListener('pointerup', up);
				self._dragging = false;
				if (self._didDrag)
					self.saveLinks();
				self.fillDetail();
			}
			window.addEventListener('pointermove', move);
			window.addEventListener('pointerup', up);
		});
	},

	lineEndHandles(x1, y1, x2, y2, key, kind) {
		const dest = this._handleLayer;
		if (!dest || this.layoutLock)
			return;
		const self = this;
		[{ x: x1, y: y1, which: 'a' }, { x: x2, y: y2, which: 'b' }].forEach(ep => {
			const show = self._lineGrip === key;
			const el = svgEl('rect', {
				x: ep.x - 7, y: ep.y - 7, width: 14, height: 14, rx: 2,
				fill: show ? '#fff' : '#ffffff',
				'fill-opacity': show ? '1' : '0',
				stroke: show ? '#2563eb' : 'none',
				'stroke-width': show ? 1.6 : 0,
				style: 'cursor:move',
				'pointer-events': 'all'
			});
			el.addEventListener('pointerdown', function(ev) {
				if (ev.button || self.layoutLock)
					return;
				ev.stopPropagation();
				ev.preventDefault();
				const svg = document.getElementById('topo-svg');
				self.selected = key;
				self.selectedKind = kind;
				self._lineGrip = key;
				self._didDrag = false;
				self._dragging = true;
				try { el.setPointerCapture(ev.pointerId); } catch (e) {}
				function move(e) {
					const p = self.clientToSvg(svg, e.clientX, e.clientY);
					const x = snapVal(p.x, self.snapGrid);
					const y = snapVal(p.y, self.snapGrid);
					if (ep.which === 'a')
						self.setLinkEnds(key, x, y, x2, y2);
					else
						self.setLinkEnds(key, x1, y1, x, y);
					self._didDrag = true;
					if (!self._dragRaf) {
						self._dragRaf = requestAnimationFrame(function() {
							self._dragRaf = 0;
							if (self.model)
								self.rebuild(svg, self.model);
						});
					}
				}
				function up() {
					window.removeEventListener('pointermove', move);
					window.removeEventListener('pointerup', up);
					self._dragging = false;
					self._lineGrip = null;
					if (self._didDrag)
						self.saveLinks();
					if (self.model)
						self.rebuild(svg, self.model);
					self.fillDetail();
				}
				window.addEventListener('pointermove', move);
				window.addEventListener('pointerup', up);
			});
			dest.appendChild(el);
		});
	},

	drawPipe(layer, x1, y1, x2, y2, color, bps, live, key, kind, snap, width, opt) {
		opt = opt || {};
		let e;
		if (snap) {
			e = { x1: x1, y1: y1, x2: x2, y2: y2 };
		} else {
			e = this.linkEnds(key, x1, y1, x2, y2);
		}
		const pts = linkRoute(e.x1, e.y1, e.x2, e.y2);
		const flowBps = Math.max(0, Number(bps) || 0);
		const linkUp = opt.linkUp !== false;
		const idleLink = linkUp && linkTrafficIdle(flowBps, 0);
		this.drawPoly(layer, pts, idleLink);
		if (snap)
			this.bindLineClick(layer, e.x1, e.y1, e.x2, e.y2, key, kind);
		else {
			this.bindLineMove(layer, e.x1, e.y1, e.x2, e.y2, key, kind);
			this.lineEndHandles(e.x1, e.y1, e.x2, e.y2, key, kind);
		}
		this.addFlow(pts, flowBps, color, key, opt.cap, null, idleLink, linkUp);
		return polyMid(pts);
	},

	drawDuplex(layer, x1, y1, x2, y2, rx, tx, live, key, kind, opt) {
		opt = opt || {};
		const gap = opt.gap != null ? opt.gap : 6;
		const e = this.linkEnds(key, x1, y1, x2, y2);
		const mx = opt.midX != null ? opt.midX : (e.x1 + e.x2) / 2;
		const rails = railsHVH(e.x1, e.y1, e.x2, e.y2, mx, gap);
		const down = rails.a;
		const upRail = reversePts(rails.b);
		const rxBps = Math.max(0, Number(rx) || 0);
		const txBps = Math.max(0, Number(tx) || 0);
		const linkUp = opt.linkUp !== false;
		const idleLink = linkUp && linkTrafficIdle(rxBps, txBps);
		this.drawPoly(layer, down, idleLink);
		this.drawPoly(layer, upRail, idleLink);
		this.bindLineMove(layer, e.x1, e.y1, e.x2, e.y2, key, kind);
		this.lineEndHandles(e.x1, e.y1, e.x2, e.y2, key, kind);
		this.addFlow(down, rxBps, null, key + ':rx', opt.capRx, 'rx', idleLink, linkUp);
		this.addFlow(upRail, txBps, null, key + ':tx', opt.capTx, 'tx', idleLink, linkUp);
		return polyMid(down);
	},

	drawLinkFault(layer, mid) {
		if (!mid)
			return;
		const s = 10;
		const g = svgEl('g', { 'class': 'topo-wan-x', 'pointer-events': 'none' });
		g.appendChild(svgEl('line', {
			x1: mid.x - s, y1: mid.y - s, x2: mid.x + s, y2: mid.y + s,
			stroke: '#dc2626', 'stroke-width': 3.4, 'stroke-linecap': 'round'
		}));
		g.appendChild(svgEl('line', {
			x1: mid.x + s, y1: mid.y - s, x2: mid.x - s, y2: mid.y + s,
			stroke: '#dc2626', 'stroke-width': 3.4, 'stroke-linecap': 'round'
		}));
		layer.appendChild(g);
	},

	drawNic(layer, st, bag, speed, up, key, kind, hostKey) {
		const color = speedColor(speed, up);
		const sel = this.selected === key;
		const x = st.x, y = st.y, rot = st.rot, s = st.s;
		bag = bag || {};
		const g = svgEl('g', {
			'class': 'topo-hit',
			'data-key': key,
			style: this.layoutLock ? 'cursor:pointer' : 'cursor:grab'
		});
		g.appendChild(svgEl('rect', {
			x: x - 30 * s, y: y - 26 * s, width: 60 * s, height: 52 * s, rx: 4,
			fill: '#ffffff', 'fill-opacity': '0', stroke: 'none',
			'pointer-events': 'all'
		}));
		const port = svgEl('g', {
			transform: 'translate(' + x + ',' + y + ') rotate(' + rot + ') scale(' + s + ')',
			fill: 'none',
			stroke: color,
			'stroke-width': (2.2 / s).toFixed(2),
			'stroke-linejoin': 'round'
		});
		port.appendChild(svgEl('path', { d: ETH_PORT, transform: 'translate(-25,-20)' }));
		g.appendChild(port);
		const tag = up === false ? '离线' : (speedTag(speed) || '未知');
		g.appendChild(svgEl('text', {
			x: x, y: y + 4 * s,
			'text-anchor': 'middle',
			'font-size': Math.max(9, Math.round(10.5 * s)),
			'font-weight': 800,
			fill: color,
			'pointer-events': 'none'
		}, [tag]));
		let labY = y + 22 * s + 12;
		this.shown(key, kind).forEach(id => {
			if (id === 'speed')
				return;
			if (id === 'rate') {
				const m = this.rateMetrics(9);
				const left = x - m.width / 2;
				this.drawAlignedRate(g, left, labY, '↓', bag.rx, COL_RX, 9, key + ':rx');
				labY += 12;
				this.drawAlignedRate(g, left, labY, '↑', bag.tx, COL_TX, 9, key + ':tx');
				labY += 12;
				return;
			}
			let v = bag[id];
			if (id === 'name')
				v = trunc(bag.name || '', 8);
			if (v == null || v === '')
				return;
			g.appendChild(svgEl('text', {
				x: x, y: labY, 'text-anchor': 'middle',
				'font-size': id === 'name' ? 10 : 9,
				'font-weight': id === 'name' || id === 'status' ? 700 : 600,
				fill: (id === 'status' && up === false) ? color : 'currentColor'
			}, [String(v)]));
			labY += 12;
		});
		this.bindFollow(g, key, kind, hostKey);
		layer.appendChild(g);
		if (sel && !this.layoutLock)
			this.nicHandles(st, key, hostKey);
		return st;
	},

	nicHandles(st, key, hostKey) {
		const dest = this._handleLayer;
		if (!dest)
			return;
		const self = this;
		const hx = st.x - Math.sin(st.rot * Math.PI / 180) * (26 * st.s);
		const hy = st.y - Math.cos(st.rot * Math.PI / 180) * (26 * st.s);
		const rotH = svgEl('circle', {
			cx: hx, cy: hy, r: 6,
			fill: '#fff', stroke: '#2563eb', 'stroke-width': 1.6,
			style: 'cursor:grab'
		});
		rotH.addEventListener('pointerdown', function(ev) {
			if (ev.button || self.layoutLock)
				return;
			ev.stopPropagation();
			ev.preventDefault();
			const svg = document.getElementById('topo-svg');
			self._dragging = true;
			self._didDrag = false;
			try { rotH.setPointerCapture(ev.pointerId); } catch (e) {}
			function move(e) {
				const p = self.clientToSvg(svg, e.clientX, e.clientY);
				let ang = Math.atan2(p.x - st.x, p.y - st.y) * 180 / Math.PI;
				if (self.snapGrid)
					ang = Math.round(ang / 15) * 15;
				self.patchNic(key, { rot: ang });
				self._didDrag = true;
				if (!self._dragRaf) {
					self._dragRaf = requestAnimationFrame(function() {
						self._dragRaf = 0;
						if (self.model)
							self.rebuild(svg, self.model);
					});
				}
			}
			function up() {
				window.removeEventListener('pointermove', move);
				window.removeEventListener('pointerup', up);
				self._dragging = false;
				if (self._didDrag)
					self.savePos();
			}
			window.addEventListener('pointermove', move);
			window.addEventListener('pointerup', up);
		});
		const rad = (st.rot + 135) * Math.PI / 180;
		const reach = 28 * st.s;
		const sx = st.x + Math.sin(rad) * reach;
		const sy = st.y + Math.cos(rad) * reach;
		const scH = svgEl('circle', {
			cx: sx, cy: sy, r: 8,
			fill: '#fff', stroke: '#0f172a', 'stroke-width': 1.8,
			style: 'cursor:nwse-resize'
		});
		scH.addEventListener('pointerdown', function(ev) {
			if (ev.button || self.layoutLock)
				return;
			ev.stopPropagation();
			ev.preventDefault();
			const svg = document.getElementById('topo-svg');
			self._dragging = true;
			self._didDrag = false;
			const p0 = self.clientToSvg(svg, ev.clientX, ev.clientY);
			const d0 = Math.max(8, Math.hypot(p0.x - st.x, p0.y - st.y));
			const s0 = st.s || 1;
			try { scH.setPointerCapture(ev.pointerId); } catch (e) {}
			function move(e) {
				const p = self.clientToSvg(svg, e.clientX, e.clientY);
				let ns = s0 * Math.hypot(p.x - st.x, p.y - st.y) / d0;
				ns = Math.max(0.5, Math.min(2.8, ns));
				self.patchNic(key, { s: Math.round(ns * 20) / 20 });
				self._didDrag = true;
				if (!self._dragRaf) {
					self._dragRaf = requestAnimationFrame(function() {
						self._dragRaf = 0;
						if (self.model)
							self.rebuild(svg, self.model);
					});
				}
			}
			function up() {
				window.removeEventListener('pointermove', move);
				window.removeEventListener('pointerup', up);
				self._dragging = false;
				if (self._didDrag)
					self.savePos();
			}
			window.addEventListener('pointermove', move);
			window.addEventListener('pointerup', up);
		});
		dest.appendChild(rotH);
		dest.appendChild(scH);
	},

	bindFollow(g, key, kind, hostKey) {
		const self = this;
		g.addEventListener('click', function(ev) {
			if (self._didDrag) {
				self._didDrag = false;
				ev.stopPropagation();
				return;
			}
			ev.stopPropagation();
			self.selected = key;
			self.selectedKind = kind;
			self.fillDetail();
			if (self.model)
				self.rebuild(document.getElementById('topo-svg'), self.model);
		});
		g.addEventListener('pointerdown', function(ev) {
			if (ev.button || self.layoutLock)
				return;
			ev.preventDefault();
			ev.stopPropagation();
			const svg = document.getElementById('topo-svg');
			if (!svg)
				return;
			self._didDrag = false;
			self._dragging = true;
			const start = self.clientToSvg(svg, ev.clientX, ev.clientY);
			const host = (self._nodes && self._nodes[hostKey]) || self.xy(hostKey, 0, 0);
			const cur = self.nicState(key, host, 0, 0, 0);
			const dx = start.x - cur.x, dy = start.y - cur.y;
			function move(e) {
				const p = self.clientToSvg(svg, e.clientX, e.clientY);
				const hx = (self._nodes && self._nodes[hostKey]) || host;
				self.patchNic(key, {
					rel: 1,
					x: snapVal(p.x - dx, self.snapGrid) - hx.x,
					y: snapVal(p.y - dy, self.snapGrid) - hx.y
				});
				self._didDrag = true;
				if (!self._dragRaf) {
					self._dragRaf = requestAnimationFrame(function() {
						self._dragRaf = 0;
						if (self.model)
							self.rebuild(svg, self.model);
					});
				}
			}
			function up() {
				window.removeEventListener('pointermove', move);
				window.removeEventListener('pointerup', up);
				self._dragging = false;
				if (self._didDrag) {
					self.savePos();
					if (self.model)
						self.rebuild(svg, self.model);
				}
			}
			window.addEventListener('pointermove', move);
			window.addEventListener('pointerup', up);
		});
	},

	drawSpeedLegend(layer, canvasW, y) {
		const items = [
			[100, true, '100M'],
			[1000, true, '1G'],
			[2500, true, '2.5G'],
			[10000, true, '10G'],
			[0, false, '离线']
		];
		const step = 58;
		const itemW = 46;
		const total = (items.length - 1) * step + itemW;
		const x0 = Math.max(12, (canvasW || TOPO_CANVAS.w) - 16 - total);
		items.forEach((it, i) => {
			const px = x0 + i * step;
			const col = speedColor(it[0], it[1]);
			const g = svgEl('g', {
				transform: 'translate(' + px + ',' + (y + 8) + ') scale(0.38)',
				fill: 'none', stroke: col, 'stroke-width': '2.4', 'stroke-linejoin': 'round'
			});
			g.appendChild(svgEl('path', { d: ETH_PORT, transform: 'translate(-25,-20)' }));
			layer.appendChild(g);
			layer.appendChild(svgEl('text', {
				x: px + 14, y: y + 14,
				'font-size': 11, fill: 'currentColor'
			}, [it[2]]));
		});
		if (!this._snapCk || !this._lockCk)
			return;
		const fo = svgEl('foreignObject', {
			x: x0,
			y: y + 26,
			width: Math.max(total, 240),
			height: 26
		});
		const bar = E('div', { 'class': 'topo-layout-ops' }, [
			E('label', { 'class': 'topo-opt' }, [this._snapCk, ' 网格对齐']),
			E('label', { 'class': 'topo-opt' }, [this._lockCk, ' 锁定布局'])
		]);
		bar.addEventListener('click', function(ev) { ev.stopPropagation(); });
		bar.addEventListener('pointerdown', function(ev) { ev.stopPropagation(); });
		fo.appendChild(bar);
		layer.appendChild(fo);
	},

	rateMetrics(size, withUsage) {
		const ch = size * 0.55;
		const glyph = size * 0.58;
		const arrowGap = 1;
		const num = RATE_NUM_W * ch;
		const gap = 2;
		const unit = RATE_UNIT_W * ch;
		const pct = withUsage ? (gap + 6 * ch) : 0;
		return {
			size, ch, glyph, arrowGap, num, gap, unit, pct,
			width: glyph + arrowGap + num + gap + unit + pct
		};
	},

	rateTextAttrs(size, fill) {
		return {
			'font-size': size,
			'font-weight': 700,
			'font-family': RATE_FONT,
			'font-variant-numeric': 'tabular-nums lining-nums',
			fill: fill,
			stroke: 'var(--background-color-high, #ffffff)',
			'stroke-width': 3,
			'stroke-linejoin': 'round',
			'paint-order': 'stroke fill'
		};
	},

	drawAlignedRate(layer, left, y, arrow, bps, fill, size, tag, capMbit) {
		const showPct = Number(capMbit) > 0;
		const m = this.rateMetrics(size, showPct);
		const p = bitrateParts(bps);
		const unitStr = padFig(p.unit, RATE_UNIT_W, 'end');
		const numX = left + m.glyph + m.arrowGap;
		layer.appendChild(svgEl('text', Object.assign(this.rateTextAttrs(size, fill), {
			x: left, y: y, 'text-anchor': 'start'
		}), [arrow]));
		const numEl = svgEl('text', Object.assign(this.rateTextAttrs(size, fill), {
			x: numX, y: y, 'text-anchor': 'start'
		}), [p.num]);
		const unitEl = svgEl('text', Object.assign(this.rateTextAttrs(size, fill), {
			x: numX + m.num + m.gap, y: y, 'text-anchor': 'start'
		}), [unitStr]);
		if (tag) {
			numEl.setAttribute('data-rate-num', tag);
			unitEl.setAttribute('data-rate-unit', tag);
		}
		layer.appendChild(numEl);
		layer.appendChild(unitEl);
		if (showPct) {
			const pct = usagePct(bps, capMbit);
			const pctEl = svgEl('text', Object.assign(this.rateTextAttrs(size, usageColor(pct == null ? 0 : pct)), {
				x: numX + m.num + m.gap + m.unit + m.gap, y: y, 'text-anchor': 'start'
			}), [pct == null ? '' : '(' + pct + '%)']);
			if (tag) {
				pctEl.setAttribute('data-rate-pct', tag);
				pctEl.setAttribute('data-rate-cap', String(capMbit));
			}
			layer.appendChild(pctEl);
		}
	},

	drawRateStack(layer, cx, yUp, yDown, tx, rx, size, prefix, caps) {
		const capTx = caps && Number(caps.tx) > 0 ? Number(caps.tx) : 0;
		const capRx = caps && Number(caps.rx) > 0 ? Number(caps.rx) : 0;
		const left = cx - this.rateMetrics(size, capTx > 0 || capRx > 0).width / 2;
		this.drawAlignedRate(layer, left, yUp, '↑', tx, COL_TX, size, prefix ? prefix + ':tx' : '', capTx);
		this.drawAlignedRate(layer, left, yDown, '↓', rx, COL_RX, size, prefix ? prefix + ':rx' : '', capRx);
	},

	strokeLabel(layer, x, y, txt, fill, size) {
		layer.appendChild(svgEl('text', {
			x: x, y: y, 'text-anchor': 'middle',
			'font-size': size || 11, 'font-weight': 700, fill: fill,
			stroke: 'var(--background-color-high, #ffffff)',
			'stroke-width': 4, 'stroke-linejoin': 'round',
			'paint-order': 'stroke fill'
		}, [txt]));
	},

	decorateLink(layer, mid, key, kind, bag) {
		if (!mid)
			return;
		bag = bag || {};
		const extras = [];
		let wantRate = false;
		let wantUsage = false;
		this.shown(key, kind).forEach(id => {
			const v = bag[id];
			if (id === 'rate') {
				wantRate = true;
				return;
			}
			if (id === 'usage') {
				wantUsage = true;
				return;
			}
			if (id === 'lat') {
				extras.push(v ? String(v) : '延迟 —');
				return;
			}
			if (v == null || v === '')
				return;
			extras.push(String(v));
		});
		if (wantUsage)
			wantRate = true;
		extras.forEach((t, i) => {
			this.strokeLabel(layer, mid.x,
				mid.y - 10 - (wantRate ? 14 : 0) - (extras.length - 1 - i) * 13,
				t, 'currentColor');
		});
		if (wantRate) {
			const caps = wantUsage ? {
				tx: bag.bw_up,
				rx: bag.bw_down
			} : null;
			const size = 11;
			const withUsage = caps && (Number(caps.tx) > 0 || Number(caps.rx) > 0);
			const anchor = this.linkRateAnchor(key, mid);
			const rw = this.rateMetrics(size, withUsage).width;
			const g = svgEl('g', { 'class': 'topo-link-rate', 'data-link-key': key });
			const hit = svgEl('rect', {
				x: anchor.x - rw / 2 - 4,
				y: anchor.y - 13,
				width: rw + 8,
				height: 26,
				fill: '#fff',
				'fill-opacity': this.selected === key ? '0.22' : '0',
				stroke: this.selected === key ? '#2563eb' : 'none',
				'stroke-width': 1,
				rx: 3,
				style: this.layoutLock ? 'cursor:pointer' : 'cursor:grab',
				'pointer-events': 'all'
			});
			g.appendChild(hit);
			this.drawRateStack(g, anchor.x, anchor.y - 13, anchor.y + 13, bag.tx, bag.rx, size, key, caps);
			layer.appendChild(g);
			this.bindLinkRateDrag(hit, key, kind, mid, anchor);
		}
	},

	drawWanSum(layer, x, y, tx, rx) {
		const key = 'wan-sum';
		const kind = 'wan_sum';
		const p = this.xy(key, x, y);
		const sel = this.selected === key;
		const ids = this.shown(key, kind);
		const showTitle = ids.indexOf('title') >= 0 || !ids.length;
		const showRate = ids.indexOf('rate') >= 0;
		const muted = !ids.length;
		const g = svgEl('g', {
			'class': 'topo-hit',
			'data-key': key,
			style: this.layoutLock ? 'cursor:pointer' : 'cursor:grab'
		});
		const rw = showRate ? this.rateMetrics(12).width : 0;
		const boxW = Math.max(124, rw + 24);
		const boxH = showRate && showTitle ? 58 : 48;
		g.appendChild(svgEl('rect', {
			x: p.x - boxW / 2, y: p.y - 32, width: boxW, height: boxH, rx: 6,
			fill: '#ffffff', 'fill-opacity': sel ? '0.35' : '0',
			stroke: sel ? '#2563eb' : (muted ? '#94a3b8' : 'none'),
			'stroke-width': sel ? 1.4 : (muted ? 1 : 0),
			'stroke-dasharray': muted ? '3 3' : null,
			'pointer-events': 'all'
		}));
		let yOff = showRate ? -16 : -2;
		if (showTitle)
			g.appendChild(svgEl('text', {
				x: p.x, y: p.y + yOff, 'text-anchor': 'middle',
				'font-size': 11, 'font-weight': 750,
				fill: muted ? '#94a3b8' : 'currentColor',
				stroke: 'var(--background-color-high, #ffffff)',
				'stroke-width': 4, 'stroke-linejoin': 'round',
				'paint-order': 'stroke fill'
			}, ['总带宽']));
		if (showRate)
			this.drawRateStack(g, p.x, p.y + 2, p.y + 18, tx, rx, 12, 'wan-sum');
		this.bindFloat(g, key, kind);
		layer.appendChild(g);
	},

	bindFloat(g, key, kind) {
		const self = this;
		g.addEventListener('click', function(ev) {
			if (self._didDrag) {
				self._didDrag = false;
				ev.stopPropagation();
				return;
			}
			ev.stopPropagation();
			self.selected = key;
			self.selectedKind = kind;
			self.fillDetail();
			if (self.model)
				self.rebuild(document.getElementById('topo-svg'), self.model);
		});
		g.addEventListener('pointerdown', function(ev) {
			if (ev.button || self.layoutLock)
				return;
			ev.preventDefault();
			ev.stopPropagation();
			const svg = document.getElementById('topo-svg');
			if (!svg)
				return;
			self._didDrag = false;
			self._dragging = true;
			const start = self.clientToSvg(svg, ev.clientX, ev.clientY);
			const cur = self.xy(key, start.x, start.y);
			const dx = start.x - cur.x, dy = start.y - cur.y;
			function move(e) {
				const p = self.clientToSvg(svg, e.clientX, e.clientY);
				self.patchPos(key, {
					x: snapVal(p.x - dx, self.snapGrid),
					y: snapVal(p.y - dy, self.snapGrid)
				}, key === 'wan-sum' ? { user: true } : null);
				self._didDrag = true;
				if (!self._dragRaf) {
					self._dragRaf = requestAnimationFrame(function() {
						self._dragRaf = 0;
						if (self.model)
							self.rebuild(svg, self.model);
					});
				}
			}
			function up() {
				window.removeEventListener('pointermove', move);
				window.removeEventListener('pointerup', up);
				self._dragging = false;
				if (self._didDrag)
					self.savePos();
			}
			window.addEventListener('pointermove', move);
			window.addEventListener('pointerup', up);
		});
	},

	device(layer, x, y, kind, title, lines, tone, key, fieldKind) {
		const sel = this.selected === key;
		const fk = fieldKind || kind;
		const cat = FIELD_CATALOG[fk] || [];
		const hasTitleField = cat.some(f => f.id === 'title');
		const metaLines = (lines || []).slice(0, kind === 'switch' ? 4 : 3);
		const n = Math.max(1, metaLines.length + 1);
		const box = this.nodeBox(key || title, kind, n);

		if (key === 'internet' || kind === 'cloud') {
			const drawTitle = hasTitleField ? this.hasField(key, fk, 'title') : true;
			const s = Math.max(0.55, Math.min(box.w / 88, box.h / 68));
			const iconH = 26 * s;
			const titleSize = 13 * s;
			const lineGap = 12 * s;
			const gapIconTitle = drawTitle ? 8 * s : 0;
			const gapTitleLines = metaLines.length ? 6 * s : 0;
			const contentH = iconH + gapIconTitle + (drawTitle ? titleSize : 0)
				+ gapTitleLines + metaLines.length * lineGap;
			const top = y - contentH / 2;
			const iconY = top + iconH / 2;
			const titleY = top + iconH + gapIconTitle + titleSize * 0.82;
			const linesBase = drawTitle ? titleY : (top + iconH);
			const w = Math.max(72, box.w * 0.72);
			const g = svgEl('g', {
				'class': 'topo-hit topo-internet-bare',
				'data-key': key || title,
				style: this.layoutLock ? 'cursor:pointer' : 'cursor:grab'
			});
			g.appendChild(svgEl('rect', {
				x: x - w / 2, y: top - 4, width: w, height: contentH + 8, rx: 4,
				fill: '#ffffff', 'fill-opacity': '0', stroke: 'none',
				'pointer-events': 'all'
			}));
			g.appendChild(this.icon('cloud', x, iconY, healthColor(tone || 'ok'), s, null, sel));
			if (drawTitle)
				g.appendChild(svgEl('text', {
					x: x, y: titleY, 'text-anchor': 'middle',
					'font-size': titleSize, 'font-weight': 750, fill: 'currentColor'
				}, [title]));
			metaLines.forEach((ln, i) => {
				g.appendChild(svgEl('text', {
					x: x, y: linesBase + gapTitleLines + (i + 1) * lineGap - 2,
					'text-anchor': 'middle',
					'font-size': 10 * s, fill: 'currentColor', opacity: '0.72'
				}, [ln]));
			});
			this.bindNode(g, key || title, fieldKind || kind);
			layer.appendChild(g);
			this._nodes = this._nodes || {};
			this._nodes[key || title] = { x: x, y: y, w: w, h: contentH + 8 };
			if (sel && !this.layoutLock)
				this.nodeResizeHandles(key, x, y, w, contentH + 8);
			return this._nodes[key || title];
		}

		const cardKind = topoUseIconSkin(kind, key) ? kind : null;
		const drawTitle = hasTitleField ? this.hasField(key, fk, 'title') : !!cardKind;
		const rackCard = kind === 'switch' || kind === 'router';
		const cardW = box.w;
		const headerH = 34;
		const footerH = metaLines.length ? metaLines.length * 11 + 10 : 6;
		const artH = rackCard ? Math.max(56, box.h - headerH - footerH) : 48;
		const cardH = rackCard ? box.h : headerH + artH + footerH;
		const left = x - cardW / 2;
		const top = y - cardH / 2;
		const g = svgEl('g', {
			'class': 'topo-hit topo-shumoku-card',
			'data-key': key || title,
			style: this.layoutLock ? 'cursor:pointer' : 'cursor:grab'
		});
		g.appendChild(svgEl('rect', {
			x: left, y: top, width: cardW, height: cardH, rx: 10,
			fill: '#ffffff', stroke: 'none', filter: 'url(#topo-card-shadow)',
			'pointer-events': 'all'
		}));
		g.appendChild(svgEl('rect', {
			x: left, y: top, width: cardW, height: cardH, rx: 10,
			fill: '#ffffff',
			stroke: sel ? '#2563eb' : '#e2e8f0',
			'stroke-width': sel ? 2.4 : 1.2
		}));
		g.appendChild(svgEl('rect', {
			x: left + 1, y: top + 1, width: cardW - 2, height: headerH,
			rx: 9, fill: '#f8fafc', stroke: 'none'
		}));
		g.appendChild(svgEl('line', {
			x1: left + 8, y1: top + headerH, x2: left + cardW - 8, y2: top + headerH,
			stroke: '#e2e8f0', 'stroke-width': 1
		}));
		if (drawTitle)
			g.appendChild(svgEl('text', {
				x: x, y: top + 22,
				'text-anchor': 'middle',
				'font-size': 13, 'font-weight': 800, fill: '#0f172a'
			}, [title]));
		const rackKind = (kind === 'router') ? 'switch' : kind;
		g.appendChild(this.deviceArt(rackKind, x, top + headerH + artH / 2, cardW - 14, artH - 8, tone || 'ok'));
		let fy = top + headerH + artH + 12;
		metaLines.forEach(ln => {
			g.appendChild(svgEl('text', {
				x: x, y: fy,
				'text-anchor': 'middle',
				'font-size': 9.5, fill: '#64748b'
			}, [ln]));
			fy += 11;
		});
		this.bindNode(g, key || title, fieldKind || kind);
		layer.appendChild(g);
		this._nodes = this._nodes || {};
		this._nodes[key || title] = { x: x, y: y, w: cardW, h: cardH };
		if (sel && !this.layoutLock && (key === 'gateway' || key === 'switch'))
			this.nodeResizeHandles(key, x, y, cardW, cardH);
		return this._nodes[key || title];
	},

	clientLayout(list) {
		const shown = this.shown('cli-list', 'host');
		const size = 11;
		const ch = size * 0.52;
		const gap = 2;
		const cols = [];
		let x = 0;
		['name', 'ip', 'mac', 'rate', 'online'].forEach(id => {
			if (shown.indexOf(id) < 0)
				return;
			if (id === 'name') {
				let n = 3;
				(list || []).forEach(c => {
					n = Math.max(n, (clientHostname(c) || '').length);
				});
				n = Math.min(10, n);
				cols.push({ id: 'name', x, w: n * ch });
				x += n * ch + gap;
			} else if (id === 'ip') {
				let n = 7;
				(list || []).forEach(c => {
					n = Math.max(n, (c.ip || '').length);
				});
				n = Math.min(15, n);
				cols.push({ id: 'ip', x, w: n * ch });
				x += n * ch + gap;
			} else if (id === 'mac') {
				let n = 11;
				(list || []).forEach(c => {
					n = Math.max(n, (c.mac || '').length);
				});
				n = Math.min(17, n);
				cols.push({ id: 'mac', x, w: n * ch });
				x += n * ch + gap;
			} else if (id === 'online') {
				cols.push({ id: 'online', x, w: 4 * ch });
				x += 4 * ch + gap;
			} else if (id === 'rate') {
				x += 8;
				const rw = this.rateMetrics(size).width;
				cols.push({ id: 'rx', x, w: rw });
				x += rw + 4;
				cols.push({ id: 'tx', x, w: rw });
				x += rw + gap;
			}
		});
		return { cols, width: Math.max(64, x), size };
	},

	drawClient(layer, x, y, c, key, stackIndex, stackCount, layout, summary) {
		layout = layout || this.clientLayout([c]);
		const iconW = 26;
		const w = layout.width + iconW;
		const h = Math.max(20, CLI_PITCH - 6);
		const g = svgEl('g', {
			'class': 'topo-hit',
			'data-key': key,
			style: this.layoutLock ? 'cursor:pointer' : 'cursor:grab'
		});
		g.appendChild(svgEl('rect', {
			x: x, y: y - h / 2, width: w, height: h, rx: 2,
			fill: '#ffffff', 'fill-opacity': '0', stroke: 'none',
			'pointer-events': 'all'
		}));
		g.appendChild(this.icon('client', x + iconW * 0.42, y, COL_TX, 0.52, c));
		x = x + iconW;
		const base = {
			y: y + 4,
			'font-size': layout.size,
			'font-weight': 650,
			'font-family': RATE_FONT,
			'font-variant-numeric': 'tabular-nums lining-nums',
			fill: c.online === false ? '#94a3b8' : 'currentColor'
		};
		if (summary) {
			g.appendChild(svgEl('text', Object.assign({}, base, {
				x: x + 2, 'text-anchor': 'start'
			}), [c.ip || '']));
		} else {
			layout.cols.forEach(col => {
				if (col.id === 'rx') {
					this.drawAlignedRate(g, x + col.x, y + 4, '↓', c.rx, COL_RX, layout.size, key + ':rx');
					return;
				}
				if (col.id === 'tx') {
					this.drawAlignedRate(g, x + col.x, y + 4, '↑', c.tx, COL_TX, layout.size, key + ':tx');
					return;
				}
				let txt = '';
				if (col.id === 'name')
					txt = trunc(clientHostname(c) || '—', Math.max(1, Math.floor(col.w / (layout.size * 0.6))));
				else if (col.id === 'ip')
					txt = c.ip || '—';
				else if (col.id === 'mac')
					txt = c.mac || '—';
				else if (col.id === 'online')
					txt = c.online === false ? '离线' : '在线';
				g.appendChild(svgEl('text', Object.assign({}, base, {
					x: x + col.x, 'text-anchor': 'start'
				}), [txt]));
			});
		}
		this.bindClientStack(g, key, stackIndex, stackCount);
		layer.appendChild(g);
		this._nodes = this._nodes || {};
		this._nodes[key] = { x: x, y: y, w: w, h: h };
		return this._nodes[key];
	},

	bindClientStack(g, key, index, count) {
		const self = this;
		const pitch = CLI_PITCH;
		g.addEventListener('click', function(ev) {
			if (self._didDrag) {
				self._didDrag = false;
				ev.stopPropagation();
				return;
			}
			ev.stopPropagation();
			self.selected = key;
			self.selectedKind = 'host';
			self.fillDetail();
			if (self.model)
				self.rebuild(document.getElementById('topo-svg'), self.model);
		});
		g.addEventListener('pointerdown', function(ev) {
			if (ev.button || self.layoutLock)
				return;
			ev.preventDefault();
			ev.stopPropagation();
			const svg = document.getElementById('topo-svg');
			if (!svg)
				return;
			self._didDrag = false;
			self._dragging = true;
			const start = self.clientToSvg(svg, ev.clientX, ev.clientY);
			const n = Math.max(1, count || 1);
			const origin = self.xy('cli-stack', start.x, start.y);
			const firstY = origin.y - ((n - 1) * pitch) / 2;
			const thisY = firstY + (index || 0) * pitch;
			const dx = start.x - origin.x;
			const dy = start.y - thisY;
			function move(e) {
				const p = self.clientToSvg(svg, e.clientX, e.clientY);
				const newFirstY = p.y - dy - (index || 0) * pitch;
				const newCenterY = newFirstY + ((n - 1) * pitch) / 2;
				self.patchPos('cli-stack', {
					x: snapVal(p.x - dx, self.snapGrid),
					y: snapVal(newCenterY, self.snapGrid)
				});
				self._didDrag = true;
				if (!self._dragRaf) {
					self._dragRaf = requestAnimationFrame(function() {
						self._dragRaf = 0;
						if (self.model)
							self.rebuild(svg, self.model);
					});
				}
			}
			function up() {
				window.removeEventListener('pointermove', move);
				window.removeEventListener('pointerup', up);
				self._dragging = false;
				if (self._didDrag)
					self.savePos();
			}
			window.addEventListener('pointermove', move);
			window.addEventListener('pointerup', up);
		});
	},

	nodeResizeHandles(key, x, y, w, h) {
		const dest = this._handleLayer;
		if (!dest)
			return;
		const self = this;
		const specs = [
			{ dx: -1, dy: -1, cur: 'nwse-resize' },
			{ dx: 0, dy: -1, cur: 'ns-resize' },
			{ dx: 1, dy: -1, cur: 'nesw-resize' },
			{ dx: 1, dy: 0, cur: 'ew-resize' },
			{ dx: 1, dy: 1, cur: 'nwse-resize' },
			{ dx: 0, dy: 1, cur: 'ns-resize' },
			{ dx: -1, dy: 1, cur: 'nesw-resize' },
			{ dx: -1, dy: 0, cur: 'ew-resize' }
		];
		specs.forEach(sp => {
			const hx = x + sp.dx * w / 2;
			const hy = y + sp.dy * h / 2;
			const el = svgEl('rect', {
				x: hx - 5, y: hy - 5, width: 10, height: 10, rx: 1,
				fill: '#fff', stroke: '#0f172a', 'stroke-width': 1.5,
				style: 'cursor:' + sp.cur
			});
			el.addEventListener('pointerdown', function(ev) {
				if (ev.button || self.layoutLock)
					return;
				ev.stopPropagation();
				ev.preventDefault();
				const svg = document.getElementById('topo-svg');
				self._dragging = true;
				self._didDrag = false;
				const left0 = x - w / 2, right0 = x + w / 2;
				const top0 = y - h / 2, bot0 = y + h / 2;
				try { el.setPointerCapture(ev.pointerId); } catch (e) {}
				function move(e) {
					const p = self.clientToSvg(svg, e.clientX, e.clientY);
					let L = left0, R = right0, T = top0, B = bot0;
					if (sp.dx < 0)
						L = snapVal(p.x, self.snapGrid);
					if (sp.dx > 0)
						R = snapVal(p.x, self.snapGrid);
					if (sp.dy < 0)
						T = snapVal(p.y, self.snapGrid);
					if (sp.dy > 0)
						B = snapVal(p.y, self.snapGrid);
					const minBoxW = (key === 'gateway' || key === 'switch') ? 64 : 70;
					if (R - L < minBoxW) {
						if (sp.dx < 0)
							L = R - minBoxW;
						else
							R = L + minBoxW;
					}
					if (B - T < 48) {
						if (sp.dy < 0)
							T = B - 48;
						else
							B = T + 48;
					}
					self.patchPos(key, {
						x: (L + R) / 2,
						y: (T + B) / 2,
						w: R - L,
						h: B - T
					});
					self._didDrag = true;
					if (!self._dragRaf) {
						self._dragRaf = requestAnimationFrame(function() {
							self._dragRaf = 0;
							if (self.model)
								self.rebuild(svg, self.model);
						});
					}
				}
				function up() {
					window.removeEventListener('pointermove', move);
					window.removeEventListener('pointerup', up);
					self._dragging = false;
					if (self._didDrag)
						self.savePos();
				}
				window.addEventListener('pointermove', move);
				window.addEventListener('pointerup', up);
			});
			dest.appendChild(el);
		});
	},

	bindNode(g, key, kind) {
		const self = this;
		g.addEventListener('click', function(ev) {
			if (self._didDrag) {
				self._didDrag = false;
				ev.stopPropagation();
				return;
			}
			ev.stopPropagation();
			self.selected = key;
			self.selectedKind = kind;
			self.fillDetail();
			if (self.model)
				self.rebuild(document.getElementById('topo-svg'), self.model);
		});
		g.addEventListener('pointerdown', function(ev) {
			if (ev.button || self.layoutLock)
				return;
			ev.preventDefault();
			ev.stopPropagation();
			const svg = document.getElementById('topo-svg');
			if (!svg)
				return;
			self._didDrag = false;
			self._dragging = true;
			const start = self.clientToSvg(svg, ev.clientX, ev.clientY);
			const cur = self.xy(key, start.x, start.y);
			const dx = start.x - cur.x, dy = start.y - cur.y;
			function move(e) {
				const p = self.clientToSvg(svg, e.clientX, e.clientY);
				self.patchPos(key, {
					x: snapVal(p.x - dx, self.snapGrid),
					y: snapVal(p.y - dy, self.snapGrid)
				});
				self._didDrag = true;
				if (!self._dragRaf) {
					self._dragRaf = requestAnimationFrame(function() {
						self._dragRaf = 0;
						if (self.model)
							self.rebuild(svg, self.model);
					});
				}
			}
			function up() {
				window.removeEventListener('pointermove', move);
				window.removeEventListener('pointerup', up);
				self._dragging = false;
				if (self._didDrag) {
					self.savePos();
					if (self.model)
						self.rebuild(svg, self.model);
				}
			}
			window.addEventListener('pointermove', move);
			window.addEventListener('pointerup', up);
		});
	},

	tick() {
		if (!this.animating)
			return;
		const t = (typeof performance !== 'undefined' ? performance.now() : Date.now()) / 1000;
		const layer = document.getElementById('topo-packets');
		if (!layer) {
			requestAnimationFrame(L.bind(this.tick, this));
			return;
		}
		const active = [];
		(this.flows || []).forEach(f => {
			if (!f.pts || f.pts.length < 2)
				return;
			const st = flowSpeedStyle(f.bps, f.cap, f.dir || flowDirFromId(f.id));
			let px = st.px;
			let color = st.color;
			if (!px && flowShouldIdle(f)) {
				px = LINK_IDLE_FLOW_PX;
				color = COL_LINK_IDLE;
			}
			if (!px)
				return;
			active.push({ pts: f.pts, attr: polyPoints(f.pts), color: color, px: px });
		});
		const sig = active.map(a => a.attr + '\\t' + a.color + '\\t' + a.px.toFixed(1)).join('\\n');
		if (this._flowSig !== sig || !this._flowEls || this._flowEls.length !== active.length) {
			this._flowSig = sig;
			while (layer.firstChild)
				layer.removeChild(layer.firstChild);
			this._flowEls = active.map(a => {
				const dash = flowDash(a.px);
				const sw = flowStrokeWidth(a.px);
				const main = svgEl('polyline', {
					points: a.attr,
					fill: 'none',
					stroke: a.color,
					'stroke-width': String(sw.main),
					'stroke-dasharray': dash,
					'stroke-linecap': 'round',
					'stroke-linejoin': 'round',
					opacity: '0.96',
					'pointer-events': 'none',
					class: 'topo-ant-line'
				});
				layer.appendChild(main);
				return { main: main, px: a.px, pts: a.pts, dash: dash };
			});
		} else {
			this._flowEls.forEach((el, i) => {
				el.px = active[i].px;
				el.pts = active[i].pts;
				const dash = flowDash(el.px);
				const sw = flowStrokeWidth(el.px);
				el.dash = dash;
				el.main.setAttribute('stroke', active[i].color);
				el.main.setAttribute('stroke-dasharray', dash);
				el.main.setAttribute('stroke-width', String(sw.main));
			});
		}
		this._flowEls.forEach(el => {
			const off = -(t * el.px);
			el.main.setAttribute('stroke-dashoffset', String(off));
		});
		requestAnimationFrame(L.bind(this.tick, this));
	},

	snapshotModel(snap) {
		if (!snap)
			return this.model;
		const wans = snap.wans || [];
		const lan = snap.lan || {};
		const sys = snap.sys || {};
		const sum = snap.clients_sum || {};
		const live = this._liveRates;
		const first = !live;
		const prevM = this.model;
		const clients = (snap.clients || []).slice().map(c => {
			const id = c.mac || c.ip;
			let lr = live && live.clients && (
				(c.mac && live.clients[c.mac]) ||
				(c.ip && live.clients[c.ip]) ||
				live.clients[id]
			);
			let down = 0, up = 0;
			if (lr) {
				down = lr.rx; up = lr.tx;
			} else if (+c.down_bps > 0 || +c.up_bps > 0) {
				down = +c.down_bps || 0;
				up = +c.up_bps || 0;
			} else if (first) {
				down = lastHist(snap, id, 'rx') || 0;
				up = lastHist(snap, id, 'tx') || 0;
			}
			return Object.assign({}, c, { rx: down, tx: up });
		}).sort((a, b) => (b.rx + b.tx) - (a.rx + a.tx) || (b.online ? 1 : 0) - (a.online ? 1 : 0));
		const wanRows = wans.map(w => {
			const lr = live && live.wans && live.wans[w.name];
			const pw = prevM && (prevM.wans || []).find(x => x.w && x.w.name === w.name);
			let down = 0, up = 0;
			if (lr) {
				down = lr.down; up = lr.up;
			} else if (+w.down_bps > 0 || +w.up_bps > 0) {
				down = +w.down_bps || 0;
				up = +w.up_bps || 0;
			} else if (first) {
				down = lastHist(snap, w.name, 'rx');
				up = lastHist(snap, w.name, 'tx');
			} else {
				down = +w.down_bps || 0;
				up = +w.up_bps || 0;
			}
			return {
				w,
				rx: down,
				tx: up,
				health: w.health || (w.up ? 'ok' : 'bad'),
				text: w.health_text || (w.up ? '正常' : '掉线')
			};
		});
		let lanDownRaw = 0, lanUpRaw = 0;
		if (live) {
			lanDownRaw = live.lanDown; lanUpRaw = live.lanUp;
		} else if (prevM) {
			lanDownRaw = prevM.lanDown; lanUpRaw = prevM.lanUp;
		} else if (+lan.down_bps > 0 || +lan.up_bps > 0) {
			lanDownRaw = +lan.down_bps || 0;
			lanUpRaw = +lan.up_bps || 0;
		} else {
			lanDownRaw = lastHist(snap, '_lan', 'rx');
			lanUpRaw = lastHist(snap, '_lan', 'tx');
		}
		this.prev = snap;
		if (!this._snapAt)
			this._snapAt = Date.now();
		this.model = { wans: wanRows, lan, lanDown: lanDownRaw, lanUp: lanUpRaw, sys, sum, clients, snap };
		return this.model;
	},

	syncHudClock() {
		this.placeStatusClock();
		const el = document.getElementById('lede-clock');
		if (!el)
			return;
		if (this._clkMs == null) {
			el.textContent = '--';
			return;
		}
		const elapsed = Date.now() - (this._clkAt || Date.now());
		el.textContent = fmtStatusClock(this._clkMs + elapsed);
	},

	noteClock(sys) {
		const ms = parseRouterClockMs(sys);
		if (ms == null)
			return;
		this._clkMs = ms;
		this._clkAt = Date.now();
		this.syncHudClock();
	},

	startLiveClock() {
		if (this._clkIv)
			return;
		const self = this;
		this._clkIv = window.setInterval(function() {
			self.syncHudClock();
		}, 250);
	},

	applyPulse(p) {
		/* Bandix 速率由 wanmonitor 代理；WAN 与 LAN 下载方向相反，换算在后端。 */
		if (!p || !this.prev)
			return;
		this.noteClock(p.sys);
		const now = Date.now();
		const wans = this.prev.wans || [];
		const lan = this.prev.lan || {};
		const zeros = this._rateZeros || {};
		this._rateZeros = zeros;
		const prevLive = this._liveRates || { wans: {}, lanDown: 0, lanUp: 0, clients: {} };
		const live = {
			wans: Object.assign({}, prevLive.wans),
			lanDown: prevLive.lanDown || 0,
			lanUp: prevLive.lanUp || 0,
			clients: Object.assign({}, prevLive.clients)
		};
		const wr = p.wan_rates || {};
		wans.forEach(function(w) {
			const r = wr[w.name];
			const old = live.wans[w.name] || {};
			const down = r ? (+r.down_bps || 0) : (+w.down_bps || 0);
			const up = r ? (+r.up_bps || 0) : (+w.up_bps || 0);
			live.wans[w.name] = {
				down: holdRate(old.down, down, zeros, 'w:' + w.name + ':d'),
				up: holdRate(old.up, up, zeros, 'w:' + w.name + ':u')
			};
		});
		if (p.lan) {
			live.lanDown = holdRate(live.lanDown, +p.lan.down_bps || 0, zeros, 'lan:d');
			live.lanUp = holdRate(live.lanUp, +p.lan.up_bps || 0, zeros, 'lan:u');
		}
		const pulseCli = {};
		(p.clients || []).forEach(function(c) {
			if (c.mac)
				pulseCli[c.mac] = c;
			if (c.ip)
				pulseCli[c.ip] = c;
		});
		Object.keys(pulseCli).forEach(function(id) {
			const c = pulseCli[id];
			const old = live.clients[id] || {};
			live.clients[id] = {
				rx: holdRate(old.rx, +c.down_bps || 0, zeros, 'c:' + id + ':d'),
				tx: holdRate(old.tx, +c.up_bps || 0, zeros, 'c:' + id + ':u')
			};
		});
		this.overlayBandixClientRates(live, zeros);
		this._liveRates = live;
		const snap = Object.assign({}, this.prev, {
			sys: Object.assign({}, this.prev.sys || {}, p.sys || {}),
			lan: Object.assign({}, this.prev.lan || {}, p.lan || {})
		});
		if (p.clients_sum)
			snap.clients_sum = Object.assign({}, snap.clients_sum || {}, p.clients_sum);
		this.paint(this.mergeBandixSnap(snap), this.info);
	},

	applyFullSnap(snap) {
		if (!snap)
			return;
		this.noteClock(snap.sys);
		if (!this.prev) {
			this.paint(this.mergeBandixSnap(snap), this.info);
			return;
		}
		const prev = this.prev;
		if (Array.isArray(snap.wans) && Array.isArray(prev.wans)) {
			snap.wans = snap.wans.map(function(w) {
				const pw = prev.wans.find(function(x) { return x.name === w.name; });
				return pw ? Object.assign({}, w, { rx_bytes: pw.rx_bytes, tx_bytes: pw.tx_bytes }) : w;
			});
		}
		if (snap.lan && prev.lan)
			snap.lan = Object.assign({}, snap.lan, { rx_bytes: prev.lan.rx_bytes, tx_bytes: prev.lan.tx_bytes });
		if (Array.isArray(snap.clients) && Array.isArray(prev.clients)) {
			snap.clients = snap.clients.map(function(c) {
				const pc = prev.clients.find(function(x) { return (c.mac && x.mac === c.mac) || (c.ip && x.ip === c.ip); });
				if (!pc)
					return Object.assign({}, c, { down_bps: null, up_bps: null });
				return Object.assign({}, c, {
					rx_bytes: pc.rx_bytes, tx_bytes: pc.tx_bytes,
					down_bps: c.down_bps, up_bps: c.up_bps
				});
			});
		}
		this.paint(this.mergeBandixSnap(snap), this.info);
	},

	startLivePoll() {
		if (this.polling)
			return;
		this.polling = true;
		const self = this;
		let fullBusy = false;
		let pulseBusy = false;
		let fullAge = 0;
		let bandixAge = 0;
		const tick = function() {
			if (!self.polling)
				return;
			if (!pulseBusy) {
				pulseBusy = true;
				callPulse().then(function(p) {
					self.applyPulse(p);
				}).catch(function() {}).finally(function() {
					pulseBusy = false;
				});
			}
			fullAge++;
			if (fullAge >= 15 && !fullBusy) {
				fullAge = 0;
				fullBusy = true;
				callSnapshot().then(function(snap) {
					self.applyFullSnap(snap);
				}).catch(function() {}).finally(function() {
					fullBusy = false;
				});
			}
			bandixAge++;
			if (bandixAge >= 5) {
				bandixAge = 0;
				self.refreshBandixClients(false);
			}
		};
		tick();
		this._pollIv = window.setInterval(tick, 1000);
	},

	placeStatusClock() {
		let clock = document.getElementById('lede-clock');
		if (!clock) {
			clock = E('div', { 'id': 'lede-clock', 'class': 'lede-clock-status' }, '--');
		} else {
			clock.className = 'lede-clock-status';
		}
		const bar = document.querySelector('#maincontent h2[name="content"]')
			|| document.querySelector('#maincontent h2')
			|| document.querySelector('.topo-title');
		if (!bar)
			return;
		if (clock.parentNode !== bar)
			bar.appendChild(clock);
	},

	fillHud() {
		const el = document.getElementById('topo-hud');
		if (!el || !this.model)
			return;
		const m = this.model;
		let wanRx = 0, wanTx = 0;
		m.wans.forEach(r => { wanRx += r.rx; wanTx += r.tx; });
		const sys = m.sys || {};
		el.innerHTML = '';
		if (this._clkMs == null)
			this.noteClock(sys);
		[
			['15分钟负载', sys.load_15 || '—'],
			['CPU', (sys.cpu_pct != null ? sys.cpu_pct : '—') + '%'],
			['温度', sys.temp_c ? sys.temp_c + '℃' : '—'],
			['内存', (sys.mem_pct != null ? sys.mem_pct : memPct(this.info)) + '%'],
			['连接数', String(sys.conn != null ? sys.conn : '—')],
			['WAN↓', fmtBitrate(wanRx)],
			['WAN↑', fmtBitrate(wanTx)],
			['LAN↓', fmtBitrate(m.lanDown)],
			['LAN↑', fmtBitrate(m.lanUp)],
			['在线终端', String((m.sum && m.sum.online) || 0)],
			['运行时长', fmtBootUptime(sys.uptime != null ? sys.uptime : ((m.snap && m.snap.ts) ? m.snap.ts / 1000 : 0))]
		].forEach(pair => {
			el.appendChild(E('div', { 'class': 'topo-kpi' }, [
				E('div', { 'class': 'k' }, pair[0]),
				E('div', { 'class': 'v' }, pair[1])
			]));
		});
	},

	entityTitle(key, kind) {
		if (kind && kind.indexOf('link_') === 0)
			return '连线';
		if (key === 'internet')
			return '运营商';
		if (key === 'wan-sum')
			return 'WAN 总带宽';
		if (key === 'gateway')
			return (this.board && this.board.hostname) || '网关';
		if (key === 'switch')
			return '核心交换机';
		if (key && key.indexOf('nic:') === 0)
			return key.slice(4);
		if (key && key.indexOf('wan:') === 0)
			return key.slice(4);
		if (key && key.indexOf('cli:') === 0) {
			const id = key.slice(4);
			const c = (this.model.clients || []).find(x => x.mac === id || x.ip === id);
			return (c && (clientHostname(c) || c.ip)) || '终端';
		}
		return key || '未选择';
	},

	fillDetail() {
		const box = document.getElementById('topo-detail');
		if (!box || !this.model)
			return;
		const m = this.model;
		const key = this.selected;
		const kind = this.selectedKind;
		box.innerHTML = '';
		if (!key) {
			box.appendChild(E('h4', {}, '点选图中的设备或连线'));
			box.appendChild(E('p', {}, '选中后可勾选要画在图上的数据。点交换机、任一客户端或客户端连线，可改图上显示的客户端数量。'));
			return;
		}

		const facts = [];
		if (key === 'internet')
			facts.push('运营商侧。线段两端可单独拖；线段与设备位置互不影响。');
		else if (key === 'wan-sum') {
			let wanRx = 0, wanTx = 0;
			(m.wans || []).forEach(r => { wanRx += r.rx; wanTx += r.tx; });
			facts.push('全部 WAN 口总带宽：↑ ' + fmtBitrate(wanTx) + '　↓ ' + fmtBitrate(wanRx));
			facts.push('可拖动调整显示位置，不跟运营商图标绑在一起。');
			facts.push('取消全部勾选后仍会留下「总带宽」占位，点它可再勾选要显示的内容。');
		}
		else if (key === 'gateway') {
			const rel = (this.board && this.board.release) || {};
			facts.push((rel.description || rel.version || '') + ' · LAN ' + (m.lan.ipv4 || '') + ' · ' + (m.lan.device || ''));
			facts.push('CPU ' + (m.sys.cpu_pct || 0) + '% · 温度 ' + (m.sys.temp_c || '—') + '℃ · 连接数 ' + (m.sys.conn || 0));
			(m.wans || []).forEach(r => {
				facts.push(r.w.name + ' · ' + protoLabel(r.w.proto) + ' · ' + (r.w.ipv4 || '无地址') +
					' · ' + r.text + ' · ↓ ' + fmtBitrate(r.rx) + ' ↑ ' + fmtBitrate(r.tx));
			});
		} else if (key === 'switch') {
			facts.push('网关 LAN 口合计，不是交换机每个物理口。');
			facts.push('↓ ' + fmtBitrate(m.lanDown) + '　↑ ' + fmtBitrate(m.lanUp));
		} else if (key.indexOf('nic:') === 0) {
			const name = key.slice(4);
			if (name === 'lan') {
				facts.push('网关 LAN 口' + (m.lan && m.lan.speed ? ' · ' + speedTag(m.lan.speed) : ''));
				facts.push('↓ ' + fmtBitrate(m.lanDown) + '　↑ ' + fmtBitrate(m.lanUp));
			} else {
				const row = m.wans.find(r => r.w.name === name);
				if (row) {
					facts.push('网关网卡 ' + row.w.name + (row.w.speed ? ' · ' + speedTag(row.w.speed) : ''));
					facts.push(row.text + ' · ' + protoLabel(row.w.proto) + ' · ' + (row.w.ipv4 || '无地址'));
					facts.push('↓ ' + fmtBitrate(row.rx) + '　↑ ' + fmtBitrate(row.tx) + ' · 延迟 ' + fmtLatency(row.w.latency));
				}
			}
		} else if (key.indexOf('wan:') === 0) {
			const row = m.wans.find(r => r.w.name === key.slice(4));
			if (row) {
				facts.push(row.text + ' · ' + protoLabel(row.w.proto) + ' · ' + (row.w.ipv4 || '无地址'));
				facts.push('↓ ' + fmtBitrate(row.rx) + '　↑ ' + fmtBitrate(row.tx) + ' · 延迟 ' + fmtLatency(row.w.latency));
			}
		} else if (key.indexOf('cli:') === 0) {
			const id = key.slice(4);
			const c = m.clients.find(x => x.mac === id || x.ip === id);
			if (c)
				facts.push((c.online ? '在线' : '离线') + ' · ' + (c.ip || '') + ' · ' + (c.mac || ''));
			if (c && clientHostname(c))
				facts.push('名称 ' + clientHostname(c));
			if (c)
				facts.push('↓ ' + fmtBitrate(c.rx) + '　↑ ' + fmtBitrate(c.tx));
			facts.push('下方勾选对全部客户端及全部客户端连线同时生效，不是只改这一台。');
		} else if (key.indexOf('link:inet:') === 0) {
			const row = m.wans.find(r => r.w.name === key.slice(10));
			if (row) {
				facts.push('网关 WAN 口 ' + row.w.name + (row.w.speed ? ' · 网卡 ' + speedTag(row.w.speed) : '') + '（不是独立设备）');
				facts.push(row.text + ' · ' + protoLabel(row.w.proto) + ' · ' + (row.w.ipv4 || '无地址'));
				facts.push('↓ ' + fmtBitrate(row.rx) + '　↑ ' + fmtBitrate(row.tx) + ' · 延迟 ' + fmtLatency(row.w.latency));
				const bd = Number(row.w.bw_down) || 0, bu = Number(row.w.bw_up) || 0;
				if (bd || bu)
					facts.push('已设下行 ' + bd + ' Mbps / 上行 ' + bu + ' Mbps');
				else
					facts.push('宽带容量在「网络 → 接口」该接口常规设置中填写（单位 Mbps）。勾选「宽带使用率」后在速率后显示占用百分比。');
			}
		} else if (key.indexOf('link:cli:') === 0) {
			facts.push('客户端与交换机连线。下方勾选对全部客户端及全部连线同时生效。');
		} else if (kind && kind.indexOf('link_') === 0) {
			facts.push('两点直线。蓝点拖两端，中段可整段平移。移动设备不会带动线段。');
			facts.push('速率标签可单独拖动位置，与线段位置互不影响。');
		}

		box.appendChild(E('h4', {}, this.entityTitle(key, kind)));
		facts.forEach(t => box.appendChild(E('p', {}, t)));
		if (this.layoutLock)
			box.appendChild(E('p', {}, '布局已锁定，不能拖动或改网卡方向/大小。'));
		if (!this.layoutLock && (key === 'internet' || key === 'gateway' || key === 'switch')) {
			box.appendChild(E('p', { 'class': 'topo-edit-lab' }, '大小'));
			box.appendChild(E('p', {}, '选中后拖四边、四角：左右改宽、上下改高，对边不动。'));
		}

		if (this.isClientSel(key, kind) || key === 'switch') {
			box.appendChild(E('p', { 'class': 'topo-edit-lab' }, '客户端显示数量（按综合速率）'));
			const num = E('input', {
				'type': 'number', min: '1', max: String(CLI_TOPN_MAX), step: '1',
				value: String(this.topN()),
				style: 'width:4.5em'
			});
			num.addEventListener('change', L.bind(function() {
				let n = Number(num.value);
				if (!(n >= 1))
					n = 1;
				if (n > CLI_TOPN_MAX)
					n = CLI_TOPN_MAX;
				this._topN = n;
				this.schedulePersist();
				this.rebuild(document.getElementById('topo-svg'), this.model);
				this.fillDetail();
			}, this));
			box.appendChild(E('label', { 'class': 'topo-opt' }, ['显示前 ', num, ' 台']));
		}

		if (key.indexOf('nic:') === 0 && !this.layoutLock) {
			box.appendChild(E('p', { 'class': 'topo-edit-lab' }, '网卡方向 / 大小（也可拖蓝点旋转、拖角缩放）'));
			const dirs = E('div', { 'class': 'topo-edit' });
			[['朝左', -90], ['朝下', 0], ['朝右', 90], ['朝上', 180]].forEach(pair => {
				dirs.appendChild(E('button', {
					'class': 'btn',
					'click': L.bind(function(ev) {
						ev.preventDefault();
						this.patchNic(key, { rot: pair[1] });
						this.savePos();
						this.rebuild(document.getElementById('topo-svg'), this.model);
					}, this)
				}, pair[0]));
			});
			box.appendChild(dirs);
			const szRow = E('div', { 'class': 'topo-edit' });
			szRow.appendChild(E('button', {
				'class': 'btn',
				'click': L.bind(function(ev) {
					ev.preventDefault();
					const s = Math.max(0.5, ((this.pos[key] || {}).s || 1) - 0.15);
					this.patchNic(key, { s: Math.round(s * 20) / 20 });
					this.savePos();
					this.rebuild(document.getElementById('topo-svg'), this.model);
					this.fillDetail();
				}, this)
			}, '缩小'));
			szRow.appendChild(E('button', {
				'class': 'btn',
				'click': L.bind(function(ev) {
					ev.preventDefault();
					const s = Math.min(2.8, ((this.pos[key] || {}).s || 1) + 0.15);
					this.patchNic(key, { s: Math.round(s * 20) / 20 });
					this.savePos();
					this.rebuild(document.getElementById('topo-svg'), this.model);
					this.fillDetail();
				}, this)
			}, '放大'));
			box.appendChild(szRow);
		}

		const addChecks = (lab, storeKey, catKind) => {
			const cat = FIELD_CATALOG[catKind] || [];
			if (!cat.length)
				return;
			box.appendChild(E('p', { 'class': 'topo-edit-lab' }, lab));
			const row = E('div', { 'class': 'topo-edit' });
			const shown = this.shown(storeKey, catKind);
			cat.forEach(f => {
				const c = E('input', { 'type': 'checkbox' });
				c.checked = shown.indexOf(f.id) >= 0;
				c.addEventListener('change', L.bind(function() {
					this.toggleField(storeKey, catKind, f.id, c.checked);
					this.rebuild(document.getElementById('topo-svg'), this.model);
					this.fillDetail();
				}, this));
				row.appendChild(E('label', { 'class': 'topo-opt' }, [c, ' ' + f.label]));
			});
			box.appendChild(row);
		};

		if (this.isClientSel(key, kind)) {
			addChecks('图上显示（对全部客户端生效）', 'cli-list', 'host');
			addChecks('连线显示（对全部客户端连线生效）', 'link:cli-all', 'link_sw_cli');
		} else {
			const cat = FIELD_CATALOG[kind] || [];
			if (cat.length)
				addChecks(kind === 'host' ? '图上显示（对全部客户端生效）' : '图上显示（只改当前选中的这一项）', key, kind);
		}
	},

	mountBandixDevList(hostEl) {
		const host = hostEl || this._bandixHost || document.getElementById('topo-bandix-devlist');
		if (!host || this._bandixDevListMounted || this._bandixDevListMounting)
			return;
		this._bandixDevListMounting = true;
		this._bandixHost = host;
		if (!host.querySelector('.topo-bandix-devlist-loading'))
			host.appendChild(E('p', { 'class': 'topo-bandix-devlist-loading' }, '正在加载 Bandix 设备列表…'));
		TopoBandixDevList.mount(host, {
			title: '设备列表',
			externalPoll: true,
			onRefreshRequest: L.bind(function() {
				return this.refreshBandixClients(false);
			}, this)
		}).then(L.bind(function() {
			const loading = host.querySelector('.topo-bandix-devlist-loading');
			if (loading && loading.parentNode)
				loading.parentNode.removeChild(loading);
			this._bandixDevListMounted = true;
			TopoBandixDevList.setSharedData(this._bandixDevices || [], this._bandixSchedules || []);
			this.refreshBandixClients(false);
		}, this)).catch(L.bind(function(err) {
			const loading = host.querySelector('.topo-bandix-devlist-loading');
			if (loading && loading.parentNode)
				loading.parentNode.removeChild(loading);
			const msg = err && err.message ? err.message : String(err);
			if (!/aborted/i.test(msg))
				host.appendChild(E('p', { 'class': 'alert-message warning' },
					'Bandix Plus 设备列表加载失败：' + msg));
		}, this)).finally(L.bind(function() {
			this._bandixDevListMounting = false;
		}, this));
	},

	unmountBandixDevList() {
		TopoBandixDevList.unmount();
		this._bandixDevListMounted = false;
		this._bandixDevListMounting = false;
		this._bandixHost = null;
	},

	topoClients(clients) {
		const list = clients || [];
		const on = list.filter(c => c.online !== false);
		if (on.length)
			return on.slice(0, this.topN());
		return list.slice(0, this.topN());
	},

	rebuild(svg, m) {
		if (!svg || !m)
			return;
		const host = (this.board && this.board.hostname) || '网关';
		const shown = this.topoClients(m.clients);
		const wanN = Math.max(1, m.wans.length);
		const rightN = Math.max(1, shown.length);
		const W = TOPO_CANVAS.w;
		const H = Math.max(TOPO_CANVAS.h,
			200 + Math.max((wanN - 1) * 52, (rightN - 1) * CLI_PITCH));
		svg.setAttribute('viewBox', '0 0 ' + W + ' ' + H);

		while (svg.firstChild)
			svg.removeChild(svg.firstChild);
		svg.appendChild(this.defs());
		svg.appendChild(svgEl('rect', { width: W, height: H, fill: '#fafbfc' }));
		svg.appendChild(svgEl('rect', { width: W, height: H, fill: 'url(#topo-grid)' }));
		const pipes = svgEl('g', { id: 'topo-pipes' });
		const packets = svgEl('g', { id: 'topo-packets' });
		const nodes = svgEl('g', { id: 'topo-nodes' });
		const nics = svgEl('g', { id: 'topo-nics' });
		const labels = svgEl('g', { id: 'topo-labels' });
		this._handleLayer = svgEl('g', { id: 'topo-handles' });
		svg.appendChild(pipes);
		svg.appendChild(packets);
		svg.appendChild(nodes);
		svg.appendChild(nics);
		svg.appendChild(labels);
		svg.appendChild(this._handleLayer);
		this._nicLayer = nics;
		this._flowSig = '';
		this._flowEls = [];
		this.drawSpeedLegend(labels, W, 22);

		this.flows = [];
		this._nodes = {};
		const T = TOPO_TEMPLATE;
		const inet = this.xy('internet', T.internet.x, T.internet.y);
		const gw = this.xy('gateway', T.gateway.x, T.gateway.y);
		const sw = this.xy('switch', T.switch.x, T.switch.y);
		svg.insertBefore(svgEl('rect', {
			x: gw.x - 140, y: 36, width: Math.max(320, sw.x - gw.x + 240), height: H - 72,
			rx: 14, fill: 'rgba(34,197,94,0.035)', stroke: 'rgba(34,197,94,0.14)', 'stroke-width': 1.2
		}), pipes);

		this.device(nodes, inet.x, inet.y, 'cloud', '运营商',
			this.pick('internet', 'internet', { hint: 'Internet' }),
			'ok', 'internet', 'internet');

		const wanOk = m.wans.filter(r => r.health === 'ok').length;
		const gwTone = !m.wans.length ? 'warn' : (wanOk ? 'ok' : 'bad');
		const gwBox = this.device(nodes, gw.x, gw.y, 'router', trunc(host, 12), this.pick('gateway', 'gateway', {
			role: '网关',
			lanip: m.lan.ipv4 || m.lan.device || '',
			cpu: 'CPU ' + (m.sys.cpu_pct != null ? m.sys.cpu_pct : '—') + '%',
			temp: m.sys.temp_c ? m.sys.temp_c + '℃' : '',
			conn: '连接数 ' + (m.sys.conn != null ? m.sys.conn : '—'),
			wans: (m.wans || []).map(r => r.w.name + ' ↓' + fmtBitrate(r.rx) + ' ↑' + fmtBitrate(r.tx))
		}), gwTone, 'gateway', 'gateway');

		if (!m.wans.length) {
			const noneMid = this.drawPipe(pipes, inet.x + T.inetJackDx, inet.y, gw.x - gwBox.w / 2, gw.y,
				'#94a3b8', 0, false, 'link:inet:none', 'link_inet_wan');
			this.decorateLink(labels, noneMid, 'link:inet:none', 'link_inet_wan', {});
		} else {
			m.wans.forEach((row, i) => {
				const nk = 'nic:' + row.w.name;
				const nic = this.nicState(nk, gw, -gwBox.w / 2 + 6, fan(0, i, wanN, 44), -90);
				const card = this.drawNic(nics, nic, {
					name: row.w.name,
					speed: speedTag(row.w.speed) || (row.w.up === false ? '离线' : '未知'),
					status: row.w.up === false ? '离线' : (row.text || ''),
					proto: protoLabel(row.w.proto),
					ip: row.w.ipv4 || '',
					lat: fmtLatency(row.w.latency),
					uptime: row.w.ifuptime ? fmtUptime(row.w.ifuptime) : '',
					rx: row.rx, tx: row.tx
				}, row.w.speed, row.w.up, nk, 'nic', 'gateway');
				const live = row.health === 'ok' && (row.rx + row.tx) > 200;
				const lk = 'link:inet:' + row.w.name;
				const mid = this.drawDuplex(pipes,
					inet.x + T.inetJackDx, inet.y + fan(0, i, wanN, T.wanFan),
					card.jackX, card.jackY,
					row.rx, row.tx, live, lk, 'link_inet_wan', {
						capRx: row.w.bw_down,
						capTx: row.w.bw_up,
						linkUp: row.w.up !== false
					});
				this.decorateLink(labels, mid, lk, 'link_inet_wan', {
					name: row.w.name,
					status: row.text || '',
					lat: fmtLatency(row.w.latency),
					rx: row.rx, tx: row.tx,
					bw_down: row.w.bw_down, bw_up: row.w.bw_up
				});
				if (row.w.up === false || row.health === 'bad')
					this.drawLinkFault(labels, mid);
			});
			if (m.wans.length >= 1) {
				let wanRx = 0, wanTx = 0;
				m.wans.forEach(r => { wanRx += r.rx; wanTx += r.tx; });
				this.drawWanSum(labels, inet.x + T.wanSum.dx, inet.y + T.wanSum.dy, wanTx, wanRx);
			}
		}

		const lanNic = this.nicState('nic:lan', gw, gwBox.w / 2 - 6, 8, 90);
		const lanCard = this.drawNic(nics, lanNic, {
			name: 'LAN',
			speed: speedTag((m.lan && m.lan.speed) || 0) || ((m.lan && m.lan.up === false) ? '离线' : '未知'),
			status: (m.lan && m.lan.up === false) ? '离线' : '',
			ip: (m.lan && m.lan.ipv4) || '',
			rx: m.lanDown, tx: m.lanUp
		}, (m.lan && m.lan.speed) || 0, !(m.lan && m.lan.up === false), 'nic:lan', 'nic', 'gateway');
		const lanLive = (m.lanDown + m.lanUp) > 200;

		const top = (m.clients || []).slice(0, this.topN());
		const rankLines = top.map(c =>
			(c.ip || c.name || '') + ' ↓' + fmtBitrate(c.rx) + ' ↑' + fmtBitrate(c.tx));
		const swPick = this.pick('switch', 'switch', {
			hint: 'LAN 上联合计',
			rate: '↓ ' + fmtBitrate(m.lanDown) + ' ↑ ' + fmtBitrate(m.lanUp),
			online: '在线终端 ' + ((m.sum && m.sum.online) || 0) + '/' + m.clients.length,
			rank: rankLines.length ? rankLines : ['暂无客户端速率']
		});
		const swBox = this.device(nodes, sw.x, sw.y, 'switch', '核心交换机', swPick, 'ok', 'switch', 'switch');

		/* ä¸ WAN å£ç¸åï¼x1 æ¯ä¸è¡æ¥æºä¾§ãLAN ä¸è¡æ¯ç½å³âäº¤æ¢æºï¼æä»¥ä¸æ¸¸ç«¯æ¯ç½å³ LAN å£ã */
		const lanCap = (m.lan && m.lan.speed) ? Number(m.lan.speed) : 0;
		const lanMid = this.drawDuplex(pipes, lanCard.jackX, lanCard.jackY, sw.x - swBox.w / 2, sw.y,
			m.lanDown, m.lanUp, lanLive, 'link:lan', 'link_gw_sw', {
				capRx: lanCap,
				capTx: lanCap,
				linkUp: !(m.lan && m.lan.up === false)
			});
		this.decorateLink(labels, lanMid, 'link:lan', 'link_gw_sw', {
			name: 'LAN',
			lat: '延迟 —',
			rx: m.lanDown, tx: m.lanUp
		});

		const pitch = CLI_PITCH;
		const stackN = shown.length;
		const stack = this.xy('cli-stack', sw.x + swBox.w / 2 + T.lanStackDx, sw.y);
		const x0 = stack.x;
		const yFirst = stack.y - ((Math.max(1, stackN) - 1) * pitch) / 2;
		const edgeX = sw.x + swBox.w / 2;
		const span = stackN > 1 ? Math.min(Math.max(20, swBox.h - 24), (stackN - 1) * pitch) : 0;
		const yRail0 = sw.y - span / 2;
		if (stackN > 1) {
			const railPts = [{ x: edgeX, y: yRail0 }, { x: edgeX, y: yRail0 + span }];
			const railBps = Math.max(0, m.lanDown + m.lanUp);
			const railIdle = !(m.lan && m.lan.up === false) && linkTrafficIdle(m.lanDown, m.lanUp);
			this.drawPoly(pipes, railPts, railIdle);
			this.addFlow(railPts, railBps, null, 'link:sw:rail', lanCap, null, railIdle, !(m.lan && m.lan.up === false));
		}
		const cliLayout = this.clientLayout(shown);
		shown.forEach((c, i) => {
			const ck = 'cli:' + (c.mac || c.ip || i);
			const cy = yFirst + i * pitch;
			const ay = stackN > 1 ? yRail0 + i * (span / Math.max(1, stackN - 1)) : sw.y;
			const live = (c.rx + c.tx) > 80;
			const clk = 'link:cli:' + (c.mac || c.ip || i);
			const cliBps = Math.max(Number(c.rx) || 0, Number(c.tx) || 0);
			const cmid = this.drawPipe(pipes, edgeX, ay, x0, cy,
				null, cliBps, live && c.online !== false, clk, 'link_sw_cli', false, null, {
					linkUp: c.online !== false,
					idleLink: c.online !== false && linkTrafficIdle(c.rx, c.tx, 80)
				});
			this.decorateLink(labels, cmid, clk, 'link_sw_cli', {
				/* Link captions only use the Bandix terminal name. */
				name: clientHostname(c),
				lat: '延迟 —',
				rx: c.rx, tx: c.tx
			});
			this.drawClient(nodes, x0, cy, c, ck, i, stackN, cliLayout);
		});
		if (this._linksDirty) {
			this._linksDirty = false;
			this.saveLinks();
		}
	},

	layoutSig(m) {
		const wans = (m.wans || []).map(r => r.w.name + ':' + (r.w.up ? '1' : '0') + ':' + (r.health || '') +
			':' + (r.w.bw_down || 0) + ':' + (r.w.bw_up || 0) + ':' + (r.w.latency || '') + ':' + (r.w.speed || 0)).join(',');
		const cli = (m.clients || []).slice(0, this.topN()).map(c => c.mac || c.ip).join(',');
		const gw = (this.pos || {}).gateway || {};
		const sw = (this.pos || {}).switch || {};
		const boxSig = [gw.w, gw.h, sw.w, sw.h].join(',');
		return [wans, cli, m.clients.length, this.topN(), this.selected, this.layoutLock,
			boxSig, JSON.stringify(this.fields || {})].join('|');
	},

	rateValue(m, tag) {
		if (!m || !tag)
			return 0;
		const parts = tag.split(':');
		const dir = parts[parts.length - 1];
		if (tag.indexOf('wan-sum:') === 0) {
			let s = 0;
			(m.wans || []).forEach(r => { s += (dir === 'tx' ? r.tx : r.rx); });
			return s;
		}
		if (tag === 'link:lan:tx' || tag === 'nic:lan:tx')
			return m.lanUp;
		if (tag === 'link:lan:rx' || tag === 'nic:lan:rx')
			return m.lanDown;
		if (tag.indexOf('link:inet:') === 0 || tag.indexOf('nic:') === 0) {
			const name = tag.indexOf('link:inet:') === 0
				? parts.slice(2, -1).join(':')
				: parts.slice(1, -1).join(':');
			const row = (m.wans || []).find(r => r.w.name === name);
			return row ? row[dir] : 0;
		}
		if (tag.indexOf('link:cli:') === 0) {
			const dir = parts[parts.length - 1];
			const id = parts.slice(2, -1).join(':');
			const c = (m.clients || []).find(x => x.mac === id || x.ip === id);
			if (!c)
				return 0;
			if (dir === 'rx' || dir === 'tx')
				return c[dir];
			return c.rx + c.tx;
		}
		if (tag.indexOf('cli:') === 0) {
			const id = parts.slice(1, -1).join(':');
			const c = (m.clients || []).find(x => x.mac === id || x.ip === id);
			return c ? c[dir] : 0;
		}
		return 0;
	},

	applyLiveRates(m) {
		const byId = {};
		(this.flows || []).forEach(f => {
			if (f.id)
				byId[f.id] = f;
		});
		const lanCap = (m.lan && m.lan.speed) ? Number(m.lan.speed) : 0;
		const lanLive = (m.lanDown + m.lanUp) > 200;
		(m.wans || []).forEach(row => {
			const k = 'link:inet:' + row.w.name;
			const live = row.health === 'ok' && (row.rx + row.tx) > LINK_IDLE_BPS;
			const capDn = Number(row.w.bw_down) || 0;
			const capUp = Number(row.w.bw_up) || 0;
			const linkUp = row.w.up !== false;
			const idleLink = linkUp && linkTrafficIdle(row.rx, row.tx);
			[ k + ':rx', k + ':tx' ].forEach(function(id, idx) {
				const f = byId[id];
				if (!f)
					return;
				f.linkUp = linkUp;
				applyFlowStyle(f, idx ? row.tx : row.rx, idx ? capUp : capDn, live);
				if (idleLink && (Number(f.bps) || 0) <= LINK_IDLE_BPS) {
					f.idleLink = true;
					f.px = LINK_IDLE_FLOW_PX;
					f.color = COL_LINK_IDLE;
				} else {
					f.idleLink = false;
				}
			});
		});
		const lanUp = !(m.lan && m.lan.up === false);
		const lanIdle = lanUp && linkTrafficIdle(m.lanDown, m.lanUp);
		[ 'link:lan:rx', 'link:lan:tx' ].forEach(function(id, idx) {
			const f = byId[id];
			if (!f)
				return;
			f.linkUp = lanUp;
			applyFlowStyle(f, idx ? m.lanUp : m.lanDown, lanCap, lanLive);
			if (lanIdle && (Number(f.bps) || 0) <= LINK_IDLE_BPS) {
				f.idleLink = true;
				f.px = LINK_IDLE_FLOW_PX;
				f.color = COL_LINK_IDLE;
			} else {
				f.idleLink = false;
			}
		});
		if (byId['link:sw:rail']) {
			byId['link:sw:rail'].linkUp = lanUp;
			applyFlowStyle(byId['link:sw:rail'], m.lanDown + m.lanUp, lanCap, lanLive);
			if (lanIdle && (Number(byId['link:sw:rail'].bps) || 0) <= LINK_IDLE_BPS) {
				byId['link:sw:rail'].idleLink = true;
				byId['link:sw:rail'].px = LINK_IDLE_FLOW_PX;
				byId['link:sw:rail'].color = COL_LINK_IDLE;
			}
		}
		(m.clients || []).forEach(c => {
			const base = 'link:cli:' + (c.mac || c.ip);
			const rx = Number(c.rx) || 0;
			const tx = Number(c.tx) || 0;
			const live = (rx + tx) > 80 && c.online !== false;
			if (c.online === false) {
				[ base + ':rx', base + ':tx' ].forEach(function(k) {
					if (!byId[k])
						return;
					byId[k].bps = 0;
					byId[k].color = COL_LINK_IDLE;
					byId[k].px = 0;
				});
				return;
			}
			[ base + ':rx', base + ':tx' ].forEach(function(k, idx) {
				const f = byId[k];
				if (!f)
					return;
				f.linkUp = true;
				applyFlowStyle(f, idx ? tx : rx, 0, live);
				if (linkTrafficIdle(rx, tx, 80) && (Number(f.bps) || 0) <= 80) {
					f.idleLink = true;
					f.px = LINK_IDLE_FLOW_PX;
					f.color = COL_LINK_IDLE;
				} else {
					f.idleLink = false;
				}
			});
		});
		const svg = document.getElementById('topo-svg');
		if (!svg)
			return;
		const self = this;
		svg.querySelectorAll('[data-rate-num]').forEach(function(el) {
			const tag = el.getAttribute('data-rate-num');
			const p = bitrateParts(self.rateValue(m, tag));
			el.textContent = p.num;
			const unit = svg.querySelector('[data-rate-unit="' + tag.replace(/"/g, '') + '"]');
			if (unit)
				unit.textContent = padFig(p.unit, RATE_UNIT_W, 'end');
			const pctEl = svg.querySelector('[data-rate-pct="' + tag.replace(/"/g, '') + '"]');
			if (pctEl) {
				const cap = Number(pctEl.getAttribute('data-rate-cap'));
				const pct = usagePct(p.num === undefined ? 0 : self.rateValue(m, tag), cap);
				pctEl.textContent = pct == null ? '' : '(' + pct + '%)';
				pctEl.setAttribute('fill', usageColor(pct == null ? 0 : pct));
			}
		});
	},

	paint(snap, info, svgNode) {
		if (this._dragging)
			return;
		if (info)
			this.info = info;
		const m = this.snapshotModel(this.mergeBandixSnap(snap || {}));
		this.model = m;
		const svg = svgNode || document.getElementById('topo-svg');
		if (!svg)
			return;
		const sig = this.layoutSig(m);
		if (svg.querySelector('#topo-pipes') && this._layoutSig === sig) {
			this.applyLiveRates(m);
			this.fillHud();
			return;
		}
		this._layoutSig = sig;
		this.rebuild(svg, m);
		this.fillHud();
		this.fillDetail();
	},

	render(data) {
		this.board = data[1] || {};
		this.info = {};
		this.hydrateLayout(data[2] || {}, true);
		const snapCk = E('input', { 'type': 'checkbox' });
		snapCk.checked = !!this.snapGrid;
		snapCk.addEventListener('change', L.bind(function() {
			this.snapGrid = !!snapCk.checked;
			this.schedulePersist();
		}, this));
		const lockCk = E('input', { 'type': 'checkbox' });
		lockCk.checked = !!this.layoutLock;
		lockCk.addEventListener('change', L.bind(function() {
			this.layoutLock = !!lockCk.checked;
			this.schedulePersist();
			if (this.model)
				this.rebuild(document.getElementById('topo-svg'), this.model);
			this.fillDetail();
		}, this));
		this._snapCk = snapCk;
		this._lockCk = lockCk;
		const svg = svgEl('svg', {
			id: 'topo-svg',
			class: 'topo-svg',
			preserveAspectRatio: 'xMidYMid meet'
		});
		svg.addEventListener('click', L.bind(function() {
			this.selected = null;
			this.selectedKind = null;
			this.fillDetail();
			if (this.model)
				this.rebuild(svg, this.model);
		}, this));
		const pageKids = [];
		const bandixHost = E('div', { 'id': 'topo-bandix-devlist', 'class': 'topo-bandix-devlist' });
		const bplusModalHost = E('div', { 'id': 'topo-bplus-modal-host', 'class': 'topo-bplus-modal-host' });
		this._bandixHost = bandixHost;
		const wrapKids = [
			E('div', { 'class': 'topo-hud-row' }, [
				E('div', { 'id': 'topo-hud', 'class': 'topo-hud' })
			]),
			svg,
			E('div', { 'id': 'topo-detail', 'class': 'topo-detail' }),
			bandixHost,
			bplusModalHost
		];
		const wrap = E('div', { 'id': 'lede-topo-pane', 'class': 'topo-wrap lede-page-panel' }, wrapKids);
		ledeTheme.injectStyles('lede-topo-page', [
			'#maincontent .topo-title h2 { display:block !important; margin:0; font-size:1.4em; font-weight:700; background:transparent !important; }',
			'.topo-hud-row { display:flex; flex-wrap:wrap; align-items:center; justify-content:space-between; gap:12px; margin:0 0 10px; width:100%; }',
			'.topo-hud { display:flex; flex-wrap:wrap; gap:8px; margin:0; flex:1 1 auto; min-width:0; }',
			'#maincontent h2[name="content"], #maincontent > .container > h2 { position: relative; padding-right: 0; min-height: 2em; }',
			'#maincontent h2[name="content"] > .lede-clock-status, #maincontent h2 > .lede-clock-status { position: absolute; left: 50%; top: 50%; transform: translate(-50%, -50%); margin: 0; pointer-events: none; }',
			'.lede-clock-status { white-space: nowrap; text-align: center; font-size: 18px; font-weight: 750; font-variant-numeric: tabular-nums; font-family: ui-monospace, SFMono-Regular, Consolas, "Liberation Mono", monospace; line-height: 1.2; color: var(--primary, #2563eb); }',
			'.topo-kpi .v { font-family: ui-monospace, SFMono-Regular, Consolas, "Liberation Mono", monospace; }',
			'.topo-wrap { width: 100%; min-width: 0; box-sizing: border-box; padding: 0; box-shadow: none; border: none; background: transparent; }',
			'.topo-layout-ops { display:flex; justify-content:flex-end; align-items:center; gap:14px; margin:0; font-size:12px; white-space:nowrap; pointer-events:auto; }',
			'.topo-layout-ops label { margin:0; cursor:pointer; }',
			'.topo-kpi { min-width:88px; padding:8px 10px; border-radius:8px; background: var(--cbi-section-bg, var(--background-color-high, #fff)); border:1px solid rgba(0,0,0,0.08); box-shadow: 0 2px 6px rgba(0,0,0,0.03); }',
			'.topo-kpi .k { font-size:11px; opacity:.65; }',
			'.topo-kpi .v { font-size:15px; font-weight:750; font-variant-numeric: tabular-nums; }',
			'.topo-svg { width:100%; height:auto; display:block; min-height:520px; overflow:hidden; background: var(--cbi-section-bg, var(--background-color-high, #fafbfc)); border:1px solid rgba(0,0,0,0.08); border-radius:8px; color: var(--text-color-high, #1e293b); box-shadow: 0 2px 6px rgba(0,0,0,0.03); }',
			'.topo-shumoku-card { pointer-events: bounding-box; }',
			'.topo-port-badge text { pointer-events: none; }',
			'.topo-detail { margin:12px 0; padding:12px 14px; border-radius:8px; border:1px solid rgba(0,0,0,0.08); background: var(--cbi-section-bg, var(--background-color-high, #fff)); min-height:88px; box-shadow: 0 2px 6px rgba(0,0,0,0.03); }',
			'.topo-detail h4 { margin:0 0 6px; }',
			'.topo-detail p { margin:4px 0; font-size:13px; }',
			'.topo-edit-lab { margin-top:10px !important; font-weight:650; }',
			'.topo-edit { display:flex; flex-wrap:wrap; gap:10px 14px; }',
			'.topo-wan-x { animation: topo-x-blink .7s step-end infinite; }',
			'@keyframes topo-x-blink { 50% { opacity: .12; } }'
		].join('\n'), [
			'.lede-clock-status { color: var(--primary, #60a5fa); }',
			'.topo-kpi, .topo-detail, .topo-svg { background: rgba(255,255,255,0.03); border-color: rgba(255,255,255,0.08); box-shadow: none; }'
		].join('\n'));

		this.paint(data[0] || {}, this.info, svg);
		this.mountBandixDevList(bandixHost);
		this.noteClock((data[0] && data[0].sys) || {});
		this.startLiveClock();
		this.startLivePoll();
		requestAnimationFrame(function() {
			const leftover = document.querySelector('.sidenav-header #lede-clock, .main-left #lede-clock');
			if (leftover && leftover.parentNode)
				leftover.parentNode.removeChild(leftover);
		});
		if (!this.animating) {
			this.animating = true;
			requestAnimationFrame(L.bind(this.tick, this));
		}
		pageKids.push(wrap);
		return ledeTheme.wrapCbiMap(
			ledeTheme.wrapSection(pageKids, 'topo-page'),
			'topo-page'
		);
	},

	handleRemove: function() {
		this.unmountBandixDevList();
		this.polling = false;
		this.animating = false;
		if (this._pollIv) {
			window.clearInterval(this._pollIv);
			this._pollIv = null;
		}
		if (this._clkIv) {
			window.clearInterval(this._clkIv);
			this._clkIv = null;
		}
	}
});

