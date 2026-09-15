'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require poll';
'require ui';
'require fs';

const callStatus = rpc.declare({
	object: 'lede-autolimit',
	method: 'status',
	expect: {}
});

const callRelease = rpc.declare({
	object: 'lede-autolimit',
	method: 'release',
	params: [ 'mac' ],
	expect: {}
});

function kbpsToMbpsStr(kbps) {
	const n = Number(kbps) || 0;
	if (n <= 0)
		return '0';
	const mbps = n / 1000;
	const r = Math.round(mbps * 1000) / 1000;
	if (Math.abs(r - Math.round(r)) < 0.0001)
		return String(Math.round(r));
	return String(r);
}

function mbpsStrToKbps(str) {
	const mbps = parseFloat(String(str || '').trim());
	if (!isFinite(mbps) || mbps <= 0)
		return 0;
	return Math.round(mbps * 1000);
}

function addMbpsOption(section, opt, title, desc) {
	const o = section.option(form.Value, opt, title, desc);
	o.datatype = 'ufloat';
	o.cfgvalue = function(section_id) {
		return kbpsToMbpsStr(uci.get('lede-autolimit', section_id, opt));
	};
	o.write = function(section_id, formvalue) {
		uci.set('lede-autolimit', section_id, opt, String(mbpsStrToKbps(formvalue)));
	};
	return o;
}

function fmtMbpsFromKbps(v) {
	const n = Number(v) || 0;
	if (n <= 0)
		return '不限';
	const mbps = n / 1000;
	if (Math.abs(mbps - Math.round(mbps)) < 0.01)
		return Math.round(mbps) + ' Mbps';
	return (Math.round(mbps * 100) / 100) + ' Mbps';
}

function fmtRemain(sec) {
	const s = Math.max(0, Math.floor(Number(sec) || 0));
	if (s <= 0)
		return '即将解除';
	const m = Math.floor(s / 60);
	const r = s % 60;
	if (m >= 60) {
		const h = Math.floor(m / 60);
		const mm = m % 60;
		return h + ' 时 ' + mm + ' 分';
	}
	if (m > 0)
		return m + ' 分 ' + r + ' 秒';
	return r + ' 秒';
}

const WL_HEADER = '# 用法：备注名称 MAC地址（每行一条，# 开头为注释）';

function isMac(s) {
	return /^([0-9a-f]{2}:){5}[0-9a-f]{2}$/i.test(String(s || '').toLowerCase());
}

function normMacLine(line) {
	line = String(line || '').trim();
	if (!line || line.charAt(0) === '#')
		return null;
	const hash = line.indexOf('#');
	if (hash >= 0)
		line = line.substring(0, hash).trim();
	const parts = line.split(/\s+/).filter(function(p) { return p; });
	if (!parts.length)
		return null;
	let mac = '';
	let name = '';
	if (parts.length >= 2 && isMac(parts[parts.length - 1])) {
		mac = parts[parts.length - 1].toLowerCase();
		name = parts.slice(0, -1).join(' ').trim();
	} else if (isMac(parts[0])) {
		mac = parts[0].toLowerCase();
		name = parts.slice(1).join(' ').trim();
	} else {
		return null;
	}
	return { mac: mac, name: name || '白名单' };
}

function fetchBrLanMac() {
	return fs.exec('ip', [ 'link', 'show', 'dev', 'br-lan' ]).then(function(res) {
		const m = String(res.stdout || '').match(/link\/ether\s+([0-9a-f:]{17})/i);
		return m ? m[1].toLowerCase() : '';
	}).catch(function() { return ''; });
}

function whitelistToText(brLanMac) {
	const lines = [ WL_HEADER ];
	const seen = {};
	uci.sections('lede-autolimit', 'whitelist').forEach(function(sid) {
		const mac = (uci.get('lede-autolimit', sid, 'mac') || '').toLowerCase();
		const name = uci.get('lede-autolimit', sid, 'name') || '';
		if (!mac || seen[mac])
			return;
		seen[mac] = true;
		lines.push((name || '白名单') + ' ' + mac);
	});
	if (brLanMac && !seen[brLanMac])
		lines.push('br-lan ' + brLanMac);
	return lines.join('\n') + '\n';
}

function parseWhitelistText(formvalue) {
	const want = {};
	const lines = String(formvalue || '').replace(/\r\n/g, '\n').split('\n');
	for (let i = 0; i < lines.length; i++) {
		const item = normMacLine(lines[i]);
		if (item)
			want[item.mac] = item.name;
	}
	return want;
}

function applyWhitelistText(formvalue) {
	const want = parseWhitelistText(formvalue);
	const sids = uci.sections('lede-autolimit', 'whitelist').slice();
	for (let i = 0; i < sids.length; i++)
		uci.remove('lede-autolimit', sids[i]);
	for (const mac in want) {
		const sid = uci.add('lede-autolimit', 'whitelist');
		uci.set('lede-autolimit', sid, 'mac', mac);
		uci.set('lede-autolimit', sid, 'name', want[mac]);
	}
}

function sectionTitleText(h3) {
	if (!h3)
		return '';
	const clone = h3.cloneNode(true);
	const extra = clone.querySelectorAll('.al-pill, .al-title-extra');
	for (let i = 0; i < extra.length; i++)
		extra[i].parentNode.removeChild(extra[i]);
	return clone.textContent.trim();
}

function findSectionByTitle(root, title) {
	const secs = root.querySelectorAll('.cbi-section');
	for (let i = 0; i < secs.length; i++) {
		const h3 = secs[i].querySelector('h3');
		if (sectionTitleText(h3) === title)
			return secs[i];
	}
	return null;
}

function mountStatusInBasicTitle(root) {
	const sec = findSectionByTitle(root, '基本设置');
	if (!sec)
		return;
	const h3 = sec.querySelector('h3');
	if (!h3)
		return;
	h3.classList.add('al-basic-title');
	if (document.getElementById('al-status-pill'))
		return;
	h3.appendChild(E('span', {
		'id': 'al-status-pill',
		'class': 'al-pill off'
	}, '加载中…'));
}

function markWhitelistSection(root) {
	const sec = findSectionByTitle(root, 'MAC 白名单');
	if (sec)
		sec.classList.add('al-wl-section');
}

function injectCss() {
	if (document.getElementById('lede-autolimit-css'))
		return;
	document.head.appendChild(E('style', { id: 'lede-autolimit-css' }, [
		'.al-page{width:100%;max-width:none;}',
		'.al-page .cbi-map{display:grid;grid-template-columns:1fr 1fr;gap:1em;align-items:stretch;max-width:none!important;width:100%!important;}',
		'.al-page .cbi-section,.al-page .cbi-section-node{max-width:none!important;width:100%!important;}',
		'.al-page .cbi-map>.cbi-section{margin-bottom:0!important;min-width:0;}',
		'.al-page .cbi-map>.cbi-section:nth-child(1),.al-page .cbi-map>.cbi-section:nth-child(2){display:flex;flex-direction:column;height:100%;}',
		'.al-page .cbi-map>.cbi-section:nth-child(1) .cbi-section-node,.al-page .cbi-map>.cbi-section:nth-child(2) .cbi-section-node{flex:1 1 auto;display:flex;flex-direction:column;}',
		'.al-page .cbi-map>.cbi-section:nth-child(n+5),.al-page .cbi-map>.cbi-page-actions{grid-column:1/-1;}',
		'@media (max-width:960px){.al-page .cbi-map{grid-template-columns:1fr;}.al-page .cbi-map>.cbi-section:nth-child(n+5){grid-column:auto;}}',
		'.al-page .cbi-section h3.al-basic-title{display:flex;align-items:center;flex-wrap:wrap;gap:8px;}',
		'.al-pill{display:inline-flex;align-items:center;padding:2px 10px;border-radius:999px;font-size:12px;font-weight:600;line-height:1.6;}',
		'.al-pill.ok{background:#e8f5e9;color:#2e7d32;}',
		'.al-pill.warn{background:#fff8e1;color:#f57f17;}',
		'.al-pill.off{background:#eceff1;color:#546e7a;}',
		'.al-mono{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12px;}',
		'.al-rate{color:#1565c0;font-variant-numeric:tabular-nums;}',
		'.al-countdown{font-weight:700;color:#e65100;font-variant-numeric:tabular-nums;}',
		'.al-empty{padding:1.2em;text-align:center;color:#90a4ae;}',
		'.al-meta{font-size:12px;color:#78909c;margin-top:.5em;}',
		'.al-badge{display:inline-block;padding:2px 8px;border-radius:4px;background:#e0f7fa;color:#00838f;font-size:11px;font-weight:600;}',
		'.al-badge.penalty{background:#fff3e0;color:#e65100;}',
		'.al-wl-section textarea{width:50%!important;max-width:50%!important;min-width:280px;box-sizing:border-box;}',
		'@media (max-width:960px){.al-wl-section textarea{width:100%!important;max-width:100%!important;}}'
	].join('\n')));
}

function paintStatus(st) {
	const pill = document.getElementById('al-status-pill');
	if (!pill)
		return;
	if (!st || !st.ok) {
		pill.className = 'al-pill warn';
		pill.textContent = 'Bandix 不可用';
		return;
	}
	if (!st.enabled) {
		pill.className = 'al-pill off';
		pill.textContent = '已关闭';
		return;
	}
	if (st.bandix_ok) {
		pill.className = 'al-pill ok';
		pill.textContent = '运行中 · Bandix 正常';
	} else {
		pill.className = 'al-pill warn';
		pill.textContent = '已启用 · Bandix 异常';
	}
}

function paintList(st) {
	const box = document.getElementById('al-active-list');
	const meta = document.getElementById('al-list-meta');
	if (!box)
		return;
	const rows = (st && st.active) ? st.active : [];
	if (!rows.length) {
		box.innerHTML = '';
		box.appendChild(E('div', { 'class': 'al-empty' }, '当前没有自动限速中的客户端。'));
		if (meta)
			meta.textContent = (st && st.track_n > 0)
				? ('正在观察 ' + st.track_n + ' 台设备的持续超阈状态。')
				: '';
		return;
	}
	const tbl = E('table', { 'class': 'table cbi-section-table' }, [
		E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, '客户端'),
			E('th', { 'class': 'th' }, 'MAC'),
			E('th', { 'class': 'th' }, '当前↓/↑'),
			E('th', { 'class': 'th' }, '限速↓/↑'),
			E('th', { 'class': 'th' }, '剩余'),
			E('th', { 'class': 'th' }, '触发'),
			E('th', { 'class': 'th' }, '')
		])
	]);
	for (let i = 0; i < rows.length; i++) {
		const r = rows[i];
		const name = (r.hostname && r.hostname !== '—') ? r.hostname : (r.ip || r.mac || '—');
		const badgeCls = 'al-badge' + (r.penalty ? ' penalty' : '');
		tbl.appendChild(E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td' }, [
				E('div', {}, name),
				r.ip ? E('div', { 'class': 'al-meta' }, r.ip) : ''
			]),
			E('td', { 'class': 'td al-mono' }, r.mac || '—'),
			E('td', { 'class': 'td al-rate' }, fmtMbpsFromKbps(r.current_down_kbps) + ' / ' + fmtMbpsFromKbps(r.current_up_kbps)),
			E('td', { 'class': 'td' }, fmtMbpsFromKbps(r.limit_down_kbps) + ' / ' + fmtMbpsFromKbps(r.limit_up_kbps)),
			E('td', { 'class': 'td al-countdown' }, fmtRemain(r.remain_sec)),
			E('td', { 'class': 'td' }, E('span', { 'class': badgeCls }, r.reason || '超阈')),
			E('td', { 'class': 'td' }, E('button', {
				'class': 'btn cbi-button cbi-button-remove',
				'click': function(ev) {
					ev.preventDefault();
					if (!r.mac || !confirm('确定解除 ' + name + ' 的自动限速？'))
						return;
					callRelease(String(r.mac || '')).then(function(res) {
						if (!res || res.ok === false)
							throw new Error((res && res.error) ? res.error : 'release failed');
						return refresh(true);
					}).catch(function(e) {
						ui.addNotification(null, E('p', {}, '解除失败：' + (e.message || String(e))), 'error');
					});
				}
			}, '解除'))
		]));
	}
	box.innerHTML = '';
	box.appendChild(tbl);
	if (meta) {
		let txt = '共 ' + rows.length + ' 台';
		if (st && st.track_n > 0)
			txt += ' · 另有 ' + st.track_n + ' 台在累计超阈时长';
		meta.textContent = txt;
	}
}

function refresh(silent) {
	return callStatus().then(function(st) {
		paintStatus(st);
		paintList(st);
		return st;
	}).catch(function(e) {
		if (!silent)
			ui.addNotification(null, E('p', {}, '刷新失败：' + (e.message || String(e))), 'warning');
	});
}

return view.extend({
	load() {
		return Promise.all([
			uci.load('lede-autolimit'),
			callStatus().catch(function() { return null; })
		]);
	},

	render() {
		injectCss();

		const m = new form.Map('lede-autolimit', '自动限速');

		/* 模块一：基本设置 */
		const s1 = m.section(form.NamedSection, 'main', 'main', '基本设置');
		s1.addremove = false;

		s1.option(form.Flag, 'enabled', '启用自动限速',
			'开启后后台按间隔检测 Bandix 设备速率并自动下发/解除限速。');

		s1.option(form.Value, 'interval_sec', '检测间隔 (秒)',
			'轮询 Bandix 的间隔，建议 20～60。')
			.datatype = 'uinteger';

		/* 模块二：限速时长与加罚（与基本设置并排，故紧接其后渲染） */
		const s4 = m.section(form.NamedSection, 'main', 'main', '限速时长与加罚');
		s4.addremove = false;

		s4.option(form.Value, 'limit_minutes', '首次限速时长 (分钟)',
			'首次触发后保持限速的分钟数；到期后自动解除。')
			.datatype = 'uinteger';

		s4.option(form.Value, 'penalty_window_minutes', '加罚观察窗口 (分钟)',
			'自上次自动解除起，在此时间内若再次满足持续超阈条件，改用加罚限速时长（无冷静期，解除后仍持续检测）。')
			.datatype = 'uinteger';

		s4.option(form.Value, 'penalty_limit_minutes', '加罚限速时长 (分钟)',
			'加罚观察窗口内再次触发时使用的更长限速分钟数。')
			.datatype = 'uinteger';

		/* 模块三：下行策略 */
		const s2 = m.section(form.NamedSection, 'main', 'main', '下行策略');
		s2.addremove = false;
		s2.description = '填 0 表示不检测或不限速该方向。';

		addMbpsOption(s2, 'down_threshold_kbps', '触发阈值 (Mbps)',
			'下行速率持续达到该值开始累计时长。填 0 表示不检测。');

		s2.option(form.Value, 'down_sustain_minutes', '持续分钟',
			'须连续超阈达到该分钟数才触发（非突发）。')
			.datatype = 'uinteger';

		addMbpsOption(s2, 'limit_down_kbps', '限速值 (Mbps)',
			'触发后下发的 Bandix 下行限速。填 0 表示不限速该方向。');

		/* 模块四：上行策略 */
		const s3 = m.section(form.NamedSection, 'main', 'main', '上行策略');
		s3.addremove = false;
		s3.description = '填 0 表示不检测或不限速该方向。';

		addMbpsOption(s3, 'up_threshold_kbps', '触发阈值 (Mbps)',
			'上行速率持续达到该值开始累计时长。填 0 表示不检测。');

		s3.option(form.Value, 'up_sustain_minutes', '持续分钟',
			'须连续超阈达到该分钟数才触发（非突发）。')
			.datatype = 'uinteger';

		addMbpsOption(s3, 'limit_up_kbps', '限速值 (Mbps)',
			'触发后下发的 Bandix 上行限速。填 0 表示不限速该方向。');

		/* 模块五：MAC 白名单（NamedSection 伪选项，与限速列表同模式，避免 TypedSection 重复/丢失） */
		const s5 = m.section(form.NamedSection, 'main', 'main', 'MAC 白名单',
			'白名单设备不参与检测与限速。');
		s5.addremove = false;

		const oWl = s5.option(form.TextValue, '_mac_list', null,
			'首行注释说明格式；保存后写入 UCI 白名单。');
		oWl.rows = 20;
		oWl.cfgvalue = function() {
			return fetchBrLanMac().then(function(brLanMac) {
				return whitelistToText(brLanMac);
			});
		};
		oWl.write = function(section_id, formvalue) {
			const next = String(formvalue || '').replace(/\r\n/g, '\n');
			return fetchBrLanMac().then(function(brLanMac) {
				const cur = whitelistToText(brLanMac);
				if (cur === next || cur === next + '\n')
					return;
				applyWhitelistText(next);
			});
		};
		oWl.remove = function() {
			applyWhitelistText('');
		};

		/* 模块六：限速列表（实时，只读） */
		const s6 = m.section(form.NamedSection, 'main', 'main', '限速列表');
		s6.addremove = false;
		s6.description = '由本功能自动下发的 Bandix 限速。倒计时归零自动解除，也可手工解除。';

		const oList = s6.option(form.DummyValue, '_active_list', ' ');
		oList.render = function() {
			return E('div', {}, [
				E('div', { 'id': 'al-active-list' }),
				E('div', { 'class': 'al-meta', 'id': 'al-list-meta' })
			]);
		};

		this.map = m;
		return m.render().then(function(mapNode) {
			if (mapNode && mapNode.querySelectorAll) {
				const hs = mapNode.querySelectorAll('h2');
				for (let i = 0; i < hs.length; i++)
					hs[i].parentNode.removeChild(hs[i]);
				mountStatusInBasicTitle(mapNode);
				markWhitelistSection(mapNode);
			}
			setTimeout(function() { refresh(true); }, 50);
			poll.add(function() { return refresh(true); }, 5);
			return E('div', { 'class': 'al-page' }, mapNode);
		});
	},

	handleSave(ev) {
		return this.map.save();
	},

	handleSaveApply(ev, mode) {
		return this.handleSave(ev).then(function() {
			return ui.changes.apply(mode == '0');
		}).then(function() {
			return fs.exec('/etc/init.d/lede-autolimit', [ 'reload' ]).catch(function() { return null; });
		}).then(function() {
			return refresh(true);
		});
	}
});
