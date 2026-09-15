'use strict';

import { cursor } from 'uci';
import { readfile, writefile, popen } from 'fs';
import { trim } from '/usr/share/ucode/lede-metrics.uc';

const BPLUS_CACHE = '/tmp/lede-bandix-snap.json';
const BPLUS_CACHE_TTL = 4;

function lc(s) {
	s = `${s}`;
	let out = '';
	for (let i = 0; i < length(s); i++) {
		let c = substr(s, i, 1);
		let o = ord(c);
		if (o >= 65 && o <= 90)
			out += sprintf('%c', o + 32);
		else
			out += c;
	}
	return out;
}

export function bandix_port() {
	let ctx = cursor();
	try { ctx.load('bandix_plus'); } catch (e) {}
	let p = ctx.get('bandix_plus', 'general', 'port');
	if (p == null || p == '')
		return 8787;
	return +p;
}

function bplus_up(m) {
	if (type(m) != 'object')
		return 0;
	return +(m.up_v4_bps || 0) + +(m.up_v6_bps || 0);
}

function bplus_down(m) {
	if (type(m) != 'object')
		return 0;
	return +(m.down_v4_bps || 0) + +(m.down_v6_bps || 0);
}

function bplus_iface_rates(m) {
	return { down_bps: bplus_up(m), up_bps: bplus_down(m) };
}

function bplus_client_rates(m) {
	return { down_bps: bplus_down(m), up_bps: bplus_up(m) };
}

function bandix_cache_read() {
	try {
		let c = json(readfile(BPLUS_CACHE) || '{}') || {};
		if (c.ok && c.data)
			return c;
	} catch (e) {}
	return null;
}

/* Bandix 不可用时返回 null，不使用过期缓存兜底。 */
export function bandix_load(use_cache) {
	let cached = bandix_cache_read();
	if (use_cache && cached && time() - +(cached._t || 0) <= BPLUS_CACHE_TTL)
		return cached;

	let port = bandix_port();
	let p = popen(sprintf('curl -sf --connect-timeout 1 --max-time 3 http://127.0.0.1:%d/api/snapshot 2>/dev/null', port), 'r');
	if (!p)
		return null;
	let raw = p.read('all') || '';
	p.close();
	if (raw == '')
		return null;

	let j = null;
	try {
		j = json(raw);
	} catch (e) {
		return null;
	}
	if (!j || !j.ok || type(j.data) != 'object')
		return null;

	j._t = time();
	try {
		writefile(BPLUS_CACHE, sprintf('%J', j));
	} catch (e) {}
	return j;
}

export function bandix_resolve_iface_rates(maps, ifname, extras) {
	let z = { down_bps: 0, up_bps: 0 };
	if (!maps || !ifname)
		return z;
	if (maps.if_rates[ifname])
		return maps.if_rates[ifname];
	if (type(extras) == 'array') {
		for (let i = 0; i < length(extras); i++) {
			let e = extras[i];
			if (e && maps.if_rates[e])
				return maps.if_rates[e];
		}
	}
	for (let k in maps.if_rates) {
		if (ifname.indexOf(k) >= 0 || k.indexOf(ifname) >= 0)
			return maps.if_rates[k];
	}
	return z;
}

export function bandix_build_maps(bj) {
	let if_rates = {};
	let dev_rates = {};

	if (!bj || !bj.data)
		return { if_rates, dev_rates };

	for (let iface in (bj.data.interfaces || [])) {
		let ifname = iface.ifname || '';
		if (!ifname)
			continue;
		let m = iface.metrics || {};
		if_rates[ifname] = bplus_iface_rates(m);
	}

	for (let dev in (bj.data.devices || [])) {
		let mac = lc(dev.mac || '');
		let m = dev.metrics || {};
		let rates = bplus_client_rates(m);
		if (mac)
			dev_rates[mac] = rates;
		if (type(dev.ipv4) == 'array') {
			for (let ip in dev.ipv4) {
				if (ip)
					dev_rates['ip:' + ip] = rates;
			}
		}
	}
	return { if_rates, dev_rates };
}

export function bandix_iface_rates(maps, ifname, extras) {
	return bandix_resolve_iface_rates(maps, ifname, extras);
}

function bplus_label(dev) {
	let h = trim(dev.hostname || '');
	if (h == '' || h == '-')
		return '';
	return h;
}

export function bandix_clients_list(bj, lan_ip) {
	let clients = [];
	let online = 0;
	if (!bj || !bj.data || type(bj.data.devices) != 'array')
		return { clients, online, leases: 0 };

	let seen = {};
	for (let dev in bj.data.devices) {
		if (type(dev) != 'object')
			continue;
		let iface = dev.logical_iface || '';
		if (iface != '' && iface != 'br-lan')
			continue;
		let mac = lc(dev.mac || '');
		if (mac && seen[mac])
			continue;
		let ip = '';
		if (type(dev.ipv4) == 'array') {
			for (let a in dev.ipv4) {
				if (a && a != '') {
					ip = a;
					break;
				}
			}
		}
		if (lan_ip != '' && ip == lan_ip)
			continue;
		if (!mac && !ip)
			continue;
		if (mac)
			seen[mac] = true;
		let m = dev.metrics || {};
		let cr = bplus_client_rates(m);
		let label = bplus_label(dev);
		let on = (dev.online == true);
		if (on)
			online++;
		push(clients, {
			mac: mac,
			ip: ip,
			hostname: label,
			name: label,
			online: on,
			rx_bytes: 0,
			tx_bytes: 0,
			down_bps: cr.down_bps,
			up_bps: cr.up_bps
		});
	}
	return { clients, online, leases: length(clients) };
}

export function bandix_wan_rates(maps, wans) {
	let out = {};
	if (!maps || type(wans) != 'array')
		return out;
	for (let w in wans) {
		let dev = w.device || '';
		let name = w.name || '';
		if (!dev && !name)
			continue;
		out[name] = bandix_resolve_iface_rates(maps, dev || name, [ name, dev ]);
	}
	return out;
}

export function bandix_rate_meta(bj, wans, lan_dev, clients) {
	let empty = {
		interval: 2,
		n: 0,
		last: time(),
		series_tip: {},
		source: 'bandix'
	};
	if (!bj)
		return empty;

	let maps = bandix_build_maps(bj);
	let tip = {};
	for (let w in wans) {
		let r = bandix_iface_rates(maps, w.device || '');
		tip[w.name] = { rx: r.down_bps, tx: r.up_bps, lat: 0 };
	}
	let lr = bandix_iface_rates(maps, lan_dev || 'br-lan');
	tip._lan = { rx: lr.down_bps, tx: lr.up_bps, lat: 0 };
	if (type(clients) == 'array') {
		for (let c in clients) {
			let down = +(c.down_bps || 0);
			let up = +(c.up_bps || 0);
			if (!(down > 0 || up > 0))
				continue;
			if (c.mac)
				tip[c.mac] = { rx: down, tx: up, lat: 0 };
			if (c.ip)
				tip[c.ip] = { rx: down, tx: up, lat: 0 };
		}
	}
	return {
		interval: 2,
		n: 1,
		last: time(),
		series_tip: tip,
		source: 'bandix'
	};
}
