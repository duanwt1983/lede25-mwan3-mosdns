'use strict';
'require view';
'require form';
'require uci';
'require ui';
'require fs';
'require poll';
'require dom';
'require lede-theme-page as ledeTheme';

const LOG_PAGE_SIZES = [10, 20, 30, 50];

function upMacs(s) {
	return String(s || '').replace(/([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}/g, function(m) {
		return m.toUpperCase().replace(/-/g, ':');
	});
}

function fmtMac(s) {
	const t = String(s || '').trim().toUpperCase().replace(/-/g, ':');
	return /^([0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(t) ? t : String(s || '').trim().toUpperCase();
}

const RULE_MOVE = {
	dhcp_allow: 'dhcp_allow',
	nat_allow: 'nat_allow',
	ignore: 'nat_allow',
	nat_block: 'nat_block',
	dhcp_ban: 'dhcp_ban'
};

function copyHost(from, type) {
	const id = uci.add('lede-lansec', type);
	uci.set('lede-lansec', id, 'enabled', (from.enabled === '0') ? '0' : '1');
	if (from.mac)
		uci.set('lede-lansec', id, 'mac', fmtMac(from.mac));
	if (from.note)
		uci.set('lede-lansec', id, 'note', from.note);
	uci.remove('lede-lansec', from['.name']);
}

function migrateLegacyRules() {
	uci.sections('lede-lansec', 'rule').forEach(function(s) {
		const type = RULE_MOVE[s.action];
		if (!type)
			return;
		copyHost(s, type);
	});
	uci.sections('lede-lansec', 'ignore').forEach(function(s) {
		copyHost(s, 'nat_allow');
	});
}

function addHostTable(m, type, title, desc) {
	const s = m.section(form.TableSection, type, title, desc);
	s.anonymous = true;
	s.addremove = true;
	s.sortable = true;

	let o = s.option(form.Flag, 'enabled', _('启用'));
	o.default = o.enabled;
	o.rmempty = false;

	o = s.option(form.Value, 'mac', _('MAC'));
	o.datatype = 'macaddr';
	o.placeholder = 'AA:BB:CC:DD:EE:FF';
	o.rmempty = false;
	o.cfgvalue = function(section_id) {
		return fmtMac(uci.get('lede-lansec', section_id, 'mac'));
	};
	o.write = function(section_id, value) {
		uci.set('lede-lansec', section_id, 'mac', fmtMac(value));
	};

	o = s.option(form.Value, 'note', _('备注'));
	o.placeholder = _('可选');
	o.optional = true;
	return s;
}

function parsePending(raw) {
	if (raw && typeof raw === 'object' && !Array.isArray(raw) && raw.data != null)
		raw = raw.data;
	const text = String(raw || '').trim();
	if (!text)
		return [];
	try {
		const data = JSON.parse(text);
		if (Array.isArray(data))
			return data;
		if (data && Array.isArray(data.items))
			return data.items;
	} catch (e) {}
	return [];
}

function readPending() {
	return fs.read('/etc/lede-lansec-pending.json').then(function(r) {
		return parsePending(r);
	}).catch(function() {
		return fs.read('/tmp/lede-lansec-pending.json').then(parsePending).catch(function() { return []; });
	});
}

function listedMac(types, mac) {
	const want = fmtMac(mac);
	if (!want)
		return false;
	for (let t = 0; t < types.length; t++) {
		const secs = uci.sections('lede-lansec', types[t]) || [];
		for (let i = 0; i < secs.length; i++) {
			if (fmtMac(secs[i].mac) === want)
				return true;
		}
	}
	return false;
}

function pendingSettled(it) {
	if (!it || !it.mac)
		return false;
	if (it.kind === 'nat' || it.kind === 'share')
		return listedMac(['nat_allow', 'nat_block'], it.mac);
	return listedMac(['dhcp_allow', 'dhcp_ban'], it.mac);
}

function visiblePending(items) {
	return (items || []).filter(function(it) {
		return it && !pendingSettled(it);
	});
}

function kindLabel(kind) {
	if (kind === 'dhcp')
		return _('非法 DHCP');
	if (kind === 'nat')
		return _('二级路由');
	if (kind === 'share')
		return _('热点/共享');
	return kind || '—';
}

function parseJson(stdout) {
	const t = (stdout || '').trim();
	if (!t)
		return [];
	try {
		const data = JSON.parse(t);
		if (Array.isArray(data))
			return data;
		if (data && Array.isArray(data.rows))
			return data.rows;
	} catch (e) {}
	return [];
}

function newestFirst(rows, key) {
	const field = key || 'time';
	return (rows || []).slice().sort(function(a, b) {
		const av = a && (a[field] || a.t || a.when || '');
		const bv = b && (b[field] || b.t || b.when || '');
		return String(bv).localeCompare(String(av));
	});
}

function clampPageSize(v) {
	const n = parseInt(v, 10);
	if (LOG_PAGE_SIZES.indexOf(n) >= 0)
		return n;
	return 20;
}

function isLansecRow(r) {
	const blob = [r.cat, r.title, r.detail].join(' ');
	return /ARP|DHCP|网关|二级|小路由|非法|欺骗|地址冲突|发地址|NAT|共享|热点|冒充/.test(blob);
}

function levelLook(lv) {
	if (lv === '严重')
		return { bg: '#c62828', fg: '#fff', row: '#fdecea' };
	if (lv === '中等')
		return { bg: '#ef6c00', fg: '#fff', row: '#fff4e5' };
	if (lv === '一般')
		return { bg: '#0277bd', fg: '#fff', row: '' };
	return { bg: '#607d8b', fg: '#fff', row: '' };
}

function levelBadge(lv) {
	const c = levelLook(lv);
	return E('span', {
		style: 'display:inline-block;min-width:2.6em;text-align:center;padding:.12em .5em;border-radius:4px;font-weight:700;font-size:12px;background:' + c.bg + ';color:' + c.fg
	}, lv || '');
}

function renderLogTable(rows, emptyHint) {
	const body = [];
	const list = rows || [];
	for (let i = 0; i < list.length; i++) {
		const r = list[i];
		const look = levelLook(r.level);
		body.push(E('tr', {
			'class': 'tr',
			'title': r.raw || '',
			'style': look.row ? ('background:' + look.row) : ''
		}, [
			E('td', { 'class': 'td' }, r.time || ''),
			E('td', { 'class': 'td' }, levelBadge(r.level)),
			E('td', { 'class': 'td' }, r.cat || ''),
			E('td', { 'class': 'td' }, E('strong', {}, upMacs(r.title || ''))),
			E('td', { 'class': 'td' }, upMacs(r.detail || ''))
		]));
	}
	if (!body.length) {
		body.push(E('tr', { 'class': 'tr' },
			E('td', { 'class': 'td', colspan: 5 }, emptyHint || _('暂无记录。'))));
	}
	return E('div', { 'style': 'overflow-x:auto' }, [
		E('table', { 'class': 'table cbi-section-table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('时间')),
				E('th', { 'class': 'th' }, _('级别')),
				E('th', { 'class': 'th' }, _('分类')),
				E('th', { 'class': 'th' }, _('事件')),
				E('th', { 'class': 'th' }, _('说明'))
			])
		].concat(body))
	]);
}

function renderPager(page, pages, total, pageSize, onPage, onSize) {
	const sizeSel = E('select', { 'style': 'min-width:4.5em' });
	LOG_PAGE_SIZES.forEach(function(n) {
		sizeSel.appendChild(E('option', { value: String(n), selected: n === pageSize }, String(n)));
	});
	sizeSel.addEventListener('change', function() {
		onSize(clampPageSize(this.value));
	});
	const prev = E('button', { type: 'button', 'class': 'btn cbi-button', disabled: page <= 1 }, _('上一页'));
	const next = E('button', { type: 'button', 'class': 'btn cbi-button', disabled: page >= pages }, _('下一页'));
	prev.addEventListener('click', function() {
		if (page > 1)
			onPage(page - 1);
	});
	next.addEventListener('click', function() {
		if (page < pages)
			onPage(page + 1);
	});
	return E('div', {
		'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:10px;margin:.5rem 0'
	}, [
		E('span', {}, _('共 %d 条').format(total)),
		prev,
		E('span', {}, _('第 %d / %d 页').format(page, pages)),
		next,
		E('span', {}, _('每页')),
		sizeSel,
		E('span', {}, _('条'))
	]);
}

function pendingKey(it) {
	if (!it || !it.mac)
		return '';
	return (it.kind || 'dhcp') + '|' + fmtMac(it.mac);
}

function selectedPending(view) {
	const key = view._selKey || '';
	if (!key)
		return null;
	const list = view._pending || [];
	for (let i = 0; i < list.length; i++) {
		if (pendingKey(list[i]) === key)
			return list[i];
	}
	return null;
}

function runPendingAction(view, action) {
	const it = selectedPending(view);
	if (!it)
		return Promise.resolve();
	const key = pendingKey(it);
	return fs.exec('/usr/libexec/lede-lansec', ['decide', action, it.kind || 'dhcp', it.mac || '']).then(function() {
		view._pending = (view._pending || []).filter(function(x) {
			return pendingKey(x) !== key;
		});
		view._selKey = '';
		view._logSig = '';
		if (view._paintLog)
			view._paintLog();
		return uci.load('lede-lansec');
	}).then(function() {
		return view.refreshLogs();
	}).catch(function(e) {
		ui.addNotification(null, E('p', {}, e.message || String(e)), 'warning');
	});
}

function renderPendingBar(view) {
	const it = selectedPending(view);
	const nat = it && (it.kind === 'nat' || it.kind === 'share');
	const allowAct = nat ? 'nat_allow' : 'dhcp_allow';
	const denyAct = nat ? 'nat_block' : 'dhcp_ban';
	const denyLabel = nat ? _('禁止转发') : _('封禁该 MAC');
	const allowBtn = E('button', {
		type: 'button',
		'class': 'btn cbi-button cbi-button-action'
	}, _('加入白名单'));
	const denyBtn = E('button', {
		type: 'button',
		'class': 'btn cbi-button cbi-button-negative'
	}, denyLabel);
	allowBtn.disabled = !it;
	denyBtn.disabled = !it || it.kind === 'share';
	allowBtn.addEventListener('click', function() {
		if (it)
			runPendingAction(view, allowAct);
	});
	denyBtn.addEventListener('click', function() {
		if (it && it.kind !== 'share')
			runPendingAction(view, denyAct);
	});
	return E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:8px;margin:.4rem 0 .8rem' }, [
		allowBtn,
		denyBtn,
		E('span', { 'style': 'color:#666' },
			it ? _('已选 %s').format(fmtMac(it.mac)) : _('先点选一行，再选择去向'))
	]);
}

function renderPending(items, view) {
	const rows = [];
	const sel = view._selKey || '';
	newestFirst(items || [], 'when').forEach(function(it) {
		if (!it)
			return;
		const key = pendingKey(it);
		const on = key !== '' && key === sel;
		const tr = E('tr', {
			'class': 'tr',
			'data-key': key,
			'style': 'cursor:pointer;' + (on ? 'background:#e3f2fd' : '')
		}, [
			E('td', { 'class': 'td' }, it.when || it.t || '—'),
			E('td', { 'class': 'td' }, kindLabel(it.kind)),
			E('td', { 'class': 'td' }, fmtMac(it.mac) || '—'),
			E('td', { 'class': 'td' }, it.ip || '—'),
			E('td', { 'class': 'td' }, it.detail || it.note || '—')
		]);
		tr.addEventListener('click', function() {
			view._selKey = (view._selKey === key) ? '' : key;
			view._paintLog();
		});
		rows.push(tr);
	});
	if (!rows.length) {
		rows.push(E('tr', { 'class': 'tr' },
			E('td', { 'class': 'td', colspan: 5 },
				_('目前没有待处理的设备。'))));
	}
	return E('div', {}, [
		renderPendingBar(view),
		E('div', { 'style': 'overflow-x:auto' }, [
			E('table', { 'class': 'table cbi-section-table' }, [
				E('tr', { 'class': 'tr table-titles' }, [
					E('th', { 'class': 'th' }, _('时间')),
					E('th', { 'class': 'th' }, _('类型')),
					E('th', { 'class': 'th' }, _('MAC')),
					E('th', { 'class': 'th' }, _('IP')),
					E('th', { 'class': 'th' }, _('说明'))
				])
			].concat(rows))
		])
	]);
}

function makeTabBar(items, current, onPick) {
	const bar = E('div', {
		'class': 'lede-log-tabs',
		'style': 'display:flex;flex-wrap:wrap;gap:8px;margin:0 0 14px'
	});
	items.forEach(function(it) {
		const btn = E('button', {
			'type': 'button',
			'class': 'btn cbi-button' + (it.id === current ? ' cbi-button-action' : ''),
			'data-tab': it.id
		}, it.title);
		btn.addEventListener('click', function() {
			onPick(it.id);
		});
		bar.appendChild(btn);
	});
	return bar;
}

return view.extend({
	load() {
		return Promise.all([
			uci.load('lede-lansec'),
			readPending(),
			fs.exec('/usr/libexec/lede-log-read', ['read', 'alert', '300', 'alarm']).then(function(r) {
				return parseJson(r && r.stdout).filter(isLansecRow);
			}).catch(function() { return []; })
		]);
	},

	render(data) {
		const pending = visiblePending((data && data[1]) || []);
		const logs = (data && data[2]) || [];

		if (!uci.get('lede-lansec', 'main'))
			uci.add('lede-lansec', 'main', 'main');
		migrateLegacyRules();

		const mPolicy = new form.Map('lede-lansec');
		mPolicy.title = null;

		let s = mPolicy.section(form.NamedSection, 'main', 'main', _('总开关'));
		s.addremove = false;
		s.description = _('控制是否启用本页全部防护，以及作用在哪一个局域网网桥上。');

		let o = s.option(form.Flag, 'enabled', _('启用局域网安全'));
		o.default = o.disabled;
		o.rmempty = false;
		o.description = _('开启后，按下面三项策略保护局域网；关闭则全部不生效。');

		o = s.option(form.Value, 'iface', _('监听网桥'),
			_('需要保护的局域网网桥，通常是 br-lan。'));
		o.default = 'br-lan';
		o.rmempty = false;

		o = s.option(form.Value, 'notify_cooldown', _('同一事件推送冷却（秒）'),
			_('同类事件两次推送的最短间隔，避免重复刷屏。消息发到已启用的钉钉或 PushPlus。'));
		o.datatype = 'uinteger';
		o.default = '120';

		o = s.option(form.ListValue, 'log_page_size', _('日志每页条数'));
		o.value('10', '10');
		o.value('20', '20');
		o.value('30', '30');
		o.value('50', '50');
		o.default = '20';
		o.rmempty = false;
		o.description = _('日志页按时间倒序显示，有新记录会自动出现。');

		s = mPolicy.section(form.NamedSection, 'main', 'main', _('非法 DHCP 服务器'));
		s.addremove = false;
		s.description = _('防止局域网里出现未经允许的 DHCP 服务器，避免终端被分配错误地址、网关或 DNS。');

		o = s.option(form.Flag, 'dhcp_enabled', _('检测非法 DHCP'));
		o.default = o.enabled;
		o.rmempty = false;
		o.description = _('发现非白名单设备对外分配地址时触发。');
		o = s.option(form.Flag, 'dhcp_log', _('写入报警日志'));
		o.default = o.enabled;
		o.rmempty = false;
		o.depends('dhcp_enabled', '1');
		o = s.option(form.Flag, 'dhcp_notify', _('发送报警消息'));
		o.default = o.enabled;
		o.rmempty = false;
		o.depends('dhcp_enabled', '1');
		o = s.option(form.Flag, 'dhcp_ban', _('自动封禁该 MAC'));
		o.default = o.enabled;
		o.rmempty = false;
		o.depends('dhcp_enabled', '1');
		o.description = _('写入禁止列表后切断该 MAC：不能再发地址，也不能经本机上网或访问本机。白名单除外。交换机上两台终端互访拦不住。');

		s = mPolicy.section(form.NamedSection, 'main', 'main', _('二级路由 / 私接小路由'));
		s.addremove = false;
		s.description = _('用来处理把其它设备藏在自己后面上网的情况。默认只记录，是否禁止由其名单决定。');

		o = s.option(form.Flag, 'nat_enabled', _('启用二级路由名单'));
		o.default = o.enabled;
		o.rmempty = false;
		o.description = _('白名单不处理，禁止名单切断其代理上网。自动发现只认它是否在本网发地址，不按名称或生存时间猜测。');
		o = s.option(form.Flag, 'nat_log', _('写入报警日志'));
		o.default = o.enabled;
		o.rmempty = false;
		o.depends('nat_enabled', '1');
		o = s.option(form.Flag, 'nat_notify', _('发送报警消息'));
		o.default = o.disabled;
		o.rmempty = false;
		o.depends('nat_enabled', '1');

		s = mPolicy.section(form.NamedSection, 'main', 'main', _('ARP 欺骗'));
		s.addremove = false;
		s.description = _('防止有人冒充网关或抢占他人 IP，避免流量被劫持。');

		o = s.option(form.Flag, 'arp_enabled', _('检测 ARP 异常'));
		o.default = o.enabled;
		o.rmempty = false;
		o.description = _('核对本网 IP 与 MAC 是否被篡改或冲突。');
		o = s.option(form.Flag, 'arp_log', _('写入报警日志'));
		o.default = o.enabled;
		o.rmempty = false;
		o.depends('arp_enabled', '1');
		o = s.option(form.Flag, 'arp_notify', _('发送报警消息'));
		o.default = o.enabled;
		o.rmempty = false;
		o.depends('arp_enabled', '1');
		o = s.option(form.Flag, 'arp_drop_gw', _('丢弃假网关 ARP'));
		o.default = o.enabled;
		o.rmempty = false;
		o.depends('arp_enabled', '1');
		o.description = _('拦截冒充本网关地址的应答，终端仍指向真正的网关。');
		o = s.option(form.Flag, 'arp_bind_gw', _('绑定本机网关 ARP'));
		o.default = o.enabled;
		o.rmempty = false;
		o.depends('arp_enabled', '1');
		o.description = _('把网关地址固定到本机网卡，避免邻居表被改写。');
		o = s.option(form.Flag, 'arp_enforce_lease', _('按 DHCP 租约核对 ARP（严格）'));
		o.default = o.disabled;
		o.rmempty = false;
		o.depends('arp_enabled', '1');
		o.description = _('只允许租约中的 IP 与 MAC 配对。静态地址或双网卡环境请谨慎开启。');

		const mAllow = new form.Map('lede-lansec');
		mAllow.title = null;
		addHostTable(mAllow, 'dhcp_allow', _('非法 DHCP · 服务器白名单'),
			_('允许在本网分配地址的 DHCP 服务器。本机网关无需填写。同一 MAC 不能同时出现在禁止列表。'));
		addHostTable(mAllow, 'nat_allow', _('二级路由 / 热点 / 共享 · 白名单'),
			_('允许存在的旁路、AP、小路由、手机热点或系统共享，不按威胁处理。同一 MAC 不能同时出现在禁止列表。'));

		const mDeny = new form.Map('lede-lansec');
		mDeny.title = null;
		addHostTable(mDeny, 'dhcp_ban', _('非法DHCP服务器'),
			_('封禁这些 MAC：不能再发地址，也不能经本机上网或访问本机。同一 MAC 不能同时出现在白名单。'));
		addHostTable(mDeny, 'nat_block', _('二级路由'),
			_('禁止这些设备为后面的终端代理上网。同一 MAC 不能同时出现在白名单。'));

		this.maps = [mPolicy, mAllow, mDeny];
		const view = this;
		view._tab = 'policy';
		view._pending = pending;
		view._logs = logs;
		view._logPage = 1;
		view._logPageSize = clampPageSize(uci.get('lede-lansec', 'main', 'log_page_size') || 20);

		return Promise.all([mPolicy.render(), mAllow.render(), mDeny.render()]).then(function(nodes) {
			nodes.forEach(function(n) { ledeTheme.enhanceMapNode(n); });
			view._panes = {
				policy: nodes[0],
				allow: nodes[1],
				deny: nodes[2],
				log: E('div', { 'class': 'cbi-map lede-themed-page' })
			};

			const logBox = E('div');
			view._logBox = logBox;
			view._paintLog = function() {
				if (view._selKey && !selectedPending(view))
					view._selKey = '';
				const all = newestFirst(view._logs || [], 'time');
				const total = all.length;
				const size = clampPageSize(view._logPageSize);
				const pages = Math.max(1, Math.ceil(total / size) || 1);
				if (view._logPage > pages)
					view._logPage = pages;
				if (view._logPage < 1)
					view._logPage = 1;
				const start = (view._logPage - 1) * size;
				const pageRows = all.slice(start, start + size);
				dom.content(logBox, [
					E('h3', {}, _('待确认')),
					E('p', { 'class': 'cbi-section-descr' },
						_('已发现、尚未决定留用或禁止的设备。点选一行后，用上面的按钮决定去向。')),
					renderPending(view._pending, view),
					E('h3', { 'style': 'margin-top:1.2rem' }, _('相关日志')),
					E('p', { 'class': 'cbi-section-descr' },
						_('非法 DHCP、二级路由和 ARP 欺骗相关的事件记录。最新的在最上面，有新记录会自动出现。')),
					renderPager(view._logPage, pages, total, size, function(p) {
						view._logPage = p;
						view._paintLog();
					}, function(n) {
						view._logPageSize = n;
						view._logPage = 1;
						uci.set('lede-lansec', 'main', 'log_page_size', String(n));
						view._paintLog();
					}),
					renderLogTable(pageRows, _('还没有相关记录。'))
				]);
			};
			view._paintLog();
			view._panes.log.appendChild(logBox);

			const host = E('div', { 'class': 'lede-themed-page' });
			view._host = host;
			view._tabBar = makeTabBar([
				{ id: 'policy', title: _('策略') },
				{ id: 'allow', title: _('白名单') },
				{ id: 'deny', title: _('禁止列表') },
				{ id: 'log', title: _('日志') }
			], view._tab, function(id) { view.showTab(id); });

			host.appendChild(E('h2', {}, _('局域网安全')));
			host.appendChild(E('p', { 'class': 'cbi-map-descr' },
				_('用来防止局域网里的非法 DHCP、私接小路由和 ARP 欺骗，让终端拿到正确的地址并走正确的网关。')));
			host.appendChild(view._tabBar);
			['policy', 'allow', 'deny', 'log'].forEach(function(id) {
				const pane = view._panes[id];
				pane.setAttribute('data-lansec-pane', id);
				pane.style.display = (id === view._tab) ? '' : 'none';
				host.appendChild(pane);
			});
			ledeTheme.injectBase();
			if (!view._logPoll) {
				view._logPoll = true;
				poll.add(function() {
					if (view._tab !== 'log')
						return Promise.resolve();
					return view.refreshLogs();
				}, 8);
			}
			return host;
		});
	},

	showTab(id) {
		this._tab = id;
		const bar = this._tabBar;
		if (bar) {
			bar.querySelectorAll('button[data-tab]').forEach(function(btn) {
				btn.classList.toggle('cbi-button-action', btn.getAttribute('data-tab') === id);
			});
		}
		const panes = this._panes || {};
		Object.keys(panes).forEach(function(k) {
			panes[k].style.display = (k === id) ? '' : 'none';
		});
		if (id === 'log')
			this.refreshLogs();
	},

	refreshLogs() {
		const view = this;
		return Promise.all([
			readPending(),
			fs.exec('/usr/libexec/lede-log-read', ['read', 'alert', '300', 'alarm']).then(function(r) {
				return parseJson(r && r.stdout).filter(isLansecRow);
			}).catch(function() { return []; })
		]).then(function(res) {
			const nextPending = visiblePending(res[0] || []);
			const nextLogs = res[1] || [];
			const sig = JSON.stringify(nextPending) + '\n' + JSON.stringify(nextLogs);
			if (sig === view._logSig)
				return;
			view._logSig = sig;
			view._pending = nextPending;
			view._logs = nextLogs;
			if (view._paintLog)
				view._paintLog();
		}).catch(function() {});
	},

	handleSave() {
		const maps = this.maps || [];
		let chain = Promise.resolve();
		maps.forEach(function(m) {
			chain = chain.then(function() { return m.save(); });
		});
		return chain.then(function() {
			return uci.save();
		}).then(function() {
			return fs.exec('/usr/libexec/lede-lansec', ['prune']).catch(function() {});
		}).then(function() {
			if (ui.changes && typeof ui.changes.init === 'function')
				return ui.changes.init();
		});
	},

	handleSaveApply(ev, mode) {
		const self = this;
		return this.handleSave(ev).then(function() {
			return fs.exec('/etc/init.d/lede-lansec', ['reload']).catch(function() {
				return fs.exec('/usr/libexec/lede-lansec', ['apply']);
			});
		}).then(function() {
			return ui.changes.apply(mode == '0');
		});
	}
});
