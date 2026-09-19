'use strict';
'require view';
'require poll';
'require rpc';
'require uci';
'require fs';
'require ui';
'require view.status.ratechart as rc';

const callSnapshot = rpc.declare({
	object: 'wanmonitor',
	method: 'snapshot',
	expect: {}
});

const callUciRevert = rpc.declare({
	object: 'uci',
	method: 'revert',
	params: [ 'config' ]
});

const callRateHist = rpc.declare({
	object: 'wanmonitor',
	method: 'rate_hist',
	params: [ 'window' ],
	expect: {}
});

function fmtBitrate(bps) {
	if (!isFinite(bps) || bps < 0)
		bps = 0;
	const mbps = bps / 1e6;
	if (mbps >= 100)
		return mbps.toFixed(1) + ' Mbps';
	if (mbps >= 1)
		return mbps.toFixed(2) + ' Mbps';
	return mbps.toFixed(3) + ' Mbps';
}

function fmtBytes(n) {
	n = Number(n) || 0;
	if (n < 1024)
		return n + ' B';
	if (n < 1048576)
		return (n / 1024).toFixed(1) + ' KB';
	if (n < 1073741824)
		return (n / 1048576).toFixed(1) + ' MB';
	return (n / 1073741824).toFixed(2) + ' GB';
}

function rateOf(prev, now, field) {
	if (!prev || !now)
		return 0;
	const dt = (now.ts - prev.ts) / 1000;
	if (dt <= 0.2)
		return 0;
	const d = Number(now[field]) - Number(prev[field]);
	if (d < 0)
		return 0;
	return (d * 8) / dt;
}

function lastHist(rates, name, field) {
	const tip = rates && rates.series_tip && rates.series_tip[name];
	if (tip && tip[field] != null)
		return Number(tip[field]) || 0;
	const s = rates && rates.series && rates.series[name];
	const a = s && s[field];
	if (!a || !a.length)
		return 0;
	return Number(a[a.length - 1]) || 0;
}

const WIN_OPTS = [
	{ v: 300, l: '5 分钟' },
	{ v: 900, l: '15 分钟' },
	{ v: 1800, l: '30 分钟' },
	{ v: 3600, l: '1 小时' },
	{ v: 14400, l: '4 小时' },
	{ v: 43200, l: '12 小时' },
	{ v: 86400, l: '24 小时' }
];
const HIST = 90;

function legend(items) {
	return E('div', { 'class': 'wanmon-legend' }, items.map(it =>
		E('span', {}, [
			E('i', { 'style': 'display:inline-block;width:18px;height:0;margin-right:6px;vertical-align:middle;border-top:' +
				(it.dot ? '2px dotted ' : (it.dash ? '2px dashed ' : '2px solid ')) + it.color }),
			it.label
		])));
}

function fmtLat(v) {
	const n = Number(v);
	if (!isFinite(n) || n <= 0)
		return '延时 --';
	if (n >= 100)
		return '延时 ' + n.toFixed(0) + ' ms';
	return '延时 ' + n.toFixed(1) + ' ms';
}

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	hist: {},
	prev: null,
	polling: false,
	mode: (typeof localStorage !== 'undefined' && localStorage.getItem('wanmon-chart')) || 'cards',
	windowSec: (function() {
		const n = Number(typeof localStorage !== 'undefined' && localStorage.getItem('wanmon-span'));
		return WIN_OPTS.some(o => o.v === n) ? n : 300;
	})(),
	wanNames: '',
	_cliSort: 'name',
	_cliDir: 1,
	_cliSig: '',
	_cliTab: 'clients',
	_editing: false,

	load() {
		return callSnapshot().then(function(data) {
			if (ui.changes && typeof ui.changes.init === 'function')
				ui.changes.init();
			return data;
		});
	},

	pushHist(key, rx, tx) {
		if (!this.hist[key])
			this.hist[key] = { rx: [], tx: [] };
		const h = this.hist[key];
		h.rx.push(rx);
		h.tx.push(tx);
		if (h.rx.length > HIST) {
			h.rx.shift();
			h.tx.shift();
		}
	},

	applyRateHist(rates) {
		if (!rates || !rates.series)
			return false;
		const keys = Object.keys(rates.series);
		if (!keys.length)
			return false;
		const next = {};
		keys.forEach(k => {
			const s = rates.series[k] || {};
			const rx = Array.isArray(s.rx) ? s.rx.slice() : [];
			const tx = Array.isArray(s.tx) ? s.tx.slice() : [];
			/* LOCKED lede-rate.uc v1: series.rx=down series.tx=up; PPPoE down=tx br-lan down=rx */
			next[k] = { rx: rx, tx: tx, lat: Array.isArray(s.lat) ? s.lat.slice() : [] };
		});
		this.hist = next;
		this._rateMeta = rates;
		this._times = Array.isArray(rates.t) ? rates.t : [];
		return true;
	},

	winLabel() {
		const w = this.windowSec;
		for (let i = 0; i < WIN_OPTS.length; i++)
			if (WIN_OPTS[i].v === w)
				return WIN_OPTS[i].l;
		return (w < 3600) ? Math.round(w / 60) + ' 分钟' : (w / 3600) + ' 小时';
	},

	rateCaption() {
		const r = this._rateMeta;
		const iv = (r && r.interval) || 10;
		const stored = (r && r.stored != null) ? Number(r.stored) : ((r && r.t && r.t.length) || 0);
		const have = (this._times && this._times.length) || 0;
		if (have < 2)
			return '后台每 ' + iv + ' 秒采样，最多保留 24 小时，写入数据盘（有 /data 用 /data/metrics，否则用 overlay）。当前窗口：' + this.winLabel() + '（采样积累中…）';
		const sec = Math.max(1, (this._times[have - 1] - this._times[0]) || 0);
		let span;
		if (sec < 90)
			span = sec + ' 秒';
		else if (sec < 3600)
			span = Math.max(1, Math.round(sec / 60)) + ' 分钟';
		else
			span = (sec / 3600).toFixed(sec >= 10 * 3600 ? 0 : 1) + ' 小时';
		const keepH = Math.min(24, Math.round((stored * iv) / 3600 * 10) / 10);
		return '显示最近 ' + this.winLabel() + ' 中的 ' + span +
			'（每 ' + iv + ' 秒一个点，最多保存约 24 小时，已存约 ' +
			(keepH >= 1 ? keepH + ' 小时' : Math.round(stored * iv / 60) + ' 分钟') +
			'，落在磁盘上重启仍保留）。鼠标移到线上可看该时刻速率。';
	},

	kpi(label, value, sub) {
		return E('div', { 'class': 'wanmon-kpi' }, [
			E('div', { 'class': 'wanmon-kpi-val' }, value),
			E('div', { 'class': 'wanmon-kpi-label' }, label),
			sub ? E('div', { 'class': 'wanmon-kpi-sub' }, sub) : ''
		]);
	},

	syncSelect(sel, wans) {
		if (!sel)
			return;
		const list = wans || [];
		const names = list.map(w => w.name).join(',');
		if (this.wanNames !== names) {
			this.wanNames = names;
			while (sel.firstChild)
				sel.removeChild(sel.firstChild);
			sel.appendChild(E('option', { 'value': 'cards' }, '各条宽带分开显示'));
			sel.appendChild(E('option', { 'value': 'combo' }, '所有宽带叠在一张图'));
			list.forEach(w => sel.appendChild(E('option', { 'value': w.name }, '仅 ' + w.name)));
			if (!list.length)
				sel.appendChild(E('option', { 'value': 'lanrx', disabled: true }, '（未检测到 WAN，请先在 网络 → 接口 里添加宽带口）'));
		}
		const valid = this.mode === 'cards' || this.mode === 'combo' ||
			list.some(w => w.name === this.mode);
		if (!valid)
			this.mode = 'cards';
		sel.value = this.mode;
	},

	_modeSel: null,

	ipSid(ip, prefix) {
		return prefix + String(ip || '').replace(/\./g, '_');
	},

	macSid(mac, prefix) {
		return prefix + String(mac || '').toLowerCase().replace(/:/g, '_');
	},

	kbitOf(sid, dir) {
		if (!sid)
			return '';
		const k = uci.get('lede-limit', sid, dir + '_kbit');
		if (k != null && String(k) !== '')
			return String(k);
		const b = uci.get('lede-limit', sid, dir + '_bps');
		if (b != null && String(b) !== '') {
			const n = Number(b);
			if (isFinite(n) && n > 0)
				return String(Math.max(1, Math.round(n / 1000)));
		}
		const m = uci.get('lede-limit', sid, dir + '_mbps');
		if (m != null && String(m) !== '') {
			const n = Number(m);
			if (isFinite(n) && n > 0)
				return String(Math.round(n * 1000));
		}
		return '';
	},

	manualSid(ip, mac) {
		const ms = mac ? this.macSid(mac, 'm_') : '';
		const is = ip ? this.ipSid(ip, 'm_') : '';
		if (ms && uci.get('lede-limit', ms))
			return ms;
		if (is && uci.get('lede-limit', is))
			return is;
		return ms || is;
	},

	autoSid(ip, mac) {
		const ms = mac ? this.macSid(mac, 'a_') : '';
		const is = ip ? this.ipSid(ip, 'a_') : '';
		if (ms && uci.get('lede-limit', ms))
			return ms;
		if (is && uci.get('lede-limit', is))
			return is;
		return ms || is;
	},

	limitOf(ip, mac) {
		const man = this.manualSid(ip, mac);
		const aut = this.autoSid(ip, mac);
		const autoEn = aut ? uci.get('lede-limit', aut, 'enabled') : '';
		return {
			sid: man,
			up: this.kbitOf(man, 'up'),
			down: this.kbitOf(man, 'down'),
			autoOn: autoEn === '1' || autoEn === 'true',
			autoUp: this.kbitOf(aut, 'up'),
			autoDown: this.kbitOf(aut, 'down')
		};
	},

	parseKbit(raw) {
		const s = String(raw == null ? '' : raw).trim();
		if (s === '')
			return 0;
		if (!/^[0-9]+$/.test(s))
			return null;
		const n = parseInt(s, 10);
		if (!isFinite(n) || n < 0)
			return null;
		if (n > 10000000)
			return null;
		return n;
	},

	fmtLim(kbit) {
		const n = Number(kbit) || 0;
		if (n <= 0)
			return '不限';
		return String(n) + ' kbit';
	},

	limMark(kbit) {
		const n = Number(kbit) || 0;
		if (n <= 0)
			return '';
		return E('div', { 'class': 'wanmon-lim-mark' }, '限 ' + n + ' kbit');
	},

	cmpCli(a, b) {
		const col = this._cliSort;
		const dir = this._cliDir;
		let va = '', vb = '';
		if (col === 'up') {
			va = a.up;
			vb = b.up;
		} else if (col === 'down') {
			va = a.down;
			vb = b.down;
		} else if (col === 'online') {
			va = a.online ? 1 : 0;
			vb = b.online ? 1 : 0;
		} else if (col === 'ip') {
			va = a.ip || '';
			vb = b.ip || '';
		} else if (col === 'mac') {
			va = a.mac || '';
			vb = b.mac || '';
		} else {
			va = a.name || a.hostname || '';
			vb = b.name || b.hostname || '';
		}
		if (typeof va === 'number' && typeof vb === 'number')
			return (va - vb) * dir;
		return String(va).localeCompare(String(vb), 'zh') * dir;
	},

	sortMark(col) {
		if (this._cliSort !== col)
			return '';
		return this._cliDir > 0 ? ' ▲' : ' ▼';
	},

	bindSort(th, col) {
		const self = this;
		th.style.cursor = 'pointer';
		th.addEventListener('click', function() {
			if (self._cliSort === col)
				self._cliDir = -self._cliDir;
			else {
				self._cliSort = col;
				self._cliDir = 1;
			}
			self._cliSig = '';
			if (self.prev)
				self.paintInto(self.prev);
		});
	},

	dash(v) {
		const s = String(v == null ? '' : v).trim();
		return s || '-';
	},

	runLimit(args) {
		const self = this;
		return fs.exec('/usr/libexec/lede-limit-apply', args).then(function(res) {
			const out = ((res && (res.stdout || res.stderr)) || '').trim();
			if (res && res.code === 2)
				ui.addNotification(null, E('p', {}, '限速已记下。当前系统没有 tc（ip-full），规则还不会真正生效。'), 'warning');
			else if (res && res.code)
				ui.addNotification(null, E('p', {}, '保存了，应用失败：' + out), 'error');
			return callUciRevert('lede-limit').catch(function() { return null; });
		}).then(function() {
			uci.unload('lede-limit');
			return uci.load('lede-limit');
		}).then(function() {
			if (ui.changes && typeof ui.changes.init === 'function')
				return ui.changes.init();
		}).then(function() {
			self._cliSig = '';
			self._limSig = '';
			self.paintLimits();
			if (self.prev)
				self.paintClients(self.prev, self.prev, self.prev.clients || []);
		}).catch(function(e) {
			ui.addNotification(null, E('p', {}, e.message || String(e)), 'error');
		});
	},

	saveDir(ip, mac, dir, raw, sidHint) {
		const kbit = this.parseKbit(raw);
		if (kbit == null) {
			ui.addNotification(null, E('p', {}, '限速只能填 0～10000000 的整数（kbit），空或 0 为不限。'), 'error');
			return Promise.resolve();
		}
		return this.runLimit([
			'set',
			this.dash(mac),
			this.dash(ip),
			dir,
			String(kbit),
			this.dash(sidHint)
		]);
	},

	clearLimit(sid) {
		if (!sid)
			return Promise.resolve();
		return this.runLimit(['clear', sid]);
	},

	startEdit(span, ip, mac, dir, cur, sid) {
		const self = this;
		if (this._editing || !span || !span.parentNode)
			return;
		this._editing = true;
		span.style.display = 'none';
		const inp = E('input', {
			'class': 'cbi-input-text wanmon-lim-edit',
			'type': 'text',
			'inputmode': 'numeric',
			'pattern': '[0-9]*',
			'maxlength': '8',
			'value': (Number(cur) > 0) ? String(cur) : '',
			'placeholder': 'kbit，空或0不限'
		});
		span.parentNode.appendChild(inp);
		inp.addEventListener('input', function() {
			this.value = String(this.value || '').replace(/[^0-9]/g, '');
		});
		function done(ok) {
			if (!self._editing)
				return;
			self._editing = false;
			const val = inp.value;
			if (inp.parentNode)
				inp.parentNode.removeChild(inp);
			span.style.display = '';
			if (ok)
				self.saveDir(ip, mac, dir, val, sid);
		}
		inp.addEventListener('keydown', function(ev) {
			if (ev.key === 'Enter') {
				ev.preventDefault();
				inp.blur();
			} else if (ev.key === 'Escape') {
				ev.preventDefault();
				done(false);
			}
		});
		inp.addEventListener('blur', function() { done(true); });
		setTimeout(function() {
			try { inp.focus(); inp.select(); } catch (e) {}
		}, 0);
	},

	allLimitRows() {
		const out = [];
		const self = this;
		function add(type) {
			uci.sections('lede-limit', type, function(s) {
				const up = self.kbitOf(s['.name'], 'up');
				const down = self.kbitOf(s['.name'], 'down');
				const on = s.enabled !== '0' && (Number(up) > 0 || Number(down) > 0);
				if (!on && type === 'manual' && !(s.mac || s.ip))
					return;
				if (!on)
					return;
				out.push({
					sid: s['.name'],
					type: type,
					ip: s.ip || '',
					mac: s.mac || '',
					name: s.name || '',
					up: up,
					down: down
				});
			});
		}
		add('manual');
		add('auto');
		return out;
	},

	paintInto(data) {
		const now = data || {};
		const wans = now.wans || [];
		const lan = now.lan || {};
		const sum = now.clients_sum || {};
		const clients = now.clients || [];
		const prev = this.prev;

		const lanDown = (lan.down_bps != null) ? (+lan.down_bps || 0) :
			((!prev) ? lastHist(now.rates, '_lan', 'rx') : 0);
		const lanUp = (lan.up_bps != null) ? (+lan.up_bps || 0) :
			((!prev) ? lastHist(now.rates, '_lan', 'tx') : 0);
		const fromDisk = !!(this._times && this._times.length);
		if (!fromDisk)
			this.pushHist('_lan', lanDown, lanUp);

		let wanDownTot = 0, wanUpTot = 0;
		const rows = [];
		wans.forEach((w, idx) => {
			const pw = (prev && prev.wans || []).find(x => x.name === w.name);
			const down = (w.down_bps != null) ? (+w.down_bps || 0) :
				((!pw) ? lastHist(now.rates, w.name, 'rx') : 0);
			const up = (w.up_bps != null) ? (+w.up_bps || 0) :
				((!pw) ? lastHist(now.rates, w.name, 'tx') : 0);
			wanDownTot += down;
			wanUpTot += up;
			if (!fromDisk)
				this.pushHist(w.name, down, up);
			rows.push({ w, rx: down, tx: up, color: rc.COLORS[idx % rc.COLORS.length] });
		});
		this._rows = rows;
		this._lanLive = { down: lanDown, up: lanUp };

		this.prev = now;

		this.syncSelect(this._modeSel || document.getElementById('wanmon-mode'), wans);

		const kpis = document.getElementById('wanmon-kpis');
		if (kpis) {
			kpis.innerHTML = '';
			kpis.appendChild(this.kpi('在线终端', String(sum.online != null ? sum.online : 0), 'LAN 邻居表'));
			kpis.appendChild(this.kpi('DHCP 租约', String(sum.leases != null ? sum.leases : 0)));
			kpis.appendChild(this.kpi('WAN 合计下行', fmtBitrate(wanDownTot)));
			kpis.appendChild(this.kpi('WAN 合计上行', fmtBitrate(wanUpTot)));
		}

		this.ensureChartShell(rows);
		this.paintSparks();
		const cap = document.getElementById('wanmon-rate-cap');
		if (cap)
			cap.textContent = this.rateCaption();
		this.paintLanHead(lanDown, lanUp);

		this.paintClients(now, prev, clients);
		if (!this._editing)
			this.paintLimits();
	},

	sparkId(name) {
		return 'wanmon-spark-' + String(name || '').replace(/[^A-Za-z0-9_-]/g, '_');
	},

	ensureChartShell(rows) {
		const chartsEl = document.getElementById('wanmon-charts');
		if (!chartsEl)
			return;
		const sig = this.mode + '|' + rows.map(r => r.w.name).join(',');
		if (chartsEl.getAttribute('data-sig') === sig && chartsEl.firstChild)
			this.updateCardHeads(rows);
		else {
			chartsEl.setAttribute('data-sig', sig);
			chartsEl.innerHTML = '';
			if (this.mode === 'combo') {
				chartsEl.appendChild(legend(rows.flatMap(r => [
					{ color: r.color, label: r.w.name + ' 下行', dash: false },
					{ color: r.color, label: r.w.name + ' 上行', dash: true }
				]).concat([{ color: '#ea580c', label: '延时', dot: true }])));
				chartsEl.appendChild(E('div', { 'id': 'wanmon-spark-combo', 'class': 'ratechart-host' }));
			} else if (!rows.length) {
				chartsEl.appendChild(E('p', { 'class': 'wanmon-meta' },
					'尚未识别到 WAN 口。宽带监控读的是「网络 → 接口」里的 wan（以及防火墙 WAN 区里的接口），不需要启用多线负载。'));
			} else {
				const shown = this.mode === 'cards' ? rows : rows.filter(r => r.w.name === this.mode);
				chartsEl.appendChild(E('div', { 'class': 'wanmon-grid' }, shown.map(r =>
					E('div', { 'class': 'wanmon-card' + (r.w.up ? '' : ' wanmon-down'), 'data-wan': r.w.name }, [
						E('div', { 'class': 'wanmon-head' }, [
							E('strong', {}, r.w.name),
							E('span', { 'class': 'wanmon-badge' + (r.w.up ? ' ok' : ' bad') }, r.w.up ? '正常' : '掉线')
						]),
						E('div', { 'class': 'wanmon-meta wanmon-dev' },
							(r.w.device || '-') + (r.w.ipv4 ? ' · ' + r.w.ipv4 : '')),
						E('div', { 'class': 'wanmon-rates' }, [
							E('span', { 'class': 'wanmon-rx' }, '下行 ' + fmtBitrate(r.rx)),
							E('span', { 'class': 'wanmon-tx' }, '上行 ' + fmtBitrate(r.tx)),
							E('span', { 'class': 'wanmon-lat' }, fmtLat(r.w.latency))
						]),
						legend([
							{ color: '#16a34a', label: '下行', dash: false },
							{ color: '#2563eb', label: '上行', dash: true },
							{ color: '#ea580c', label: '延时', dot: true }
						]),
						E('div', { 'id': this.sparkId(r.w.name), 'class': 'ratechart-host' }),
						E('div', { 'class': 'wanmon-meta wanmon-acc' },
							'累计下行 ' + fmtBytes(r.w.tx_bytes) + ' · 累计上行 ' + fmtBytes(r.w.rx_bytes))
					])
				)));
			}
		}
		const lanEl = document.getElementById('wanmon-lan');
		if (lanEl && !document.getElementById('wanmon-spark-lan')) {
			lanEl.innerHTML = '';
			lanEl.appendChild(legend([
				{ color: '#16a34a', label: '下行', dash: false },
				{ color: '#2563eb', label: '上行', dash: true }
			]));
			lanEl.appendChild(E('div', { 'id': 'wanmon-lan-rates', 'class': 'wanmon-rates' }, [
				E('span', { 'class': 'wanmon-rx' }, ''),
				E('span', { 'class': 'wanmon-tx' }, '')
			]));
			lanEl.appendChild(E('div', { 'id': 'wanmon-spark-lan', 'class': 'ratechart-host' }));
		}
	},

	updateCardHeads(rows) {
		rows.forEach(r => {
			const card = document.querySelector('#wanmon-charts [data-wan="' + r.w.name + '"]');
			if (!card)
				return;
			card.classList.toggle('wanmon-down', !r.w.up);
			const badge = card.querySelector('.wanmon-badge');
			if (badge) {
				badge.className = 'wanmon-badge' + (r.w.up ? ' ok' : ' bad');
				badge.textContent = r.w.up ? '正常' : '掉线';
			}
			const rx = card.querySelector('.wanmon-rx');
			const tx = card.querySelector('.wanmon-tx');
			if (rx)
				rx.textContent = '下行 ' + fmtBitrate(r.rx);
			if (tx)
				tx.textContent = '上行 ' + fmtBitrate(r.tx);
			const lat = card.querySelector('.wanmon-lat');
			if (lat)
				lat.textContent = fmtLat(r.w.latency);
			const acc = card.querySelector('.wanmon-acc');
			if (acc)
				acc.textContent = '累计下行 ' + fmtBytes(r.w.tx_bytes) + ' · 累计上行 ' + fmtBytes(r.w.rx_bytes);
			const dev = card.querySelector('.wanmon-dev');
			if (dev)
				dev.textContent = (r.w.device || '-') + (r.w.ipv4 ? ' · ' + r.w.ipv4 : '');
		});
	},

	paintLanHead(lanDown, lanUp) {
		const box = document.getElementById('wanmon-lan-rates');
		if (!box)
			return;
		const rx = box.querySelector('.wanmon-rx');
		const tx = box.querySelector('.wanmon-tx');
		if (rx)
			rx.textContent = '下行 ' + fmtBitrate(lanDown);
		if (tx)
			tx.textContent = '上行 ' + fmtBitrate(lanUp);
	},

	paintSparks() {
		const times = this._times || [];
		const rows = this._rows || [];
		const last = times.length ? times[times.length - 1] : 0;
		const sig = last + '|' + this.windowSec + '|' + this.mode + '|' + rows.map(r => r.w.name).join(',');
		if (this._sparkSig === sig)
			return;
		this._sparkSig = sig;
		const specOf = (h, withLat) => {
			const s = {
				rx: (h && h.rx && h.rx.length) ? h.rx : [0, 0],
				tx: (h && h.tx && h.tx.length) ? h.tx : [0, 0],
				color: '#16a34a',
				colorTx: '#2563eb'
			};
			if (withLat)
				s.lat = (h && h.lat && h.lat.length) ? h.lat : [0, 0];
			return { t: times, series: [s] };
		};
		if (this.mode === 'combo') {
			const host = document.getElementById('wanmon-spark-combo');
			if (host)
				rc.renderInto(host, {
					t: times,
					series: rows.map(r => {
						const h = this.hist[r.w.name] || { rx: [0, 0], tx: [0, 0], lat: [0, 0] };
						return {
							label: r.w.name,
							color: r.color,
							colorTx: r.color,
							rx: h.rx,
							tx: h.tx,
							lat: h.lat || [0, 0],
							colorLat: '#ea580c'
						};
					})
				});
		} else {
			rows.forEach(r => {
				const host = document.getElementById(this.sparkId(r.w.name));
				if (host)
					rc.renderInto(host, specOf(this.hist[r.w.name], true));
			});
		}
		const lanHost = document.getElementById('wanmon-spark-lan');
		if (lanHost)
			rc.renderInto(lanHost, specOf(this.hist._lan, false));
	},

	pullHist(force) {
		const self = this;
		const win = self.windowSec;
		const last = self.prev && self.prev.rates && self.prev.rates.last;
		if (!self._histBag)
			self._histBag = {};
		if (!force && self._histWin === win && self._histSrcLast === last && self._times && self._times.length)
			return Promise.resolve();
		const bag = self._histBag[win];
		if (bag && bag.last === last) {
			self.applyRateHist(bag);
			self._histWin = win;
			self._histSrcLast = last;
			self.paintSparks();
			const cap0 = document.getElementById('wanmon-rate-cap');
			if (cap0)
				cap0.textContent = self.rateCaption();
			if (!force)
				return Promise.resolve();
		}
		if (self._histBusy)
			return self._histBusy;
		self._histBusy = callRateHist(win).then(function(h) {
			h = h || {};
			if (h.last == null && h.t && h.t.length)
				h.last = h.t[h.t.length - 1];
			self._histBag[win] = h;
			self._histWin = win;
			self._histSrcLast = h.last;
			self.applyRateHist(h);
			self.paintSparks();
			const cap = document.getElementById('wanmon-rate-cap');
			if (cap)
				cap.textContent = self.rateCaption();
		}).catch(function() {}).then(function() {
			self._histBusy = null;
		});
		return self._histBusy;
	},

	clientName(mac, ip) {
		const list = (this.prev && this.prev.clients) || [];
		for (let i = 0; i < list.length; i++) {
			if (mac && list[i].mac === mac)
				return list[i].name || list[i].hostname || ip || mac;
			if (ip && list[i].ip === ip)
				return list[i].name || list[i].hostname || ip;
		}
		return ip || mac || '';
	},

	bindRateClick(el, ip, mac, dir, cur, sid) {
		const self = this;
		el.style.cursor = 'text';
		el.title = '点击填写限速（kbit，空或0不限）';
		el.addEventListener('click', function(ev) {
			ev.preventDefault();
			self.startEdit(el, ip, mac, dir, cur, sid);
		});
	},

	paintLimits() {
		const tbl = document.getElementById('wanmon-limits');
		if (!tbl || this._editing)
			return;
		const rows = this.allLimitRows();
		const sig = rows.map(function(r) {
			return r.sid + ':' + r.mac + ':' + r.ip + ':' + r.up + ':' + r.down + ':' + r.type;
		}).join('|');
		if (this._limSig === sig && tbl.querySelector('tr'))
			return;
		this._limSig = sig;
		tbl.innerHTML = '';
		tbl.appendChild(E('tr', { 'class': 'tr table-titles' }, [
			E('th', { 'class': 'th' }, '名称'),
			E('th', { 'class': 'th' }, 'MAC'),
			E('th', { 'class': 'th' }, 'IP'),
			E('th', { 'class': 'th' }, '上行'),
			E('th', { 'class': 'th' }, '下行'),
			E('th', { 'class': 'th' }, '来源'),
			E('th', { 'class': 'th' }, '')
		]));
		if (!rows.length) {
			tbl.appendChild(E('tr', { 'class': 'tr' },
				E('td', { 'class': 'td', 'colspan': 7 }, '当前没有限速。在终端列表里点击上行/下行数字即可添加。')));
			return;
		}
		const self = this;
		for (let i = 0; i < rows.length; i++) {
			const r = rows[i];
			const upEl = E('span', { 'class': 'wanmon-tx live-up' }, this.fmtLim(r.up));
			const downEl = E('span', { 'class': 'wanmon-rx live-down' }, this.fmtLim(r.down));
			this.bindRateClick(upEl, r.ip, r.mac, 'up', r.up, r.sid);
			this.bindRateClick(downEl, r.ip, r.mac, 'down', r.down, r.sid);
			tbl.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, this.clientName(r.mac, r.ip) || r.name || ''),
				E('td', { 'class': 'td' }, r.mac || '—'),
				E('td', { 'class': 'td' }, r.ip || '—'),
				E('td', { 'class': 'td' }, upEl),
				E('td', { 'class': 'td' }, downEl),
				E('td', { 'class': 'td' }, r.type === 'auto' ? '自动' : '手工'),
				E('td', { 'class': 'td' }, E('button', {
					'class': 'btn cbi-button',
					'click': function(ev) {
						ev.preventDefault();
						self.clearLimit(r.sid);
					}
				}, '解除限速'))
			]));
		}
	},

	paintClients(now, prev, clients) {
		const tbl = document.getElementById('wanmon-clients');
		if (!tbl || this._editing)
			return;
		const self = this;
		const qEl = document.getElementById('wanmon-cli-q');
		const q = qEl ? String(qEl.value || '').trim().toLowerCase() : '';
		const ranked = clients.map(function(c) {
			const pc = (prev && prev.clients || []).find(function(x) {
				return (c.mac && x.mac === c.mac) || (c.ip && x.ip === c.ip);
			});
			const down = Number(c.down_bps) || 0;
			const up = Number(c.up_bps) || 0;
			return Object.assign({}, c, { down: down, up: up });
		});
		const shown = (q ? ranked.filter(function(c) {
			const blob = ((c.name || '') + ' ' + (c.hostname || '') + ' ' +
				(c.ip || '') + ' ' + (c.mac || '')).toLowerCase();
			return blob.indexOf(q) >= 0;
		}) : ranked).slice().sort(function(a, b) {
			return self.cmpCli(a, b);
		});
		const hint = document.getElementById('wanmon-cli-n');
		if (hint)
			hint.textContent = q ?
				('显示 ' + shown.length + ' / ' + ranked.length) :
				('共 ' + ranked.length + ' 台');
		const limSig = this.allLimitRows().map(function(r) {
			return r.mac + r.ip + r.up + r.down;
		}).join(',');
		const sig = this._cliSort + ':' + this._cliDir + ':' + q + ':' + limSig + ':' +
			shown.map(function(c) { return (c.ip || '') + (c.online ? '1' : '0'); }).join(',');
		if (this._cliSig === sig && tbl.querySelector('tr[data-ip]')) {
			for (let i = 0; i < shown.length; i++) {
				const c = shown[i];
				const tr = tbl.querySelector('tr[data-ip="' + (c.ip || '') + '"]');
				if (!tr)
					continue;
				const u = tr.querySelector('.live-up');
				const d = tr.querySelector('.live-down');
				if (u && u.tagName !== 'INPUT')
					u.textContent = fmtBitrate(c.up);
				if (d && d.tagName !== 'INPUT')
					d.textContent = fmtBitrate(c.down);
			}
			return;
		}
		this._cliSig = sig;
		tbl.innerHTML = '';
		const ths = [
			['name', '名称'],
			['ip', 'IP'],
			['mac', 'MAC'],
			['up', '上行'],
			['down', '下行'],
			['online', '状态']
		];
		const hr = E('tr', { 'class': 'tr table-titles' });
		for (let i = 0; i < ths.length; i++) {
			const th = E('th', { 'class': 'th' }, ths[i][1] + this.sortMark(ths[i][0]));
			this.bindSort(th, ths[i][0]);
			hr.appendChild(th);
		}
		tbl.appendChild(hr);
		if (!shown.length) {
			tbl.appendChild(E('tr', { 'class': 'tr' },
				E('td', { 'class': 'td', 'colspan': 6 },
					q ? '没有匹配的终端' : '暂无 DHCP 租约')));
			return;
		}
		for (let i = 0; i < shown.length; i++) {
			const c = shown[i];
			const lim = this.limitOf(c.ip, c.mac);
			const limited = Number(lim.up) > 0 || Number(lim.down) > 0 || lim.autoOn;
			const upEl = E('div', { 'class': 'wanmon-tx live-up' }, fmtBitrate(c.up));
			const downEl = E('div', { 'class': 'wanmon-rx live-down' }, fmtBitrate(c.down));
			this.bindRateClick(upEl, c.ip, c.mac, 'up', lim.up, lim.sid);
			this.bindRateClick(downEl, c.ip, c.mac, 'down', lim.down, lim.sid);
			const autoTxt = lim.autoOn ?
				E('div', { 'class': 'wanmon-auto' },
					'自动 上' + this.fmtLim(lim.autoUp) + ' / 下' + this.fmtLim(lim.autoDown)) : '';
			tbl.appendChild(E('tr', {
				'class': 'tr' + (limited ? ' wanmon-limited' : ''),
				'data-ip': c.ip || '',
				'data-mac': c.mac || ''
			}, [
				E('td', { 'class': 'td' }, [
					c.name || '',
					limited ? E('div', { 'class': 'wanmon-lim-mark' }, '已限速') : ''
				]),
				E('td', { 'class': 'td' }, c.ip || ''),
				E('td', { 'class': 'td' }, c.mac || ''),
				E('td', { 'class': 'td' }, [upEl, this.limMark(lim.up), autoTxt]),
				E('td', { 'class': 'td' }, [downEl, this.limMark(lim.down)]),
				E('td', { 'class': 'td' }, c.online ?
					E('span', { 'class': 'wanmon-dot ok' }, '在线') :
					E('span', {}, '离线'))
			]));
		}
	},

	render(first) {
		const self = this;
		const sel = E('select', {
			'id': 'wanmon-mode',
			'class': 'cbi-input-select',
			'change': function() {
				self.mode = this.value;
				try { localStorage.setItem('wanmon-chart', self.mode); } catch (e) {}
				if (self.prev)
					self.paintInto(self.prev);
			}
		});
		this._modeSel = sel;

		const winSel = E('select', {
			'id': 'wanmon-win',
			'class': 'cbi-input-select',
			'change': function() {
				self.windowSec = Number(this.value) || 300;
				try { localStorage.setItem('wanmon-span', String(self.windowSec)); } catch (e) {}
				self._sparkSig = '';
				self.pullHist(true);
			}
		});
		WIN_OPTS.forEach(function(o) {
			winSel.appendChild(E('option', { 'value': String(o.v) }, o.l));
		});
		winSel.value = String(self.windowSec);
		this._winSel = winSel;

		const tabClients = E('button', {
			'type': 'button',
			'class': 'btn cbi-button cbi-button-action',
			'click': function(ev) {
				ev.preventDefault();
				self._cliTab = 'clients';
				tabClients.classList.add('cbi-button-action');
				tabLimits.classList.remove('cbi-button-action');
				document.getElementById('wanmon-pane-cli').style.display = '';
				document.getElementById('wanmon-pane-lim').style.display = 'none';
			}
		}, '终端列表');
		const tabLimits = E('button', {
			'type': 'button',
			'class': 'btn cbi-button',
			'click': function(ev) {
				ev.preventDefault();
				self._cliTab = 'limits';
				tabLimits.classList.add('cbi-button-action');
				tabClients.classList.remove('cbi-button-action');
				document.getElementById('wanmon-pane-cli').style.display = 'none';
				document.getElementById('wanmon-pane-lim').style.display = '';
				self._limSig = '';
				self.paintLimits();
			}
		}, '限速列表');

		const root = E('div', {}, [
			E('div', { 'class': 'wanmon-kpis', 'id': 'wanmon-kpis' }),
			E('h3', { 'class': 'wanmon-h' }, '宽带速率'),
			E('div', { 'class': 'wanmon-toolbar' }, [
				E('label', {}, '显示方式 '),
				sel,
				E('label', { 'style': 'margin-left:14px' }, '时间范围 '),
				winSel
			]),
			E('p', { 'class': 'wanmon-meta', 'id': 'wanmon-rate-cap' }, ''),
			E('div', { 'id': 'wanmon-charts' }),
			E('h3', { 'class': 'wanmon-h' }, '局域网'),
			E('div', { 'id': 'wanmon-lan' }),
			E('div', { 'class': 'lede-log-tabs', 'style': 'display:flex;flex-wrap:wrap;gap:8px;margin:20px 0 12px' }, [
				tabClients, tabLimits
			]),
			E('div', { 'id': 'wanmon-pane-cli' }, [
				E('div', { 'class': 'wanmon-cli-bar' }, [
					E('input', {
						'id': 'wanmon-cli-q',
						'type': 'search',
						'class': 'cbi-input-text',
						'placeholder': '查找 IP、MAC、名称',
						'input': function() {
							if (self.prev)
								self.paintInto(self.prev);
						}
					}),
					E('span', { 'id': 'wanmon-cli-n', 'class': 'wanmon-meta' }, '')
				]),
				E('table', { 'class': 'table wanmon-table', 'id': 'wanmon-clients' })
			]),
			E('div', { 'id': 'wanmon-pane-lim', 'style': 'display:none' }, [
				E('p', { 'class': 'wanmon-meta' }, '列出已限速的 MAC。点击上行/下行数字可改（单位 kbit，空或 0 为不限）。'),
				E('table', { 'class': 'table wanmon-table', 'id': 'wanmon-limits' })
			])
		]);

		this.syncSelect(sel, (first && first.wans) || []);
		this.paintInto(first);
		this.pullHist(true);

		if (!this.polling) {
			this.polling = true;
			poll.add(L.bind(function() {
				return callSnapshot().then(L.bind(function(snap) {
					this.paintInto(snap);
					return this.pullHist();
				}, this));
			}, this), 3);
		}

		return E('div', {}, [
			E('h2', {}, '宽带监控'),
			E('p', {}, '实线为下行、虚线为上行、点线为线路延时。左侧为延时（ms），右侧为速率。多条宽带各占一行。后台每 10 秒记一个点，最多 24 小时。时间范围可在图上方选择。点击终端上行/下行的数字可填限速，回车或点别处确认；单位为 kbit，只能填整数，空或 0 表示不限。已限速的 MAC 在「限速列表」里查看和解除。'),
			E('style', {}, `
				.wanmon-kpis { display:flex; flex-wrap:wrap; gap:12px; margin-bottom:16px; }
				.wanmon-kpi { flex:1; min-width:140px; padding:14px 16px; border-radius:8px;
					background: var(--background-color-high, #fff); border:1px solid var(--border-color-medium, #ddd); }
				.wanmon-kpi-val { font-size:1.5em; font-weight:700; }
				.wanmon-kpi-label { opacity:.75; margin-top:4px; }
				.wanmon-kpi-sub { font-size:12px; opacity:.65; }
				.wanmon-toolbar { margin-bottom:10px; display:flex; flex-wrap:wrap; align-items:center; gap:8px; }
				.wanmon-grid { display:flex; flex-direction:column; gap:14px; }
				.wanmon-card { padding:14px; border-radius:8px; background: var(--background-color-high, #fff);
					border:1px solid var(--border-color-medium, #ddd); width:100%; }
				.wanmon-card.wanmon-down { opacity:.72; }
				.wanmon-head { display:flex; justify-content:space-between; align-items:center; }
				.wanmon-meta { font-size:12px; opacity:.7; margin:6px 0; }
				.wanmon-rates { display:flex; gap:18px; margin:8px 0; }
				.wanmon-rx { color:#16a34a; font-size:1.2em; font-weight:700; }
				.wanmon-tx { color:#2563eb; font-size:1.2em; font-weight:700; }
				.wanmon-lat { color:#ea580c; font-size:1.2em; font-weight:700; }
				.wanmon-legend { display:flex; gap:14px; font-size:12px; opacity:.8; margin:6px 0; flex-wrap:wrap; }
				.wanmon-badge { font-size:12px; padding:2px 8px; border-radius:10px; }
				.wanmon-badge.ok { background:#e8f8ef; color:#1e8449; }
				.wanmon-badge.bad { background:#fdecea; color:#c0392b; }
				.wanmon-table { width:100%; margin-top:8px; }
				.wanmon-cli-bar { display:flex; align-items:center; gap:12px; margin:8px 0; flex-wrap:wrap; }
				.wanmon-cli-bar input { min-width:16em; max-width:28em; flex:1; }
				.wanmon-lim-edit { width:9em; }
				.wanmon-lim-mark { font-size:12px; color:#c0392b; margin-top:4px; }
				.wanmon-limited td { background: rgba(192,57,43,.04); }
				.live-up, .live-down { border-bottom:1px dashed currentColor; }
				.wanmon-auto { font-size:12px; color:#c0392b; margin-top:4px; }
				.wanmon-dot.ok { color:#1e8449; font-weight:600; }
				.wanmon-h { margin:20px 0 8px; }
				.ratechart-wrap { position:relative; width:100%; color: var(--text-color-high, #1e293b); }
				.ratechart { width:100%; }
				.ratechart-tip { display:none; position:absolute; z-index:5; pointer-events:none;
					padding:6px 8px; border-radius:6px; font-size:12px; line-height:1.45; white-space:pre;
					background: var(--background-color-high, #fff);
					border:1px solid var(--border-color-medium, #ccc);
					box-shadow: 0 4px 14px rgba(0,0,0,.12); }
			`),
			root
		]);
	}
});
