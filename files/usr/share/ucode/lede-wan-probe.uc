/* WAN 健康：对 mwan3 track_ip 做 ping（走该 WAN 的 L3 设备）。 */

function is_ipv4(s) {
	return match(`${s || ''}`, /^[0-9]{1,3}(\.[0-9]{1,3}){3}$/) != null;
}

export function track_ip_for(ctx, iface) {
	try { ctx.load('mwan3'); } catch (e) {}
	let list = ctx.get('mwan3', iface, 'track_ip');
	if (type(list) == 'array') {
		for (let ip in list)
			if (is_ipv4(ip))
				return ip;
	} else if (is_ipv4(list))
		return list;
	return '223.5.5.5';
}

export function iface_l3(u, name) {
	if (u == null)
		return '';
	try {
		let st = u.call('network.interface.' + name, 'status');
		if (st && st.l3_device)
			return st.l3_device;
		if (st && st.device)
			return st.device;
	} catch (e) {}
	return '';
}

export function wan_ping_ok(dev, host) {
	if (!dev || !host)
		return false;
	if (!match(dev, /^[A-Za-z0-9._-]+$/) || !is_ipv4(host))
		return false;
	return system(sprintf("ping -c 1 -W 2 -I '%s' '%s' >/dev/null 2>&1", dev, host)) == 0;
}

export function wan_probe_ok(ctx, u, iface) {
	let dev = iface_l3(u, iface);
	if (!dev)
		return false;
	return wan_ping_ok(dev, track_ip_for(ctx, iface));
}

export function wait_wan_probe(ctx, u, iface, sec) {
	let i = 0;
	while (i < sec) {
		system('sleep 2');
		i += 2;
		if (wan_probe_ok(ctx, u, iface))
			return true;
	}
	return wan_probe_ok(ctx, u, iface);
}
