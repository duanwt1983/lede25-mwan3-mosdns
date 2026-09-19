'use strict';
'require view';
'require fs';
'require ui';
'require form';
'require uci';
'require poll';
'require dom';

function levelLook(lv) {
	if (lv === '严重') return { bg: '#c62828', fg: '#fff', row: '#fdecea' };
	if (lv === '中等') return { bg: '#ef6c00', fg: '#fff', row: '#fff4e5' };
	if (lv === '一般') return { bg: '#0277bd', fg: '#fff', row: '' };
	if (lv === '调试') return { bg: '#546e7a', fg: '#fff', row: '' };
	return { bg: '#607d8b', fg: '#fff', row: '' };
}

function levelBadge(lv) {
	const c = levelLook(lv);
	return E('span', {
		style: 'display:inline-block;min-width:2.6em;text-align:center;padding:.12em .5em;border-radius:4px;font-weight:700;font-size:12px;background:' + c.bg + ';color:' + c.fg
	}, lv || '');
}

function parseJson(stdout, fallback) {
	const t = (stdout || '').trim();
	if (!t)
		return fallback;
	try {
		return JSON.parse(t);
	} catch (e) {
		return fallback;
	}
}

function renderTable(rows, emptyHint) {
	const body = (rows || []).slice().reverse().map(r => {
		const look = levelLook(r.level);
		return E('tr', {
			'class': 'tr',
			'title': r.raw || '',
			'style': look.row ? ('background:' + look.row) : ''
		}, [
			E('td', { 'class': 'td', 'style': 'white-space:nowrap' }, r.time || ''),
			E('td', { 'class': 'td' }, levelBadge(r.level)),
			E('td', { 'class': 'td' }, r.cat || ''),
			E('td', { 'class': 'td' }, E('strong', {}, r.title || '')),
			E('td', { 'class': 'td' }, r.detail || '')
		]);
	});

	if (!body.length)
		body.push(E('tr', { 'class': 'tr' },
			E('td', { 'class': 'td', colspan: 5 }, emptyHint || _('暂无记录。'))));

	return E('table', { 'class': 'table cbi-section-table' }, [
		E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, _('时间')),
			E('th', { 'class': 'th' }, _('级别')),
			E('th', { 'class': 'th', 'title': _('分类：网络、设备、安全、系统') }, _('分类')),
			E('th', { 'class': 'th' }, _('发生了什么')),
			E('th', { 'class': 'th' }, _('说明'))
		]),
		...body
	]);
}

function sizeText(a) {
	if (!a || !a.path)
		return _('仅内存 / 未写文件');
	if (!a.exists)
		return _('尚无文件');
	return ((a.size / 1024).toFixed(1) + ' KB');
}

return view.extend({
	load() {
		return Promise.all([
			uci.load('lede-log').catch(() => null),
			uci.load('wanalert').catch(() => null),
			uci.load('system'),
			uci.load('mosdns').catch(() => null),
			fs.exec('/usr/libexec/lede-log-read', ['list']).then(r => parseJson(r && r.stdout, [])),
			fs.exec('/usr/libexec/lede-log-read', ['summary']).then(r => parseJson(r && r.stdout, {})),
			fs.exec('/usr/libexec/lede-log-read', ['read', 'syslog', '400', 'all']).then(r => parseJson(r && r.stdout, []))
		]);
	},

	render([_l, _w, _s, _m, apps, summary, syslogRows]) {
		const view = this;
		view._page = 'syslog';
		view._filter = 'all';
		view._syslogRows = syslogRows || [];
		view._alertRows = null;
		view._box = E('div', { 'class': 'cbi-section' });
		view._storeWrap = E('div');

		const catOf = { net: '网络', dhcp: 'DHCP', auth: '登录' };

		view._paint = function() {
			if (view._page === 'alert') {
				dom.content(view._box, renderTable(view._alertRows || [], _('这一类暂时没有记录。')));
				return;
			}
			let rows = view._syslogRows || [];
			const want = catOf[view._filter];
			if (want)
				rows = rows.filter(r => r.cat === want);
			dom.content(view._box, renderTable(rows, _('这一类暂时没有记录。')));
		};

		view._refresh = function() {
			if (view._page === 'alert') {
				return fs.exec('/usr/libexec/lede-log-read', ['read', 'alert', '400', 'alarm']).then(r => {
					view._alertRows = parseJson(r && r.stdout, []);
					view._paint();
				}).catch(e => {
					dom.content(view._box, E('p', {}, e.message || String(e)));
				});
			}
			return fs.exec('/usr/libexec/lede-log-read', ['read', 'syslog', '400', 'all']).then(r => {
				view._syslogRows = parseJson(r && r.stdout, []);
				view._paint();
			}).catch(e => {
				dom.content(view._box, E('p', {}, e.message || String(e)));
			});
		};

		const makeTab = (page, label, filt, active) => E('button', {
			type: 'button',
			'class': active ? 'btn cbi-button cbi-button-action' : 'btn cbi-button',
			click: function(ev) {
				if (ev) {
					ev.preventDefault();
					ev.stopPropagation();
				}
				view._page = page;
				view._filter = filt || (page === 'alert' ? 'alarm' : 'all');
				[...view._tabs.querySelectorAll('button')].forEach(b => b.classList.remove('cbi-button-action'));
				this.classList.add('cbi-button-action');
				if (page === 'alert' && !view._alertRows)
					return view._refresh();
				view._paint();
				return false;
			}
		}, label);

		view._tabs = E('div', {
			'class': 'lede-log-tabs',
			'style': 'display:flex;flex-wrap:wrap;gap:8px;margin:0 0 12px'
		}, [
			makeTab('syslog', _('全部'), 'all', true),
			makeTab('syslog', _('网络'), 'net', false),
			makeTab('syslog', _('DHCP'), 'dhcp', false),
			makeTab('syslog', _('登录'), 'auth', false),
			makeTab('alert', _('报警日志'), 'alarm', false)
		]);

		const headlines = [];
		(summary.alert || []).forEach(x => headlines.push(x));
		(summary.syslog || []).forEach(x => headlines.push(x));
		const statusBox = E('div', { 'class': 'alert-message notice', 'style': 'margin-bottom:1em' }, [
			E('strong', {}, _('当前状况')),
			E('ul', {}, (headlines.length ? headlines : [_('暂无值得单独列出的事件。')]).slice(0, 6).map(t => E('li', {}, t)))
		]);

		view._paint();

		const storageRows = (apps || []).map(a => E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td' }, a.title || a.id),
			E('td', { 'class': 'td' }, E('code', {}, a.path || _('（内存，不占磁盘）'))),
			E('td', { 'class': 'td' }, a.max_kb ? (a.max_kb + ' KB') : '—'),
			E('td', { 'class': 'td' }, sizeText(a)),
			E('td', { 'class': 'td' }, a.persist ? _('重启保留') : _('重启可能丢失'))
		]));

		const m = new form.Map('lede-log', _('存储设置'),
			_('设置各日志文件的磁盘路径和单段容量。写满后按时间戳归档；磁盘达到告警阈值时从最旧归档删除。'));
		view.map = m;

		let s = m.section(form.NamedSection, 'alert', 'store', _('报警日志'));
		s.addremove = false;
		s.description = _('网络、设备、安全、系统告警。默认文件名 sys-alert.log。');
		let o = s.option(form.Flag, 'enabled', _('写入文件'));
		o.default = o.enabled;
		o = s.option(form.Value, 'path', _('存储路径'),
			_('例如 /data/logs/sys-alert.log，或只填 /data/logs（自动写成 /data/logs/sys-alert.log）。中间目录会自动建。'));
		o.placeholder = _('绝对路径，文件或目录');
		o.rmempty = false;
		o = s.option(form.Value, 'max_kb', _('单文件上限（KB）'),
			_('超过则转存为 .old 后继续写新内容。上一次的 .old 会被覆盖。'));
		o.datatype = 'uinteger';
		o.placeholder = '512';

		s = m.section(form.NamedSection, 'syslog', 'store', _('系统日志 logd'));
		s.addremove = false;
		s.description = _('默认只在内存里转。落盘时务必改到外置盘。默认文件名 system.log。'));
		o = s.option(form.Flag, 'enabled', _('写到文件（不推荐放 overlay）'));
		o.default = o.disabled;
		o = s.option(form.Value, 'path', _('存储路径'),
			_('例如 /data/logs/system.log，或只填 /data/logs。目录会自动建。保存后需应用配置让 logd 重新加载。'));
		o.placeholder = '/mnt/sda1/logs/system.log';
		o.depends('enabled', '1');
		o.rmempty = false;
		o = s.option(form.Value, 'max_kb', _('单文件上限（KB）'),
			_('交给系统 logd：超过后轮转为 .old。同时影响内存缓冲大小。'));
		o.datatype = 'uinteger';
		o.placeholder = '256';
		o.depends('enabled', '1');
		o.rmempty = false;

		s = m.section(form.NamedSection, 'mosdns', 'store', _('MosDNS'));
		s.addremove = false;
		s.description = _('关掉则仍用 MosDNS 自己的 log_file。改路径后需要重启 MosDNS。');
		o = s.option(form.Flag, 'enabled', _('写到持久路径'));
		o.default = o.disabled;
		o = s.option(form.Value, 'path', _('存储路径'),
			_('例如 /data/logs/mosdns.log，或 /data/logs/mosdns（自动写成 /data/logs/mosdns/mosdns.log）。目录会自动建。'));
		o.placeholder = _('绝对路径，文件或目录');
		o.depends('enabled', '1');
		o.rmempty = false;
		o = s.option(form.Value, 'max_kb', _('单文件上限（KB）'),
			_('超过则转存为 .old 后清空当前文件继续写。上一次的 .old 会被覆盖。'));
		o.datatype = 'uinteger';
		o.placeholder = '256';
		o.depends('enabled', '1');
		o.rmempty = false;

		poll.add(L.bind(view._refresh, view), 25);

		return m.render().then(node => {
			dom.content(view._storeWrap, [
				E('h3', {}, _('当前占用')),
				E('table', { 'class': 'table' }, [
					E('tr', { 'class': 'tr table-titles' }, [
						E('th', { 'class': 'th' }, _('用途')),
						E('th', { 'class': 'th' }, _('路径')),
						E('th', { 'class': 'th' }, _('上限')),
						E('th', { 'class': 'th' }, _('已用')),
						E('th', { 'class': 'th' }, _('持久'))
					]),
					...storageRows
				]),
				E('hr'),
				node
			]);
			return E('div', {}, [
				E('h2', {}, _('日志中心')),
				statusBox,
				view._tabs,
				E('div', { 'style': 'margin:.5em 0 1em' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-action',
						'click': ui.createHandlerFn(view, view._refresh)
					}, _('刷新'))
				]),
				view._box,
				view._storeWrap
			]);
		});
	},

	handleSave(ev) {
		const saveLog = this.map ? this.map.save() : Promise.resolve();
		const prep = (kind, path) => fs.exec('/usr/libexec/lede-log-read', ['prep', kind, path || '']).then(r => {
			const j = parseJson(r && r.stdout, {});
			return (j && j.path) ? j.path : path;
		}).catch(() => path);

		return saveLog.then(() => {
			const enA = uci.get('lede-log', 'alert', 'enabled');
			const pathA = uci.get('lede-log', 'alert', 'path');
			const maxA = uci.get('lede-log', 'alert', 'max_kb');
			const enS = uci.get('lede-log', 'syslog', 'enabled');
			const pathS = uci.get('lede-log', 'syslog', 'path');
			const maxS = uci.get('lede-log', 'syslog', 'max_kb');
			const enM = uci.get('lede-log', 'mosdns', 'enabled');
			const pathMos = uci.get('lede-log', 'mosdns', 'path');

			const jobs = [];
			if (pathA)
				jobs.push(prep('alert', pathA));
			else
				jobs.push(Promise.resolve(''));
			if (enS === '1' && pathS)
				jobs.push(prep('syslog', pathS));
			else
				jobs.push(Promise.resolve(pathS || ''));
			if (enM === '1' && pathMos)
				jobs.push(prep('mosdns', pathMos));
			else
				jobs.push(Promise.resolve(pathMos || ''));

			return Promise.all(jobs).then(([pA, pS, pM]) => {
				uci.set('wanalert', 'main', 'log_enabled', (enA === '0') ? '0' : '1');
				if (pA) {
					uci.set('lede-log', 'alert', 'path', pA);
					uci.set('wanalert', 'main', 'log_path', pA);
				}
				if (maxA)
					uci.set('wanalert', 'main', 'log_max_kb', maxA);

				const sysSid = (uci.sections('system', 'system')[0] || {})['.name'];
				if (sysSid) {
					if (enS === '1' && pS) {
						uci.set('lede-log', 'syslog', 'path', pS);
						uci.set('system', sysSid, 'log_file', pS);
						uci.set('system', sysSid, 'log_size', maxS || '256');
					} else if (uci.get('system', sysSid, 'log_file') != null) {
						uci.unset('system', sysSid, 'log_file');
					}
				}

				if (uci.get('mosdns', 'config', 'configfile') != null || uci.get('mosdns', 'config', 'log_file') != null) {
					if (enM === '1' && pM) {
						uci.set('lede-log', 'mosdns', 'path', pM);
						uci.set('mosdns', 'config', 'log_file', pM);
					}
				}

				return uci.save();
			});
		});
	},

	handleSaveApply(ev, mode) {
		return this.handleSave(ev).then(() => ui.changes.apply(mode == '0'));
	}
});
