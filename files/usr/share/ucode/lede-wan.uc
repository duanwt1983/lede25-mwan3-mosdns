'use strict';

import { as_list } from '/usr/share/ucode/lede-metrics.uc';

export function skip_wan_iface(sid) {
	if (sid == null || sid == '')
		return true;
	if (sid == 'loopback' || sid == 'lan' || sid == 'wan6')
		return true;
	if (match(sid, /_6$/) || match(sid, /^@/))
		return true;
	return false;
}

export function wan_like_proto(proto) {
	return proto == 'pppoe' || proto == 'dhcp' || proto == 'pptp' || proto == 'l2tp' ||
		proto == 'pppoa' || proto == '3g' || proto == 'ncm' || proto == 'qmi' ||
		proto == 'modemmanager' || proto == 'mbim' || proto == 'wwan' ||
		proto == 'ppp' || proto == 'dslite' || proto == 'vti' || proto == 'gre';
}

export function add_wan_name(names, seen, sid) {
	if (skip_wan_iface(sid) || seen[sid])
		return;
	seen[sid] = true;
	push(names, sid);
}

/* Same WAN discovery as wanmonitor snapshot / pulse (firewall + network + default route). */
export function collect_wan_names(ctx, u) {
	let names = [];
	let seen = {};

	ctx.foreach('firewall', 'zone', (z) => {
		if (z.name != 'wan')
			return;
		for (let n in as_list(z.network))
			add_wan_name(names, seen, n);
	});

	ctx.foreach('network', 'interface', (s) => {
		let sid = s['.name'];
		if (skip_wan_iface(sid) || seen[sid])
			return;
		if (match(sid, /^wan/) || wan_like_proto(s.proto))
			add_wan_name(names, seen, sid);
	});

	if (u) {
		try {
			let dump = u.call('network.interface', 'dump');
			if (dump && type(dump.interface) == 'array') {
				for (let it in dump.interface) {
					let n = it.interface;
					if (skip_wan_iface(n) || seen[n])
						continue;
					let routes = it.route;
					if (type(routes) != 'array')
						continue;
					for (let r in routes) {
						if (r && (r.target == '0.0.0.0' || r.target == '::')) {
							add_wan_name(names, seen, n);
							break;
						}
					}
				}
			}
		} catch (e) {}
	}

	return names;
}

export function wan_status_row(ctx, u, mw, name) {
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
	let d = (mw && mw[name]) ? mw[name] : {};
	return {
		name, dev, phy, ip, up,
		track: d.status || '',
		bw_down: +(ctx.get('network', name, 'lede_bw_down') || 0),
		bw_up: +(ctx.get('network', name, 'lede_bw_up') || 0)
	};
}

export function collect_wan_rows(ctx, u, mw) {
	let rows = [];
	for (let name in collect_wan_names(ctx, u))
		push(rows, wan_status_row(ctx, u, mw, name));
	return rows;
}
