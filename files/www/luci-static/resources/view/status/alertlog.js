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

function parseJson(stdout) {
	const t = (stdout || '').trim();
	if (!t)
		return [];
	try {
		return JSON.parse(t);
	} catch (e) {
		return [];
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

function renderTable(rows) {
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
			E('td', { 'class': 'td', colspan: 5 },
				_('还没有报警记录。请到「系统报警」打开写入日志，并确认钉钉/阈值会触发。存储路径在「日志中心」。'))));
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
		view._box = E('div');
		view._refresh = function() {
			return fs.exec('/usr/libexec/lede-log-read', ['read', 'alert', '500', 'alarm']).then(r => {
				dom.content(view._box, renderTable(parseJson(r && r.stdout)));
			}).catch(e => {
				dom.content(view._box, E('p', {}, e.message || String(e)));
			});
		};
		dom.content(view._box, renderTable(rows || []));
		poll.add(L.bind(view._refresh, view), 15);

		return E('div', {}, [
			E('h2', {}, _('报警日志')),
			E('p', {}, _('线路掉线/恢复、CPU/内存/磁盘/温度/DHCP 池不足等。不含定时状态采样。钉钉机器人在「系统报警」里配。')),
			E('div', { 'style': 'margin:.5em 0 1em' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': ui.createHandlerFn(view, view._refresh)
				}, _('刷新')),
				' ',
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
