'use strict';
'require view';
'require uci';
'require view.status.alertmap as AlertMap';
'require view.status.wanalert-layout as applyWanalertLayout';
'require lede-theme-page as ledeTheme';

function skipWanName(name, proto, device) {
	if (!name || name === 'loopback' || name === 'lo' || name === 'lan')
		return true;
	if (/_(6|v6)$/i.test(name) || /^wan6/i.test(name))
		return true;
	if (proto === 'none' || proto === 'relay')
		return true;
	if (device === 'br-lan' || device === 'lo')
		return true;
	return false;
}

function collectAlertWans() {
	const names = [];
	const seen = {};
	const add = function(n) {
		if (!n || seen[n])
			return;
		const proto = uci.get('network', n, 'proto') || '';
		const device = uci.get('network', n, 'device') || '';
		if (skipWanName(n, proto, device))
			return;
		seen[n] = true;
		names.push(n);
	};
	uci.sections('firewall', 'zone').forEach(function(z) {
		if ((z.name || uci.get('firewall', z['.name'], 'name')) !== 'wan')
			return;
		let nets = z.network || uci.get('firewall', z['.name'], 'network');
		if (!Array.isArray(nets))
			nets = nets ? [ nets ] : [];
		nets.forEach(add);
	});
	uci.sections('network', 'interface').forEach(function(s) {
		const n = s['.name'];
		const proto = s.proto || '';
		if (/^wan/i.test(n) || /^(pppoe|dhcp|pptp|l2tp|pppoa|3g|qmi|ncm|mbim|wwan|ppp|modemmanager)$/.test(proto))
			add(n);
	});
	uci.sections('mwan3', 'interface').forEach(function(s) {
		if (uci.get('mwan3', s['.name'], 'enabled') === '0')
			return;
		add(s['.name']);
	});
	return names;
}

function collectSvc() {
	let passwall = false;
	uci.sections('passwall', 'global').forEach(function(s) {
		const en = uci.get('passwall', s['.name'], 'enabled');
		if (en === '1' || en === true)
			passwall = true;
	});
	return {
		mosdns: uci.get('mosdns', 'config', 'enabled') === '1',
		passwall: passwall
	};
}

return view.extend({
	load() {
		return Promise.all([
			uci.load('wanalert'),
			uci.load('network'),
			uci.load('mwan3').catch(function() { return null; }),
			uci.load('firewall').catch(function() { return null; }),
			uci.load('mosdns').catch(function() { return null; }),
			uci.load('passwall').catch(function() { return null; })
		]);
	},

	render() {
		this.map = AlertMap.makeMap(collectAlertWans(), collectSvc());
		return this.map.render().then(function(node) {
			return applyWanalertLayout.applyPage(ledeTheme.enhanceMapNode(node));
		});
	}
});
