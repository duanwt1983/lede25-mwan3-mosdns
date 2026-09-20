'use strict';

import { readfile, writefile, popen, unlink } from 'fs';
import * as ubus from 'ubus';
import { trim, as_bool, load_rate_hist, save_rate_hist, save_rate_windows } from '/usr/share/ucode/lede-metrics.uc';
import {
	bandix_load, bandix_build_maps, bandix_iface_rates, bandix_resolve_iface_rates,
	bandix_clients_list
} from '/usr/share/ucode/lede-bandix.uc';
import { wan_cause } from '/usr/share/ucode/lede-diag.uc';

const STATE = '/tmp/lede-watch.json';
const RATE_HIST_MAX = 8640;
const RH_EVERY = 10;
const ST_SAVE_EVERY = 3;
let LAST_LOG_T = 0;
let LAST_RH_T = 0;
let LAST_ST_SAVE = 0;
let RH = null;
let RH_SAVE = 0;

function load_st() {
	try {
		return json(readfile(STATE) || '{}') || {};
	} catch (e) {
		return {};
	}
}

function save_st(st) {
	writefile(STATE, sprintf('%J', st));
}

function g(ctx, key, def) {
	let v = ctx.get('wanalert', 'main', key);
	if (v == null || v == '')
		return def;
	return v;
}

function ev(out, level, cat, title, detail, key, flag) {
	push(out, { level, cat, title, detail, key, flag });
}

function mac_norm(s) {
	return uc(trim(s));
}

function arp_map(dev) {
	let m = {};
	let p = popen(sprintf("ip -4 neigh show dev '%s' 2>/dev/null", replace(dev || 'br-lan', /'/g, '')), 'r');
	if (!p)
		return m;
	let text = p.read('all') || '';
	p.close();
	for (let line in split(text, '\n')) {
		if (index(line, 'FAILED') >= 0 || index(line, 'INCOMPLETE') >= 0 || index(line, 'STALE') >= 0)
			continue;
		if (index(line, 'REACHABLE') < 0 && index(line, 'DELAY') < 0 && index(line, 'PROBE') < 0)
			continue;
		let f = split(trim(line), /[ \t]+/);
		if (length(f) < 5)
			continue;
		let ip = f[0];
		for (let i = 0; i < length(f); i++) {
			if (f[i] == 'lladdr' && i + 1 < length(f))
				m[ip] = mac_norm(f[i + 1]);
		}
	}
	return m;
}

function lan_runtime(ctx) {
	let dev = ctx.get('network', 'lan', 'device') || 'br-lan';
	let ip = ctx.get('network', 'lan', 'ipaddr') || '';
	let u = ubus_open();
	if (u) {
		try {
			let lst = u.call('network.interface.lan', 'status') || {};
			if (lst.l3_device)
				dev = lst.l3_device;
			let a4 = lst['ipv4-address'];
			if (type(a4) == 'array' && a4[0] && a4[0].address)
				ip = a4[0].address;
		} catch (e) {}
		ubus_close(u);
	}
	if (dev == '')
		dev = 'br-lan';
	return { dev, ip };
}

function lan_ident(ctx) {
	let dev = ctx.get('network', 'lan', 'device') || 'br-lan';
	dev = replace(`${dev}`, /[^A-Za-z0-9._-]/g, '');
	if (dev == '')
		dev = 'br-lan';
	let mac = mac_norm(trim(readfile('/sys/class/net/' + dev + '/address') || ''));
	let ip = '';
	let p = popen(sprintf("ip -4 -o addr show dev '%s' 2>/dev/null", dev), 'r');
	if (p) {
		let t = p.read('all') || '';
		p.close();
		let m = match(t, /inet ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)/);
		if (m)
			ip = m[1];
	}
	return { dev, mac, ip };
}

function arp_table(dev) {
	return arp_map(dev);
}

function lansec_arp(ctx) {
	try { ctx.load('lede-lansec'); } catch (e) {}
	if (!as_bool(ctx.get('lede-lansec', 'main', 'enabled'), false))
		return { detect: true, log: true, notify: true, scoped: false };
	if (!as_bool(ctx.get('lede-lansec', 'main', 'arp_enabled'), true))
		return { detect: false, log: false, notify: false, scoped: true };
	return {
		detect: true,
		log: as_bool(ctx.get('lede-lansec', 'main', 'arp_log'), true),
		notify: as_bool(ctx.get('lede-lansec', 'main', 'arp_notify'), true),
		scoped: true
	};
}

function check_arp(ctx, st, now, out) {
	let ls = lansec_arp(ctx);
	if (!ls.detect)
		return;
	let self = lan_ident(ctx);
	if (self.ip == '' || self.mac == '')
		return;
	if (type(st.arp) != 'object')
		st.arp = {};
	if (type(st.arp.ipmac) != 'object')
		st.arp.ipmac = {};
	if (type(st.arp.mm) != 'object')
		st.arp.mm = {};
	if (type(st.arp.flipn) != 'object')
		st.arp.flipn = {};
	let neigh = arp_table(self.dev);
	let leases = {};
	try { leases = lease_meta(); } catch (e) { leases = {}; }
	let issues = [];
	let arp_flag = (!ls.scoped || ls.notify) ? 'alert_arp' : '';
	if (ls.scoped && !ls.log && !ls.notify)
		return;
	if (neigh[self.ip] && neigh[self.ip] != self.mac) {
		let detail = sprintf('网关 %s 应为 %s，邻居表是 %s', self.ip, self.mac, neigh[self.ip]);
		ev(out, '严重', '安全', '网关地址被冒充', detail, 'arp-gw', arp_flag);
		push(issues, { kind: 'gateway', ip: self.ip, mac: neigh[self.ip] });
	}
	if (type(st.arp.prev2) != 'object')
		st.arp.prev2 = {};
	for (let ip in neigh) {
		let mac = neigh[ip];
		if (ip == self.ip)
			continue;
		let L = leases[ip];
		let lease_mac = (L && L.mac && L.mac != '*' && L.mac != '') ? mac_norm(L.mac) : '';
		let prev = st.arp.ipmac[ip];
		if (prev && prev.mac && prev.mac != mac) {
			let dt = now - +(prev.t || 0);
			let osc = (st.arp.prev2[ip] || '') == mac;
			if (osc && dt > 0 && dt < 300) {
				let detail = sprintf('%s 的 MAC 在 %s 与 %s 之间来回切换', ip, prev.mac, mac);
				ev(out, '中等', '安全', '同一 IP 的 MAC 来回切换', detail, 'arp-flip-' + ip, arp_flag);
				push(issues, { kind: 'flap', ip, from: prev.mac, to: mac, dt });
			}
			st.arp.prev2[ip] = prev.mac;
		} else if (!prev || prev.mac == mac)
			st.arp.prev2[ip] = '';
		st.arp.ipmac[ip] = { mac, t: now };
		if (lease_mac != '' && lease_mac != mac) {
			let n = +(st.arp.mm[ip] || 0) + 1;
			st.arp.mm[ip] = n;
			if (n >= 2) {
				let detail = sprintf('%s 租约 %s，邻居表 %s', ip, lease_mac, mac);
				ev(out, '中等', '安全', '有人占用已分配地址', detail, 'arp-lease-' + ip, arp_flag);
				push(issues, { kind: 'lease', ip, arp: mac, lease: lease_mac });
			}
		} else
			st.arp.mm[ip] = 0;
	}
	for (let ip in st.arp.ipmac) {
		if (now - +(st.arp.ipmac[ip].t || 0) > 3600)
			delete st.arp.ipmac[ip];
	}
	try {
		writefile('/tmp/lede-arp-guard.json', sprintf('%J', {
			t: now, gw_ip: self.ip, gw_mac: self.mac, lan: self.dev,
			neigh: length(neigh), issues
		}));
	} catch (e) {}
}

function lease_meta() {
	let by_ip = {};
	let statics = {};
	for (let line in split(readfile('/tmp/dhcp.leases') || '', '\n')) {
		let f = split(trim(line), /[ \t]+/);
		if (length(f) < 3)
			continue;
		by_ip[f[2]] = { mac: mac_norm(f[1]), host: (length(f) >= 4 && f[3] != '*') ? f[3] : '' };
	}
	return by_ip;
}

function link_mbps(dev) {
	if (!dev || match(dev, /[^A-Za-z0-9_.-]/))
		return 0;
	let n = +trim(readfile('/sys/class/net/' + dev + '/speed') || '');
	if (n > 0 && n < 200000)
		return int(n);
	return 0;
}

function alive(bin) {
	if (system(sprintf("command -v '%s' >/dev/null 2>&1", bin)) != 0)
		return null;
	return system(sprintf("pidof '%s' >/dev/null 2>&1", bin)) == 0;
}

function ubus_open() {
	try { return ubus.connect(); } catch (e) { return null; }
}

function ubus_close(u) {
	if (u == null)
		return;
	try { u.disconnect(); } catch (e) {}
}

function iface_bundle(ctx) {
	let u = ubus_open();
	let mw = {};
	if (u) {
		try {
			let mj = u.call('mwan3', 'status');
			if (mj && type(mj.interfaces) == 'object')
				mw = mj.interfaces;
		} catch (e) {}
	}
	let rows = [];
	ctx.foreach('mwan3', 'interface', (s) => {
		if (!as_bool(s.enabled, true))
			return;
		let name = s['.name'];
		let st = {};
		if (u) {
			try { st = u.call('network.interface.' + name, 'status') || {}; } catch (e) { st = {}; }
		}
		let dev = st.l3_device || ctx.get('network', name, 'device') || '';
		let phy = st.device || ctx.get('network', name, 'device') || '';
		let ip = '';
		let a4 = st['ipv4-address'];
		if (type(a4) == 'array' && a4[0] && a4[0].address)
			ip = a4[0].address;
		let up = (st.up == true || st.up == 1);
		let d = mw[name] || {};
		push(rows, {
			name, dev, phy, ip, up,
			track: d.status || '',
			bw_down: +(ctx.get('network', name, 'lede_bw_down') || 0),
			bw_up: +(ctx.get('network', name, 'lede_bw_up') || 0)
		});
	});
	let lan_dev = ctx.get('network', 'lan', 'device') || 'br-lan';
	if (u) {
		try {
			let lst = u.call('network.interface.lan', 'status') || {};
			if (lst.l3_device)
				lan_dev = lst.l3_device;
		} catch (e) {}
	}
	ubus_close(u);
	return { rows, lan_dev, mw };
}

function wan_rows(ctx) {
	return iface_bundle(ctx).rows;
}

function is_ipv4(s) {
	return match(`${s}`, /^[0-9]{1,3}(\.[0-9]{1,3}){3}$/) != null;
}

function ping_host_for(ctx, mw, name) {
	let d = mw[name];
	if (d && type(d.track_ip) == 'array') {
		for (let t in d.track_ip)
			if (t && t.status == 'up' && is_ipv4(t.ip))
				return t.ip;
		for (let t in d.track_ip)
			if (t && t.status != 'skipped' && is_ipv4(t.ip))
				return t.ip;
	}
	let list = ctx.get('mwan3', name, 'track_ip');
	if (type(list) == 'array') {
		for (let ip in list)
			if (is_ipv4(ip))
				return ip;
	} else if (is_ipv4(list))
		return list;
	return '223.5.5.5';
}

function kick_wan_ping(name, dev, host) {
	if (!dev || match(dev, /[^A-Za-z0-9._-]/) || !is_ipv4(host))
		return;
	let tag = replace(`${name}`, /[^A-Za-z0-9_]/g, '_');
	let stamp = '/tmp/lede-wan-lat-' + tag + '.t';
	let now = time();
	let last = +trim(readfile(stamp) || '0');
	if (last > 0 && now - last < 8)
		return;
	writefile(stamp, now + '\n');
	let out = '/tmp/lede-wan-lat-' + tag;
	system(sprintf("(ping -c 1 -W 1 -I %s %s 2>/dev/null | awk -F'time=' '/time=/{gsub(/ ms/,\"\"); print $2; exit}' > %s.tmp && mv %s.tmp %s) >/dev/null 2>&1 &",
		dev, host, out, out, out));
}

function read_wan_lat(name) {
	let tag = replace(`${name}`, /[^A-Za-z0-9_]/g, '_');
	let val = trim(readfile('/tmp/lede-wan-lat-' + tag) || '');
	if (match(val, /^[0-9]+(\.[0-9]+)?$/))
		return +val;
	return 0;
}

function trim_hist(a, max) {
	let n = length(a);
	if (n <= max)
		return a;
	let out = [];
	for (let i = n - max; i < n; i++)
		push(out, a[i]);
	return out;
}

function hist_obj() {
	if (RH == null) {
		RH = load_rate_hist();
		if (type(RH) != 'object')
			RH = {};
	}
	return RH;
}

function record_bandix_rate_hist(ctx, now) {
	let bj = bandix_load(true);
	if (!bj)
		return;

	let h = hist_obj();
	if (type(h) != 'object')
		h = {};
	if (type(h.series) != 'object')
		h.series = {};
	if (type(h.t) != 'array')
		h.t = [];

	let maps = bandix_build_maps(bj);
	let bundled = { rows: [], lan_dev: ctx.get('network', 'lan', 'device') || 'br-lan', mw: {} };
	try { bundled = iface_bundle(ctx); } catch (e) {}
	let rows = bundled.rows || [];
	let mw = bundled.mw || {};
	let lan_dev = bundled.lan_dev || ctx.get('network', 'lan', 'device') || 'br-lan';

	push(h.t, now);
	for (let w in rows) {
		if (!w || !w.name)
			continue;
		if (w.up)
			kick_wan_ping(w.name, w.dev, ping_host_for(ctx, mw, w.name));
		if (type(h.series[w.name]) != 'object')
			h.series[w.name] = { rx: [], tx: [], lat: [] };
		let r = bandix_resolve_iface_rates(maps, w.dev || w.name, [ w.name, w.dev ]);
		push(h.series[w.name].rx, r.down_bps);
		push(h.series[w.name].tx, r.up_bps);
		if (type(h.series[w.name].lat) != 'array')
			h.series[w.name].lat = [];
		while (length(h.series[w.name].lat) < length(h.series[w.name].rx) - 1)
			push(h.series[w.name].lat, 0);
		push(h.series[w.name].lat, w.up ? read_wan_lat(w.name) : 0);
	}
	if (type(h.series['_lan']) != 'object')
		h.series['_lan'] = { rx: [], tx: [], lat: [] };
	let lr = bandix_iface_rates(maps, lan_dev);
	push(h.series['_lan'].rx, lr.down_bps);
	push(h.series['_lan'].tx, lr.up_bps);

	h.t = trim_hist(h.t, RATE_HIST_MAX);
	for (let name in h.series) {
		h.series[name].rx = trim_hist(h.series[name].rx || [], RATE_HIST_MAX);
		h.series[name].tx = trim_hist(h.series[name].tx || [], RATE_HIST_MAX);
		if (type(h.series[name].lat) == 'array')
			h.series[name].lat = trim_hist(h.series[name].lat, RATE_HIST_MAX);
	}
	h.interval = 10;
	RH = h;
	try { save_rate_windows(h); } catch (e) {}
	if (!(RH_SAVE > 0) || now - RH_SAVE >= 60) {
		RH_SAVE = now;
		save_rate_hist(h, now);
	}
}

function scan_bandix_burst(ctx, st, out, bj, lan_ip, now, leases, arp) {
	let down_l = +g(ctx, 'burst_down_mbps', 50);
	let up_l = +g(ctx, 'burst_up_mbps', 20);
	let hold = +g(ctx, 'burst_hold_sec', 60);
	if (hold < 10)
		hold = 10;
	if (type(st.clients) != 'object')
		st.clients = {};

	let cl = bandix_clients_list(bj, lan_ip);
	let seen = {};
	for (let c in cl.clients) {
		let ip = c.ip || '';
		if (ip == '')
			continue;
		seen[ip] = true;
		let mac = c.mac || arp[ip] || '';
		let host = c.hostname || (leases[ip] ? leases[ip].host : '');
		let who = sprintf('%s  %s%s', mac != '' ? mac : '未知MAC', ip, host != '' ? ('（' + host + '）') : '');
		let down_mbps = (+c.down_bps || 0) / 1000000.0;
		let up_mbps = (+c.up_bps || 0) / 1000000.0;
		let dstr = sprintf('%.1f', down_mbps);
		let ustr = sprintf('%.1f', up_mbps);
		let prev = st.clients[ip];
		if (!prev) {
			st.clients[ip] = { mac, down_since: 0, up_since: 0, alert_down: 0, alert_up: 0, t: now };
			prev = st.clients[ip];
		}
		prev.mac = mac || prev.mac;
		prev.t = now;

		if (down_l > 0 && down_mbps >= down_l) {
			if (!(+prev.down_since > 0))
				prev.down_since = now;
			if (now - +prev.down_since >= hold && !prev.alert_down) {
				prev.alert_down = 1;
				ev(out, '中等', '设备', '下行突发持续',
					sprintf('%s 下行 %s Mbps，已持续 %d 秒（阈值 %s Mbps / %d 秒）。',
						who, dstr, now - +prev.down_since, down_l, hold),
					'burst-down-' + ip, 'alert_burst_down');
			}
		} else {
			prev.down_since = 0;
			prev.alert_down = 0;
		}

		if (up_l > 0 && up_mbps >= up_l) {
			if (!(+prev.up_since > 0))
				prev.up_since = now;
			if (now - +prev.up_since >= hold && !prev.alert_up) {
				prev.alert_up = 1;
				ev(out, '中等', '设备', '上行突发持续',
					sprintf('%s 上行 %s Mbps，已持续 %d 秒（阈值 %s Mbps / %d 秒）。',
						who, ustr, now - +prev.up_since, up_l, hold),
					'burst-up-' + ip, 'alert_burst_up');
			}
		} else {
			prev.up_since = 0;
			prev.alert_up = 0;
		}
		st.clients[ip] = prev;
	}
	for (let ip in st.clients) {
		if (!seen[ip] && now - +(st.clients[ip].t || 0) > 120)
			delete st.clients[ip];
	}
}

function dns_answer_ok(text) {
	if (text == null || trim(text) == '')
		return false;
	if (match(text, /timed out|SERVFAIL|REFUSED|can't resolve|connection refused|network is unreachable|no servers/i))
		return false;
	if (match(text, /status: NOERROR|status: NXDOMAIN/))
		return true;
	if (match(text, /Address([ \t]+[0-9]+)?:[ \t]+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/))
		return true;
	if (match(text, /[ \t][0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[ \t]*\n/))
		return true;
	return false;
}

function dns_lookup(qname, server, port) {
	qname = replace(`${qname}`, /'/g, '');
	server = replace(`${server}`, /'/g, '');
	port = `${port || '53'}`;
	let text = '';
	let p;
	if (system('command -v dig >/dev/null 2>&1') == 0) {
		p = popen(sprintf("dig @%s -p %s +time=2 +tries=1 +retry=0 '%s' A 2>/dev/null", server, port, qname), 'r');
		if (p) {
			text = p.read('all') || '';
			p.close();
		}
		return dns_answer_ok(text);
	}
	if (port != '53') {
		p = popen(sprintf("nslookup -port=%s '%s' '%s' 2>/dev/null", port, qname, server), 'r');
		if (p) {
			text = p.read('all') || '';
			p.close();
		}
		if (dns_answer_ok(text))
			return true;
		if (system('command -v nc >/dev/null 2>&1') == 0) {
			let q = '\\x4c\\x44\\x01\\x00\\x00\\x01\\x00\\x00\\x00\\x00\\x00\\x00';
			for (let lab in split(qname, '.')) {
				if (lab == '')
					continue;
				q += sprintf('\\x%02x', length(lab)) + lab;
			}
			q += '\\x00\\x00\\x01\\x00\\x01';
			p = popen(sprintf("printf '%s' | nc -u -w 2 %s %s 2>/dev/null | wc -c", q, server, port), 'r');
			let n = p ? trim(p.read('all') || '0') : '0';
			if (p)
				p.close();
			if (+n > 20)
				return true;
		}
		return false;
	}
	p = popen(sprintf("nslookup '%s' '%s' 2>/dev/null", qname, server), 'r');
	if (!p)
		return false;
	text = p.read('all') || '';
	p.close();
	if (port != '53')
		return false;
	return dns_answer_ok(text);
}

function dns_track(st, out, key, ok, title_fail, title_ok, detail, nlim) {
	if (type(st.dns) != 'object')
		st.dns = {};
	let d = st.dns[key];
	if (type(d) != 'object')
		d = { n: 0, hit: 0 };
	if (ok) {
		if (d.hit)
			ev(out, '一般', '网络', title_ok, detail, 'dns-up-' + key, 'alert_dns');
		st.dns[key] = { n: 0, hit: 0 };
		return;
	}
	d.n = +d.n + 1;
	if (d.n >= nlim && !d.hit) {
		d.hit = 1;
		ev(out, '中等', '网络', title_fail,
			sprintf('%s 连续 %d 次未获应答。', detail, d.n),
			'dns-down-' + key, 'alert_dns');
	}
	st.dns[key] = d;
}

function check_mosdns_upstreams(ctx, st, out) {
	try { ctx.load('mosdns'); } catch (e) {}
	if (!as_bool(ctx.get('mosdns', 'config', 'enabled'), false))
		return;
	if (alive('mosdns') != true)
		return;
	let port = ctx.get('mosdns', 'config', 'listen_port') || '5335';
	let nlim = +g(ctx, 'dns_fail_n', 2);
	if (nlim < 1)
		nlim = 1;
	let q_local = g(ctx, 'dns_local_q', 'www.baidu.com');
	let q_remote = g(ctx, 'dns_remote_q', 'www.google.com');
	let loc_ok = dns_lookup(q_local, '127.0.0.1', port);
	if (!loc_ok && port != '53')
		loc_ok = dns_lookup(q_local, '127.0.0.1', '53');
	dns_track(st, out, 'local', loc_ok, '国内上游无应答', '国内上游恢复',
		sprintf('查询 %s @127.0.0.1:%s（走 MosDNS 国内链路）', q_local, port), nlim);

	let rem_ok = dns_lookup(q_remote, '127.0.0.1', port);
	if (!rem_ok && port != '53')
		rem_ok = dns_lookup(q_remote, '127.0.0.1', '53');
	dns_track(st, out, 'remote', rem_ok, '国外上游无应答', '国外上游恢复',
		sprintf('查询 %s @127.0.0.1:%s（走 MosDNS 国外链路）', q_remote, port), nlim);

	if (rem_ok)
		return;
	if (!as_bool(ctx.get('mosdns', 'config', 'dns_follow_wan'), true))
		return;
	let i = 0;
	ctx.foreach('mwan3', 'interface', (s) => {
		if (!as_bool(s.enabled, true))
			return;
		i++;
		let wp = 5300 + i;
		let ok = dns_lookup(q_remote, '127.0.0.1', wp);
		dns_track(st, out, 'wan' + i, ok,
			sprintf('%s 线路 DNS 无应答', s['.name']),
			sprintf('%s 线路 DNS 恢复', s['.name']),
			sprintf('查询 %s @127.0.0.1:%d', q_remote, wp), nlim);
	});
}

function recent_log_rows(limit) {
	let u = ubus_open();
	if (!u)
		return [];
	let res = null;
	try {
		res = u.call('log', 'read', {
			lines: limit,
			stream: false,
			oneshot: true
		});
	} catch (e) {}
	ubus_close(u);
	return res && type(res.log) == 'array' ? res.log : [];
}

function keep_recent_times(v, since) {
	let out = [];
	if (type(v) != 'array')
		return out;
	for (let t in v) {
		if (+t >= since)
			push(out, +t);
	}
	return out;
}

function remote_num(ctx, key, def, lo, hi) {
	let n = +(ctx.get('lede-remote', 'main', key) || def);
	if (!(n >= lo) || n > hi)
		n = def;
	return n;
}

function remote_ban(ip, seconds) {
	if (!match(ip, /^([0-9]{1,3}[.]){3}[0-9]{1,3}$/))
		return false;
	let path = '/tmp/lede-remote-ban.nft';
	writefile(path, sprintf(
		'add element inet lede_remote_guard ban4 { %s timeout %ds }\n',
		ip, seconds));
	return system("nft -f /tmp/lede-remote-ban.nft >/dev/null 2>&1") == 0;
}

function scan_remote_access(ctx, st, out, line, now) {
	if ((ctx.get('lede-remote', 'main', 'scan_enabled') || '1') == '0')
		return;
	let m = match(line, /wanhttps:\s+([0-9.]+)\|([A-Z]+)\|([^|]*)\|([0-9]+)\|([01])/);
	if (!m)
		return;
	let ip = m[1];
	let method = m[2];
	let uri = m[3];
	let status = +m[4];
	let login = m[5] == '1';
	let scan_window = remote_num(ctx, 'scan_window_min', 5, 1, 60) * 60;
	let login_window = remote_num(ctx, 'login_window_min', 10, 1, 60) * 60;
	let scan_alert_n = remote_num(ctx, 'scan_alert_n', 10, 3, 1000);
	let scan_ban_n = remote_num(ctx, 'scan_ban_n', 30, 5, 5000);
	let login_ban_n = remote_num(ctx, 'login_ban_n', 8, 3, 100);
	let ban_sec = remote_num(ctx, 'ban_minutes', 30, 1, 1440) * 60;
	let auto_ban = (ctx.get('lede-remote', 'main', 'auto_ban') || '1') != '0';
	let suspicious = status >= 400 || !match(method, /^(GET|POST|HEAD)$/) ||
		match(uri, /\/(\.env|wp-|phpmyadmin|cgi-bin|actuator|vendor|boaform|HNAP1)/i);

	if (type(st.remote_guard) != 'object')
		st.remote_guard = {};
	let hit = st.remote_guard[ip];
	if (type(hit) != 'object')
		hit = { scan: [], login: [], scan_notice: 0, login_notice: 0, ban_until: 0 };
	hit.scan = keep_recent_times(hit.scan, now - scan_window);
	hit.login = keep_recent_times(hit.login, now - login_window);
	hit.last = now;
	hit.uri = uri;
	if (suspicious)
		push(hit.scan, now);
	if (login)
		push(hit.login, now);

	if (length(hit.scan) >= scan_alert_n && now >= +(hit.scan_notice || 0)) {
		ev(out, '中等', '安全', '远程管理端口遭扫描',
			sprintf('来源 %s 在 %d 分钟内触发 %d 次异常访问，最近路径 %s。',
				ip, int(scan_window / 60), length(hit.scan), uri),
			'remote-scan-' + ip, 'alert_remote_scan');
		hit.scan_notice = now + scan_window;
	}
	if (length(hit.login) >= login_ban_n && now >= +(hit.login_notice || 0)) {
		ev(out, '中等', '安全', '远程登录尝试过多',
			sprintf('来源 %s 在 %d 分钟内提交 %d 次登录请求。',
				ip, int(login_window / 60), length(hit.login)),
			'remote-login-' + ip, 'alert_remote_scan');
		hit.login_notice = now + login_window;
	}

	let should_ban = length(hit.scan) >= scan_ban_n || length(hit.login) >= login_ban_n;
	if (auto_ban && should_ban && now >= +(hit.ban_until || 0)) {
		if (remote_ban(ip, ban_sec)) {
			hit.ban_until = now + ban_sec;
			ev(out, '中等', '安全', '已临时封禁远程来源',
				sprintf('来源 %s 已封禁 %d 分钟；扫描 %d 次，登录请求 %d 次。到期自动解封。',
					ip, int(ban_sec / 60), length(hit.scan), length(hit.login)),
				'remote-ban-' + ip, 'alert_remote_scan');
		}
	}
	st.remote_guard[ip] = hit;
}

function scan_logread(ctx, st, out) {
	let rows = recent_log_rows(80);
	if (length(rows) == 0)
		return;
	let prev = +(st.logid || 0);
	let newest = 0;
	let fails = st.login_fails;
	if (type(fails) != 'array')
		fails = [];
	let now = time();
	let fresh = [];
	for (let t in fails) {
		if (now - +t < 600)
			push(fresh, +t);
	}
	fails = fresh;
	for (let row in rows) {
		let id = +(row.id || 0);
		if (id > newest)
			newest = id;
	}
	if (!(newest > 0))
		return;
	/* Establish the initial baseline without replaying the existing ring. */
	if (!(prev > 0)) {
		st.logid = newest;
		st.login_fails = fails;
		return;
	}
	/* A logd restart resets ids; its ring then contains only post-restart
	 * entries, so consume that tail rather than dropping fresh events. */
	if (newest < prev)
		prev = 0;
	for (let row in rows) {
		let id = +(row.id || 0);
		if (!(id > prev))
			continue;
		let line = trim(row.msg || '');
		if (line == '')
			continue;
		scan_remote_access(ctx, st, out, line, now);
		if (match(line, /Bad password|Login attempt|auth(entication)? fail/i) && match(line, /dropbear|sshd|lede-login/i))
			push(fails, now);
		if (match(line, /CHAP authentication failed|PAP authentication failed|Unable to authenticate/i))
			ev(out, '中等', '网络', '拨号认证失败', line, 'ppp-auth', 'alert_ppp_fail');
		if (match(line, /no address available|no addresses available/i))
			ev(out, '中等', '系统', '地址池空了', line, 'dhcp-empty', 'alert_dhcp');
		if (match(line, /lost tracking on interface|tracking is down/i))
			ev(out, '中等', '网络', '线路探测失败', line, 'track-log', 'alert_track');
	}
	st.logid = newest;
	st.login_fails = fails;
	if (type(st.remote_guard) == 'object') {
		for (let ip in st.remote_guard) {
			let h = st.remote_guard[ip];
			if (type(h) != 'object' || now - +(h.last || 0) > 172800)
				delete st.remote_guard[ip];
		}
	}
	let nlim = +st._login_n || 5;
	if (length(fails) >= nlim)
		ev(out, '中等', '安全', '登录失败次数过多',
			sprintf('近 10 分钟失败 %d 次（阈值 %d）。', length(fails), nlim),
			'login-fail-burst', 'alert_login_fail');
}

function wan_hold_sec(ctx, key, def) {
	let n = +g(ctx, key, def);
	if (!(n >= 0))
		n = def;
	if (n > 120)
		n = 120;
	return n;
}

function emit_wan_updown(ctx, st, out) {
	if (type(st.wanup) != 'object')
		st.wanup = {};
	if (type(st.track) != 'object')
		st.track = {};
	if (type(st.wan_dn_t) != 'object')
		st.wan_dn_t = {};
	if (type(st.wan_dn_sent) != 'object')
		st.wan_dn_sent = {};
	if (type(st.wan_up_t) != 'object')
		st.wan_up_t = {};
	let down_hold = wan_hold_sec(ctx, 'wan_down_hold', 5);
	let up_hold = wan_hold_sec(ctx, 'wan_up_hold', 3);
	let now = time();
	let rows = [];
	try { rows = wan_rows(ctx); } catch (e) { rows = []; }
	for (let w in rows) {
		let upn = w.up ? 1 : 0;
		let prevu = st.wanup[w.name];
		if (!w.up) {
			delete st.wan_up_t[w.name];
			if (prevu == 1 || prevu == null) {
				if (!(+st.wan_dn_t[w.name] > 0))
					st.wan_dn_t[w.name] = now;
				st.wan_dn_sent[w.name] = false;
			}
			let since = now - (+st.wan_dn_t[w.name] || now);
			if (!st.wan_dn_sent[w.name] && (down_hold == 0 || since >= down_hold)) {
				st.wan_dn_sent[w.name] = true;
				let cause = '';
				try { cause = wan_cause(w.name); } catch (e) { cause = ''; }
				let trnote = (w.track && w.track != '') ? sprintf('mwan3探测=%s。', w.track) : '';
				ev(out, '中等', '网络', '断线告警',
					sprintf('【%s】判定为外网不可用（尚未自动修复）。%s%s', w.name, trnote, cause),
					'down-' + w.name, 'alert_down');
			}
		} else {
			delete st.wan_dn_t[w.name];
			st.wan_dn_sent[w.name] = false;
			if (prevu == 0) {
				if (!(+st.wan_up_t[w.name] > 0))
					st.wan_up_t[w.name] = now;
				let since = now - (+st.wan_up_t[w.name] || now);
				if (up_hold == 0 || since >= up_hold) {
					ev(out, '一般', '网络', '线路恢复',
						sprintf('网口 %s 已恢复正常。', w.name),
						'up-' + w.name, 'alert_up');
					delete st.wan_up_t[w.name];
					st.wanup[w.name] = 1;
				}
				continue;
			}
			delete st.wan_up_t[w.name];
			st.wanup[w.name] = 1;
			continue;
		}
		st.wanup[w.name] = upn;
		let tr = w.track || '';
		let prevt = st.track[w.name] || '';
		if (w.up && tr == 'offline' && prevt != 'offline')
			ev(out, '中等', '网络', '线路探测失败',
				sprintf('【%s】逻辑接口 up，但 mwan3 外网探测 offline（物理链路可能仍正常）。', w.name),
				'track-' + w.name, 'alert_track');
		else if (prevt == 'offline' && tr == 'online')
			ev(out, '一般', '网络', '线路探测恢复',
				sprintf('%s 探测已恢复 online。', w.name),
				'track-up-' + w.name, 'alert_track');
		st.track[w.name] = tr;
	}
	let n_wan = 0;
	let n_up = 0;
	let n_down_ok = 0;
	for (let w in rows) {
		n_wan++;
		if (w.up)
			n_up++;
		else if (st.wan_dn_sent[w.name])
			n_down_ok++;
	}
	if (n_wan >= 2 && n_up == 0 && n_down_ok == n_wan) {
		if (!st.all_down_sent)
			ev(out, '严重', '网络', '全部 WAN 掉线',
				'所有已启用 WAN 均不可用，内网将无法上网。',
				'all-down', 'alert_all_down');
		st.all_down_sent = true;
	} else
		st.all_down_sent = false;
	return rows;
}

export function collect_tick(ctx) {
	let out = [];
	let st = load_st();
	st._login_n = +g(ctx, 'login_fail_n', 5);
	let now = time();
	if (!(LAST_LOG_T > 0) || now - LAST_LOG_T >= 10) {
		LAST_LOG_T = now;
		try { scan_logread(ctx, st, out); } catch (e) {}
	}

	let lan_ip = ctx.get('network', 'lan', 'ipaddr') || '';
	let lan_dev = ctx.get('network', 'lan', 'device') || 'br-lan';
	try {
		let rt = lan_runtime(ctx);
		if (rt.dev)
			lan_dev = rt.dev;
		if (rt.ip)
			lan_ip = rt.ip;
	} catch (e) {}
	let arp = {};
	try { arp = arp_table(lan_dev); } catch (e) { arp = {}; }
	let leases = {};
	try { leases = lease_meta(); } catch (e) { leases = {}; }

	let bj = bandix_load(true);
	if (bj) {
		try { scan_bandix_burst(ctx, st, out, bj, lan_ip, now, leases, arp); } catch (e) {}
	}

	if (!(LAST_RH_T > 0) || now - LAST_RH_T >= RH_EVERY) {
		LAST_RH_T = now;
		try { record_bandix_rate_hist(ctx, now); } catch (e) {}
	}
	try { emit_wan_updown(ctx, st, out); } catch (e) {}
	if (!(LAST_ST_SAVE > 0) || now - LAST_ST_SAVE >= ST_SAVE_EVERY) {
		LAST_ST_SAVE = now;
		save_st(st);
	}
	return out;
}

export function collect_interval(ctx) {
	let out = [];
	let st = load_st();
	let now = time();
	if (type(st.link) != 'object')
		st.link = {};
	if (type(st.bw) != 'object')
		st.bw = {};
	if (type(st.bw_hit) != 'object')
		st.bw_hit = {};
	if (type(st.bw_since) != 'object')
		st.bw_since = {};
	if (type(st.link_hit) != 'object')
		st.link_hit = {};
	if (type(st.macs) != 'object')
		st.macs = {};
	let rows = emit_wan_updown(ctx, st, out);
	let bw_pct = +g(ctx, 'wan_bw_percent', 90);
	let bw_hold = +g(ctx, 'wan_bw_hold_min', 5);
	if (!(bw_hold >= 0))
		bw_hold = 0;
	let bj = bandix_load(true);
	let maps = bj ? bandix_build_maps(bj) : null;
	for (let w in rows) {
		let spd = link_mbps(w.dev) || link_mbps(w.phy);
		let last = +st.link[w.name];
		if (spd > last)
			st.link[w.name] = spd;
		if (last >= 1000 && spd > 0 && spd <= 100 && !st.link_hit[w.name]) {
			st.link_hit[w.name] = 1;
			ev(out, '中等', '网络', '网口协商降速',
				sprintf('%s 设备 %s 由 %d M 降为 %d M。', w.name, w.dev || w.phy, last, spd),
				'link-' + w.name, 'alert_link_speed');
		} else if (last > 0 && spd > 0 && spd < last && spd * 2 <= last && !st.link_hit[w.name]) {
			st.link_hit[w.name] = 1;
			ev(out, '中等', '网络', '网口协商降速',
				sprintf('%s 设备 %s 由 %d M 降为 %d M。', w.name, w.dev || w.phy, last, spd),
				'link-' + w.name, 'alert_link_speed');
		} else if (spd > 0 && last > 0 && spd >= last && st.link_hit[w.name]) {
			st.link_hit[w.name] = 0;
			ev(out, '一般', '网络', '网口速率恢复',
				sprintf('%s 当前 %d M。', w.name, spd),
				'link-up-' + w.name, 'alert_link_speed');
		}

		if (maps) {
			let r = bandix_resolve_iface_rates(maps, w.dev || w.name, [ w.name, w.dev ]);
			let down_mbps = r.down_bps / 1000000.0;
			let up_mbps = r.up_bps / 1000000.0;
			let dkey = w.name + '-d';
			let down_high = w.bw_down > 0 && down_mbps >= w.bw_down * bw_pct / 100.0;
			if (down_high) {
				if (!(+st.bw_since[dkey] > 0))
					st.bw_since[dkey] = now;
				if (now - +st.bw_since[dkey] >= bw_hold * 60 && !st.bw_hit[dkey]) {
					st.bw_hit[w.name + '-d'] = 1;
					ev(out, '中等', '网络', 'WAN 下行接近上限',
						sprintf('%s 下行 %.1f Mbps，配置上限 %s Mbps（阈值 %d%%），已持续至少 %d 分钟。',
							w.name, down_mbps, w.bw_down, bw_pct, bw_hold),
						'wanbw-d-' + w.name, 'alert_wan_bw');
				}
			} else {
				st.bw_hit[dkey] = 0;
				st.bw_since[dkey] = 0;
			}
			let ukey = w.name + '-u';
			let up_high = w.bw_up > 0 && up_mbps >= w.bw_up * bw_pct / 100.0;
			if (up_high) {
				if (!(+st.bw_since[ukey] > 0))
					st.bw_since[ukey] = now;
				if (now - +st.bw_since[ukey] >= bw_hold * 60 && !st.bw_hit[ukey]) {
					st.bw_hit[ukey] = 1;
					ev(out, '中等', '网络', 'WAN 上行接近上限',
						sprintf('%s 上行 %.1f Mbps，配置上限 %s Mbps（阈值 %d%%），已持续至少 %d 分钟。',
							w.name, up_mbps, w.bw_up, bw_pct, bw_hold),
						'wanbw-u-' + w.name, 'alert_wan_bw');
				}
			} else {
				st.bw_hit[ukey] = 0;
				st.bw_since[ukey] = 0;
			}
		}
	}

	let conn = +(trim(readfile('/proc/sys/net/netfilter/nf_conntrack_count') || '0'));
	let conn_max = +(trim(readfile('/proc/sys/net/netfilter/nf_conntrack_max') || '0'));
	let cpct = +g(ctx, 'conn_percent', 80);
	if (conn_max > 0 && conn * 100 / conn_max >= cpct) {
		if (!st.conn_hit) {
			st.conn_hit = 1;
			ev(out, '中等', '系统', '连接跟踪占用高',
				sprintf('当前 %d / %d（%d%%），阈值 %d%%。', conn, conn_max, int(conn * 100 / conn_max), cpct),
				'conntrack', 'alert_conntrack');
		}
	} else
		st.conn_hit = 0;

	let known_n = 0;
	for (let _ in st.macs)
		known_n++;
	let seeded = known_n > 0;
	for (let line in split(readfile('/tmp/dhcp.leases') || '', '\n')) {
		let f = split(trim(line), /[ \t]+/);
		if (length(f) < 3)
			continue;
		let mac = mac_norm(f[1]);
		let ip = f[2];
		let host = (length(f) >= 4 && f[3] != '*') ? f[3] : '';
		if (mac == '' || mac == '*')
			continue;
		if (!st.macs[mac]) {
			st.macs[mac] = 1;
			if (seeded)
				ev(out, '一般', '设备', '新设备入网',
					sprintf('MAC %s 获得 %s%s', mac, ip, host != '' ? ('（' + host + '）') : ''),
					'newmac-' + mac, 'alert_new_mac');
		}
	}

	let isp = trim(readfile('/var/run/isp-ip-update.status') || '');
	if (isp != '' && match(isp, /^FAIL/)) {
		if (st.isp != isp)
			ev(out, '中等', '网络', 'ISP 地址库更新失败', isp, 'isp-fail', 'alert_isp');
		st.isp = isp;
	} else if (isp != '')
		st.isp = isp;

	let overlay_ok = false;
	try {
		writefile('/overlay/.lede-write-test', 'ok\n');
		let ok = trim(readfile('/overlay/.lede-write-test') || '');
		try { unlink('/overlay/.lede-write-test'); } catch (e2) {}
		overlay_ok = (ok == 'ok');
	} catch (e) {
		overlay_ok = false;
	}
	if (!overlay_ok) {
		if (!st.overlay_hit)
			ev(out, '严重', '系统', 'Overlay 无法写入', '探测文件读写失败，overlay 可能只读。', 'overlay-ro', 'alert_overlay');
		st.overlay_hit = true;
	} else
		st.overlay_hit = false;

	try { check_mosdns_upstreams(ctx, st, out); } catch (e) {}
	try { check_arp(ctx, st, now, out); } catch (e) {}

	st.n = +(st.n || 0) + 1;
	if (st.n % 6 == 1 && system('command -v smartctl >/dev/null 2>&1') == 0) {
		let p = popen("ls /dev/sd[a-z] /dev/nvme[0-9]n1 2>/dev/null", 'r');
		let devs = p ? (p.read('all') || '') : '';
		if (p)
			p.close();
		for (let d in split(devs, '\n')) {
			d = trim(d);
			if (d == '')
				continue;
			let q = popen(sprintf("smartctl -H '%s' 2>/dev/null", d), 'r');
			let body = q ? (q.read('all') || '') : '';
			if (q)
				q.close();
			if (match(body, /FAILED|FAILING|SMART overall-health.*FAILED/i))
				ev(out, '严重', '系统', '磁盘健康异常', d + ' ' + trim(body), 'smart-' + replace(d, /\//g, '_'), 'alert_smart');
		}
	}

	save_st(st);
	return out;
}
