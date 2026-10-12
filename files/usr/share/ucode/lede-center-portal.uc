'use strict';

import { cursor } from 'uci';
import { readfile } from 'fs';

function trim(s) {
	if (s == null)
		s = '';
	return replace(`${s}`, /^\s+|\s+$/g, '');
}

function uci_get(ctx, sect, key) {
	let v = ctx.get('lede-center', sect, key);
	if (v == null)
		return '';
	return trim(v);
}

function hostname() {
	let ctx = cursor();
	let h = '';
	try {
		ctx.load('system');
		ctx.foreach('system', 'system', function(s) {
			if (h == '')
				h = trim(s.hostname || '');
		});
	} catch (e) {}
	if (h != '')
		return h;
	h = trim(readfile('/proc/sys/kernel/hostname') || '');
	return h != '' ? h : 'gateway';
}

function lan_ip(ctx) {
	let lip = uci_get(ctx, 'main', 'local_luci_ip');
	if (lip != '')
		return lip;
	try {
		ctx.load('network');
	} catch (e) {}
	return uci_get(ctx, 'lan', 'ipaddr');
}

function tunnel_rows(ctx) {
	let out = [];
	ctx.foreach('lede-center', 'tunnel', function(s) {
		if (trim(s.enabled || '') != '1')
			return;
		let name = trim(s.name || '');
		let lip = trim(s.local_ip || '');
		let lport = trim(s.local_port || '');
		let rport = trim(s.remote_port || '');
		if (name == '' || lip == '' || lport == '' || rport == '')
			return;
		let row = {
			name: name,
			port: +rport,
			local: lip + ':' + lport
		};
		let remark = trim(s.remark || '');
		if (remark != '')
			row.remark = remark;
		push(out, row);
	});
	return out;
}

/* JSON body for POST /home/api/gateway/register */
export function register_payload() {
	let ctx = cursor();
	ctx.load('lede-center');
	let site_id = uci_get(ctx, 'main', 'site_id');
	let name = uci_get(ctx, 'main', 'display_name');
	if (name == '')
		name = hostname();
	let region = uci_get(ctx, 'main', 'region');
	let luci_port = +uci_get(ctx, 'main', 'remote_port_luci');
	let ssh_port = +uci_get(ctx, 'main', 'remote_port_ssh');
	if (!(ssh_port >= 0))
		ssh_port = 0;
	let lip = lan_ip(ctx);
	let lport = uci_get(ctx, 'main', 'local_luci_port');
	if (lport == '')
		lport = '443';
	let luci_host = lip;
	if (luci_host != '' && lport != '' && lport != '443')
		luci_host = luci_host + ':' + lport;
	else if (luci_host == '')
		luci_host = '';
	return {
		site_id: site_id,
		name: name,
		region: region,
		luci_port: luci_port,
		luci_host: luci_host,
		ssh_port: ssh_port,
		tunnels: tunnel_rows(ctx)
	};
}
