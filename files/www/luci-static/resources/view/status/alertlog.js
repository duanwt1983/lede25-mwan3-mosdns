'use strict';
'require view';
'require fs';
'require ui';
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

const PAGE_SIZES = [10, 20, 30, 50];

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

function newestFirst(rows) {
	return (rows || []).slice().sort(function(a, b) {
		return String((b && b.time) || '').localeCompare(String((a && a.time) || ''));
	});
}

function clampPageSize(v) {
	const n = parseInt(v, 10);
	return PAGE_SIZES.indexOf(n) >= 0 ? n : 20;
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

function upMacs(s) {
	return String(s || '').replace(/([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}/g, function(m) {
		return m.toUpperCase().replace(/-/g, ':');
	});
}

function renderTable(rows) {
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
			E('td', { 'class': 'td', 'style': colStyle('time') }, r.time || ''),
			E('td', { 'class': 'td', 'style': colStyle('level') }, levelBadge(r.level)),
			E('td', { 'class': 'td', 'style': colStyle('cat') }, r.cat || ''),
			E('td', { 'class': 'td', 'style': colStyle('title') }, E('strong', {}, upMacs(r.title || ''))),
			E('td', { 'class': 'td', 'style': colStyle('detail') }, upMacs(r.detail || ''))
		]));
	}
	if (!body.length)
		body.push(E('tr', { 'class': 'tr' },
			E('td', { 'class': 'td', colspan: 5 },
				_('还没有报警记录。请到「系统报警」打开写入日志，并确认推送/阈值会触发。存储路径在「日志中心」。'))));
	const head = E('tr', { 'class': 'tr table-titles' }, [
		E('th', { 'class': 'th', 'style': colStyle('time') }, _('时间')),
		E('th', { 'class': 'th', 'style': colStyle('level') }, _('级别')),
		E('th', { 'class': 'th', 'style': colStyle('cat') }, _('分类')),
		E('th', { 'class': 'th', 'style': colStyle('title') }, _('事件')),
		E('th', { 'class': 'th', 'style': colStyle('detail') }, _('说明'))
	]);
	return E('div', { 'style': 'overflow-x:auto' }, [
		E('table', { 'class': 'table cbi-section-table', 'style': 'table-layout:fixed;width:100%' }, [head].concat(body))
	]);
}

return view.extend({
	load() {
		return fs.exec('/usr/libexec/lede-log-read', ['read', 'alert', '500', 'alarm']).then(r => parseJson(r && r.stdout));
	},

	render(rows) {
		const view = this;
		view._all = newestFirst(Array.isArray(rows) ? rows : []);
		view._page = 1;
		try { view._ps = clampPageSize(localStorage.getItem('lede-alertlog-ps')); }
		catch (e) { view._ps = 20; }
		view._box = E('div');
		view._paint = function() {
			const all = view._all || [];
			const size = clampPageSize(view._ps);
			const pages = Math.max(1, Math.ceil(all.length / size) || 1);
			if (view._page > pages)
				view._page = pages;
			const start = (view._page - 1) * size;
			const sizeSel = E('select', { 'style': 'min-width:4.5em' });
			PAGE_SIZES.forEach(function(n) {
				sizeSel.appendChild(E('option', { value: String(n), selected: n === size }, String(n)));
			});
			sizeSel.addEventListener('change', function() {
				view._ps = clampPageSize(this.value);
				view._page = 1;
				try { localStorage.setItem('lede-alertlog-ps', String(view._ps)); } catch (e) {}
				view._paint();
			});
			const prev = E('button', { type: 'button', 'class': 'btn cbi-button', disabled: view._page <= 1 }, _('上一页'));
			const next = E('button', { type: 'button', 'class': 'btn cbi-button', disabled: view._page >= pages }, _('下一页'));
			prev.addEventListener('click', function() { view._page -= 1; view._paint(); });
			next.addEventListener('click', function() { view._page += 1; view._paint(); });
			dom.content(view._box, [
				E('div', { 'style': 'display:flex;flex-wrap:wrap;align-items:center;gap:10px;margin:0 0 .6em' }, [
					E('span', {}, _('共 %d 条').format(all.length)),
					prev,
					E('span', {}, _('第 %d / %d 页').format(view._page, pages)),
					next,
					E('span', {}, _('每页')),
					sizeSel,
					E('span', {}, _('条'))
				]),
				renderTable(all.slice(start, start + size))
			]);
		};
		view._refresh = function() {
			return fs.exec('/usr/libexec/lede-log-read', ['read', 'alert', '500', 'alarm']).then(r => {
				const next = newestFirst(parseJson(r && r.stdout));
				const sig = JSON.stringify(next);
				if (sig === view._sig)
					return;
				view._sig = sig;
				view._all = next;
				view._paint();
			}).catch(e => {
				dom.content(view._box, E('p', {}, e.message || String(e)));
			});
		};
		view._paint();
		poll.add(L.bind(view._refresh, view), 8);

		return E('div', {}, [
			E('h2', {}, _('报警日志')),
			E('p', {}, _('按网络、设备、安全、系统四类记录。不含采样和未持续的突发。最新的在最上面。钉钉 / PushPlus 在「系统报警」里配。')),
			E('div', { 'style': 'margin:.5em 0 1em' }, [
				E('a', {
					'class': 'btn cbi-button',
					'href': L.url('admin/status/wanalert')
				}, _('报警设置')),
				' ',
				E('a', {
					'class': 'btn cbi-button',
					'href': L.url('admin/status/logs')
				}, _('日志中心 / 存储路径'))
			]),
			view._box
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
