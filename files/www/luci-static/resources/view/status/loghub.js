'use strict';
'require view';
'require fs';
'require ui';
'require form';
'require uci';
'require poll';
'require dom';

function levelLook(lv) {
	if (lv === '严重')
		return { bg: '#c62828', fg: '#fff', row: '#fdecea' };
	if (lv === '中等')
		return { bg: '#ef6c00', fg: '#fff', row: '#fff4e5' };
	if (lv === '一般')
		return { bg: '#0277bd', fg: '#fff', row: '' };
	if (lv === '调试')
		return { bg: '#546e7a', fg: '#fff', row: '' };
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

function colStyle(kind) {
	const base = 'box-sizing:border-box;vertical-align:top;overflow:hidden;';
	if (kind === 'time')
		return base + 'width:15%;white-space:nowrap;text-overflow:ellipsis;';
	if (kind === 'level')
		return base + 'width:8%;white-space:nowrap;';
	if (kind === 'cat')
		return base + 'width:8%;white-space:nowrap;';
	if (kind === 'title')
		return base + 'width:16%;word-break:break-word;white-space:normal;';
	return base + 'width:53%;word-break:break-word;overflow-wrap:anywhere;white-space:normal;';
}

function renderTable(rows, emptyHint) {
	const body = [];
	const list = (rows || []).slice().reverse();
	for (let i = 0; i < list.length; i++) {
		const r = list[i];
		const look = levelLook(r.level);
		body.push(E('tr', {
			'class': 'tr',
			'title': r.raw || '',
			'style': look.row ? ('background:' + look.row) : ''
		}, [
			E('td', { 'class': 'td', 'style': colStyle('time') }, r.time || ''),
			E('td', { 'class': 'td', 'style': colStyle('level') }, levelBadge(r.level)),
			E('td', { 'class': 'td', 'style': colStyle('cat') }, r.cat || ''),
			E('td', { 'class': 'td', 'style': colStyle('title') }, E('strong', {}, r.title || '')),
			E('td', { 'class': 'td', 'style': colStyle('detail') }, r.detail || '')
		]));
	}

	if (!body.length)
		body.push(E('tr', { 'class': 'tr' },
			E('td', { 'class': 'td', colspan: 5 }, emptyHint || _('暂无记录。'))));

	const head = E('tr', { 'class': 'tr table-titles' }, [
		E('th', { 'class': 'th', 'style': colStyle('time') }, _('时间')),
		E('th', { 'class': 'th', 'style': colStyle('level') }, _('级别')),
		E('th', { 'class': 'th', 'style': colStyle('cat') }, _('分类')),
		E('th', { 'class': 'th', 'style': colStyle('title') }, _('事件')),
		E('th', { 'class': 'th', 'style': colStyle('detail') }, _('说明'))
	]);
	return E('div', { 'style': 'overflow-x:auto' }, [
		E('table', {
			'class': 'table cbi-section-table',
			'style': 'table-layout:fixed;width:100%'
		}, [head].concat(body))
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
		return uci.load('lede-log').catch(function() { return null; });
	},

	render() {
		const view = this;
		view._page = 'syslog';
		view._cat = 'all';
		view._level = 'all';
		view._pg = 1;
		view._more = false;
		view._rows = [];

		function clampPs(n) {
			n = +n || 20;
			if (n < 10)
				n = 10;
			if (n > 100)
				n = 100;
			return n;
		}

		view._psOpt = function(tab) {
			if (tab === 'kernel')
				return 'page_size_kernel';
			if (tab === 'alert')
				return 'page_size_alert';
			return 'page_size_syslog';
		};

		view._lsKey = function(tab) {
			return 'lede-log-' + view._psOpt(tab);
		};

		view._readPs = function(tab) {
			try {
				const ls = localStorage.getItem(view._lsKey(tab));
				if (ls)
					return clampPs(ls);
			} catch (e) {}
			const spec = uci.get('lede-log', 'ui', view._psOpt(tab));
			const legacy = uci.get('lede-log', 'ui', 'page_size');
			return clampPs(spec || legacy || 20);
		};

		view._syncSizeSel = function() {
			view._ps = view._readPs(view._page);
			view._sizeSel.value = String(view._ps);
		};

		view._ps = view._readPs('syslog');
		view._box = E('div', { 'class': 'cbi-section' });
		view._storeWrap = E('div');
		view._catSel = E('select', { 'style': 'min-width:8em' });
		view._levelSel = E('select', { 'style': 'min-width:7em' });
		view._sizeSel = E('select', { 'style': 'min-width:5em' });
		view._pageLbl = E('span', { 'class': 'lede-log-pginfo' }, '');
		view._navBox = E('span', { 'class': 'lede-log-nav' });
		view._pages = 1;
		view._more = false;
		view._levelWrap = E('span', { 'style': 'display:none;margin-left:4px' }, [
			E('span', { 'style': 'margin-right:.4em' }, _('级别')),
			view._levelSel
		]);

		const catsSys = ['网络', 'DHCP', '登录', '内核', '服务', '无线', 'DNS', '文件共享', '代理', '其它'];
		const catsAlert = ['线路', '资源', 'DHCP', '系统', '硬件', '内核', '网络', '登录', '客户端', '服务', 'DNS', '告警'];
		const levels = ['严重', '中等', '一般', '信息'];

		function fillSelect(sel, values, current) {
			while (sel.firstChild)
				sel.removeChild(sel.firstChild);
			sel.appendChild(E('option', { value: 'all' }, _('全部')));
			for (let i = 0; i < values.length; i++)
				sel.appendChild(E('option', { value: values[i] }, values[i]));
			let keep = 'all';
			for (let i = 0; i < values.length; i++) {
				if (values[i] === current)
					keep = current;
			}
			sel.value = keep;
			return keep;
		}

		view._syncFilters = function() {
			const cats = view._page === 'alert' ? catsAlert : catsSys;
			view._cat = fillSelect(view._catSel, cats, view._cat);
			if (view._page === 'alert') {
				view._levelWrap.style.display = 'inline';
				view._level = fillSelect(view._levelSel, levels, view._level);
			} else {
				view._levelWrap.style.display = 'none';
				view._level = 'all';
			}
		};

		view._goPage = function(n) {
			n = +n || 1;
			if (n < 1)
				n = 1;
			if (view._pages && n > view._pages)
				n = view._pages;
			if (n === view._pg)
				return;
			view._pg = n;
			view._refresh();
		};

		view._pageNums = function(cur, pages) {
			const out = [];
			if (pages <= 1)
				return out;
			const mark = {};
			function add(p) {
				if (p >= 1 && p <= pages && !mark[p]) {
					mark[p] = true;
					out.push(p);
				}
			}
			add(1);
			add(pages);
			for (let i = cur - 2; i <= cur + 2; i++)
				add(i);
			out.sort(function(a, b) { return a - b; });
			const withGap = [];
			for (let i = 0; i < out.length; i++) {
				if (i && out[i] - out[i - 1] > 1)
					withGap.push(0);
				withGap.push(out[i]);
			}
			return withGap;
		};

		view._paintPager = function() {
			const pages = view._pages || 1;
			const cur = view._pg || 1;
			view._pageLbl.textContent = _('第 %s / 共 %s 页').format(String(cur), String(pages));
			dom.content(view._navBox, []);
			if (pages <= 1)
				return;
			if (pages <= 5) {
				const prev = E('button', { type: 'button', 'class': 'btn cbi-button' }, _('上一页'));
				const next = E('button', { type: 'button', 'class': 'btn cbi-button' }, _('下一页'));
				prev.disabled = cur <= 1;
				next.disabled = cur >= pages;
				prev.addEventListener('click', function() { view._goPage(cur - 1); });
				next.addEventListener('click', function() { view._goPage(cur + 1); });
				view._navBox.appendChild(prev);
				view._navBox.appendChild(next);
				return;
			}
			view._pageNums(cur, pages).forEach(function(p) {
				if (!p) {
					view._navBox.appendChild(E('span', { 'class': 'lede-log-ellipsis' }, '…'));
					return;
				}
				const b = E('button', {
					type: 'button',
					'class': 'btn cbi-button' + (p === cur ? ' cbi-button-action' : '')
				}, String(p));
				if (p === cur)
					b.disabled = true;
				else
					b.addEventListener('click', function() { view._goPage(p); });
				view._navBox.appendChild(b);
			});
		};

		view._paint = function() {
			view._syncFilters();
			view._paintPager();
			dom.content(view._box, renderTable(view._rows, _('这一类暂时没有记录。')));
		};

		view._filtArg = function() {
			if (view._page === 'alert') {
				if (view._level !== 'all')
					return view._level;
				if (view._cat !== 'all')
					return view._cat;
				return 'alarm';
			}
			if (view._cat !== 'all')
				return view._cat;
			return 'all';
		};

		view._refresh = function() {
			if (view._page === 'config')
				return Promise.resolve();
			const page = view._page;
			const pg = view._pg;
			dom.content(view._box, E('p', {}, _('正在读取…')));
			let id = 'syslog';
			if (page === 'kernel')
				id = 'kernel';
			else if (page === 'alert')
				id = 'alert';
			const filt = view._filtArg();
			return fs.exec('/usr/libexec/lede-log-read', [
				'read', id, String(view._ps), filt, String(pg)
			]).then(function(r) {
				const j = parseJson(r && r.stdout, {});
				let rows = [];
				let more = false;
				if (j && j.rows)
					rows = j.rows;
				else if (j && j.length)
					rows = j;
				if (j && j.more)
					more = true;
				if (view._page === page && view._pg === pg) {
					view._rows = rows;
					view._more = more;
					view._pages = Math.max(1, +(j && j.pages) || (more ? pg + 1 : pg) || 1);
					if (j && j.page && +j.page !== pg)
						view._pg = +j.page;
					view._paint();
				}
			}).catch(function(e) {
				if (view._page === page)
					dom.content(view._box, E('p', {}, e.message || String(e)));
			});
		};

		view._applyPane = function() {
			const cfg = view._page === 'config';
			stickyBar.style.display = cfg ? 'none' : 'flex';
			view._box.style.display = cfg ? 'none' : '';
			view._storeWrap.style.display = cfg ? '' : 'none';
		};

		const makeTab = function(page, label, active) {
			return E('button', {
				type: 'button',
				'class': active ? 'btn cbi-button cbi-button-action' : 'btn cbi-button',
				click: function(ev) {
					if (ev) {
						ev.preventDefault();
						ev.stopPropagation();
					}
					view._page = page;
					view._cat = 'all';
					view._level = 'all';
					view._pg = 1;
					if (page !== 'config')
						view._syncSizeSel();
					const buttons = view._tabs.getElementsByTagName('button');
					for (let i = 0; i < buttons.length; i++)
						buttons[i].classList.remove('cbi-button-action');
					this.classList.add('cbi-button-action');
					view._applyPane();
					if (page === 'config')
						return false;
					return view._refresh();
				}
			}, label);
		};

		view._tabs = E('div', {
			'class': 'lede-log-tabs',
			'style': 'display:flex;flex-wrap:wrap;gap:8px;margin:0 0 12px'
		}, [
			makeTab('syslog', _('系统日志'), true),
			makeTab('kernel', _('内核日志'), false),
			makeTab('alert', _('报警日志'), false),
			makeTab('config', _('配置'), false)
		]);

		const sizes = [20, 30, 50, 100];
		for (let i = 0; i < sizes.length; i++) {
			const opt = E('option', { value: String(sizes[i]) }, String(sizes[i]));
			if (sizes[i] === view._ps)
				opt.selected = true;
			view._sizeSel.appendChild(opt);
		}

		view._catSel.addEventListener('change', function() {
			view._cat = this.value || 'all';
			view._pg = 1;
			view._refresh();
		});
		view._levelSel.addEventListener('change', function() {
			view._level = this.value || 'all';
			view._pg = 1;
			view._refresh();
		});
		view._sizeSel.addEventListener('change', function() {
			view._ps = clampPs(this.value);
			view._pg = 1;
			try { localStorage.setItem(view._lsKey(view._page), String(view._ps)); } catch (e) {}
			view._refresh();
		});

		const filterBar = E('div', { 'class': 'lede-log-filters' }, [
			E('span', {}, _('分类')),
			view._catSel,
			view._levelWrap,
			E('button', {
				'class': 'btn cbi-button cbi-button-action',
				'click': ui.createHandlerFn(view, function() { view._pg = 1; return view._refresh(); })
			}, _('刷新'))
		]);
		const pagerBar = E('div', { 'class': 'lede-log-pager' }, [
			view._pageLbl,
			E('span', { 'class': 'lede-log-ps' }, [
				E('span', {}, _('每页')),
				view._sizeSel,
				E('span', {}, _('条'))
			]),
			view._navBox
		]);
		const stickyBar = E('div', { 'class': 'lede-log-sticky' }, [filterBar, pagerBar]);

		const m = new form.Map('lede-log', _('存储设置'),
			_('设置各日志文件的磁盘路径和单段容量。写满后按时间戳归档；磁盘达到告警阈值时从最旧归档删除。'));
		view.map = m;

		let s = m.section(form.NamedSection, 'alert', 'store', _('报警日志'));
		s.addremove = false;
		s.description = _('线路和资源告警。');
		let o = s.option(form.Flag, 'enabled', _('写入文件'));
		o.default = o.enabled;
		o = s.option(form.Value, 'path', _('存储路径'));
		o.placeholder = _('绝对路径，文件或目录');
		o.rmempty = false;
		o = s.option(form.Value, 'max_kb', _('单段大小 KB'));
		o.datatype = 'uinteger';
		o.placeholder = '2048';

		s = m.section(form.NamedSection, 'syslog', 'store', _('系统日志'));
		s.addremove = false;
		s.description = _('从内存 logd 定时写入磁盘。');
		o = s.option(form.Flag, 'enabled', _('写入磁盘'));
		o.default = o.enabled;
		o = s.option(form.Value, 'path', _('存储路径'));
		o.placeholder = _('绝对路径，文件或目录');
		o.depends('enabled', '1');
		o.rmempty = false;
		o = s.option(form.Value, 'max_kb', _('单段大小 KB'));
		o.datatype = 'uinteger';
		o.placeholder = '2048';
		o.depends('enabled', '1');
		o.rmempty = false;

		s = m.section(form.NamedSection, 'kernel', 'store', _('内核日志'));
		s.addremove = false;
		s.description = _('内核日志写入磁盘，便于查崩溃和硬件错误。');
		o = s.option(form.Flag, 'enabled', _('写入磁盘'));
		o.default = o.enabled;
		o = s.option(form.Value, 'path', _('存储路径'));
		o.placeholder = _('绝对路径，文件或目录');
		o.depends('enabled', '1');
		o.rmempty = false;
		o = s.option(form.Value, 'max_kb', _('单段大小 KB'));
		o.datatype = 'uinteger';
		o.placeholder = '2048';
		o.depends('enabled', '1');
		o.rmempty = false;

		s = m.section(form.NamedSection, 'mosdns', 'store', _('MosDNS'));
		s.addremove = false;
		s.description = _('关掉则仍用 MosDNS 自己的 log_file。改路径后需重启 MosDNS。');
		o = s.option(form.Flag, 'enabled', _('写到持久路径'));
		o.default = o.disabled;
		o = s.option(form.Value, 'path', _('存储路径'));
		o.placeholder = _('绝对路径，文件或目录');
		o.depends('enabled', '1');
		o.rmempty = false;
		o = s.option(form.Value, 'max_kb', _('单段大小 KB'));
		o.datatype = 'uinteger';
		o.placeholder = '2048';
		o.depends('enabled', '1');
		o.rmempty = false;

		view._storeWrap.style.display = 'none';
		view._storeLoaded = false;
		view._loadStore = function() {
			if (view._storeLoaded)
				return;
			view._storeLoaded = true;
			fs.exec('/usr/libexec/lede-log-read', ['list']).then(function(r) {
				const apps = parseJson(r && r.stdout, []);
				const storageRows = [
					E('tr', { 'class': 'tr table-titles' }, [
						E('th', { 'class': 'th' }, _('用途')),
						E('th', { 'class': 'th' }, _('路径')),
						E('th', { 'class': 'th' }, _('上限')),
						E('th', { 'class': 'th' }, _('已用')),
						E('th', { 'class': 'th' }, _('持久'))
					])
				];
				for (let i = 0; i < apps.length; i++) {
					const a = apps[i];
					storageRows.push(E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td' }, a.title || a.id),
						E('td', { 'class': 'td' }, E('code', {}, a.path || _('仅内存'))),
						E('td', { 'class': 'td' }, a.max_kb ? (a.max_kb + ' KB') : '—'),
						E('td', { 'class': 'td' }, sizeText(a)),
						E('td', { 'class': 'td' }, a.persist ? _('重启保留') : _('重启可能丢失'))
					]));
				}
				return m.render().then(function(node) {
					dom.content(view._storeWrap, [
						E('h3', {}, _('磁盘占用')),
						E('table', { 'class': 'table' }, storageRows),
						E('hr'),
						node
					]);
				});
			}).catch(function() {});
		};

		const origApply = view._applyPane;
		view._applyPane = function() {
			origApply();
			if (view._page === 'config')
				view._loadStore();
		};

		const root = E('div', { 'class': 'lede-loghub' }, [
			E('style', {}, `
				.lede-log-sticky {
					position: sticky; top: 0; z-index: 40;
					display: flex; flex-wrap: wrap; align-items: center; gap: 8px 16px;
					margin: 0 0 12px; padding: 10px 12px;
					background: var(--background-color-high, #fff);
					border: 1px solid var(--border-color-medium, rgba(127,127,127,.18));
					border-radius: 8px;
					box-shadow: 0 6px 16px rgba(0,0,0,.06);
				}
				.lede-log-filters, .lede-log-pager, .lede-log-nav {
					display: flex; flex-wrap: wrap; align-items: center; gap: 8px;
				}
				.lede-log-pager { margin-left: auto; font-weight: 650; }
				.lede-log-ps { display: inline-flex; align-items: center; gap: 6px; }
				.lede-log-ellipsis { opacity: .55; padding: 0 .15em; }
			`),
			E('h2', {}, _('日志中心')),
			view._tabs,
			stickyBar,
			view._box,
			view._storeWrap
		]);

		view._refresh().then(function() {
			poll.add(L.bind(function() {
				if (view._page === 'config')
					return Promise.resolve();
				return view._refresh();
			}, view), 60);
		});
		return root;
	},

	handleSave(ev) {
		const view = this;
		const extra = Promise.all([
			uci.load('wanalert').catch(function() { return null; }),
			uci.load('mosdns').catch(function() { return null; })
		]);
		const saveLog = extra.then(function() {
			return view.map ? view.map.save() : Promise.resolve();
		});
		const prep = function(kind, path) {
			return fs.exec('/usr/libexec/lede-log-read', ['prep', kind, path || '']).then(function(r) {
				const j = parseJson(r && r.stdout, {});
				return (j && j.path) ? j.path : path;
			}).catch(function() { return path; });
		};

		return saveLog.then(function() {
			const enA = uci.get('lede-log', 'alert', 'enabled');
			const pathA = uci.get('lede-log', 'alert', 'path');
			const maxA = uci.get('lede-log', 'alert', 'max_kb');
			const enS = uci.get('lede-log', 'syslog', 'enabled');
			const pathS = uci.get('lede-log', 'syslog', 'path');
			const enK = uci.get('lede-log', 'kernel', 'enabled');
			const pathK = uci.get('lede-log', 'kernel', 'path');
			const enM = uci.get('lede-log', 'mosdns', 'enabled');
			const pathMos = uci.get('lede-log', 'mosdns', 'path');

			const jobs = [];
			jobs.push(pathA ? prep('alert', pathA) : Promise.resolve(''));
			jobs.push((enS !== '0' && pathS) ? prep('syslog', pathS) : Promise.resolve(pathS || ''));
			jobs.push((enK !== '0' && pathK) ? prep('kernel', pathK) : Promise.resolve(pathK || ''));
			jobs.push((enM === '1' && pathMos) ? prep('mosdns', pathMos) : Promise.resolve(pathMos || ''));

			return Promise.all(jobs).then(function(parts) {
				const pA = parts[0], pS = parts[1], pK = parts[2], pM = parts[3];
				uci.set('wanalert', 'main', 'log_enabled', (enA === '0') ? '0' : '1');
				if (pA) {
					uci.set('lede-log', 'alert', 'path', pA);
					uci.set('wanalert', 'main', 'log_path', pA);
				}
				if (maxA)
					uci.set('wanalert', 'main', 'log_max_kb', maxA);
				if (pS)
					uci.set('lede-log', 'syslog', 'path', pS);
				if (pK)
					uci.set('lede-log', 'kernel', 'path', pK);
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
		return this.handleSave(ev).then(function() { return ui.changes.apply(mode == '0'); });
	}
});
