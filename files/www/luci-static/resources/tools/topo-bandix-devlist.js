'use strict';
'require baseclass';
'require dom';
'require rpc';
'require poll';
'require ui';

var _bandixSettingsPromise = null;

function loadBandixSettings() {
	if (!_bandixSettingsPromise)
		_bandixSettingsPromise = L.require('tools.bandix-topo-settings');
	return _bandixSettingsPromise;
}

var callGetDevices = rpc.declare({
	object: 'luci.bandix_plus',
	method: 'getDevices',
	params: [ 'iface', 'period' ],
	expect: {}
});

var callGetSchedules = rpc.declare({
	object: 'luci.bandix_plus',
	method: 'getSchedules',
	expect: {}
});

var callDeleteDevice = rpc.declare({
	object: 'luci.bandix_plus',
	method: 'deleteDevice',
	params: [ 'iface', 'mac' ],
	expect: {}
});

function bplusJson(r) {
	if (r == null) return null;
	if (typeof r === 'string') {
		try { return JSON.parse(r); } catch (e) { return null; }
	}
	return r;
}

function unwrapData(r, fallback) {
	var z = bplusJson(r);
	if (z == null) return fallback;
	if (z.ok === false) throw new Error(z.error || 'RPC error');
	return z.data == null ? fallback : z.data;
}

function asNum(v) {
	var n = +v;
	return isFinite(n) ? n : 0;
}

function formatBytes(n) {
	n = asNum(n);
	if (n <= 0) return '0 B';
	var u = [ 'B', 'KB', 'MB', 'GB', 'TB' ];
	var i = 0;
	while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
	return (i === 0 ? String(Math.round(n)) : n.toFixed(2)) + ' ' + u[i];
}

function formatByteRate(n) {
	n = asNum(n);
	if (n <= 0) return '0 B/s';
	var u = [ 'B/s', 'KB/s', 'MB/s', 'GB/s' ];
	var i = 0;
	while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
	return (i === 0 ? String(Math.round(n)) : n.toFixed(2)) + ' ' + u[i];
}

function formatBpsAsByteRate(bps) {
	return formatByteRate(asNum(bps) / 8);
}

function formatLimitKbpsRate(v) {
	var n = asNum(v);
	if (n <= 0) return '不限速';
	if (n >= 1000) return (n / 1000).toFixed(2) + ' Mbps';
	return Math.round(n) + ' kbps';
}

function deviceIfaceName(d) {
	if (!d || typeof d !== 'object') return '';
	var v = d.logical_iface != null ? String(d.logical_iface).trim() : '';
	if (v) return v;
	v = d.iface != null ? String(d.iface).trim() : '';
	if (v) return v;
	return d.ifname != null ? String(d.ifname).trim() : '';
}

function normalizeMacKey(mac) {
	return String(mac || '').trim().toLowerCase().replace(/[^a-f0-9]/g, '');
}

function deviceFirstIpv4Uint(d) {
	var arr = d && d.ipv4;
	if (!arr || !arr.length) return -1;
	var raw = String(arr[0]).split('/')[0].trim();
	var parts = raw.split('.');
	if (parts.length !== 4) return -1;
	var n = 0;
	for (var i = 0; i < 4; i++) {
		var o = parseInt(parts[i], 10);
		if (isNaN(o) || o < 0 || o > 255) return -1;
		n = ((n << 8) >>> 0) + o;
	}
	return n >>> 0;
}

function compareVal(a, b) {
	if (a === b) return 0;
	if (a == null) return -1;
	if (b == null) return 1;
	if (typeof a === 'number' && typeof b === 'number') return a - b;
	return String(a).localeCompare(String(b));
}

function sumUpBps(x) { return asNum(x && x.up_v4_bps) + asNum(x && x.up_v6_bps); }
function sumDownBps(x) { return asNum(x && x.down_v4_bps) + asNum(x && x.down_v6_bps); }
function sumUpBytes(x) { return asNum(x && x.up_v4_bytes) + asNum(x && x.up_v6_bytes); }
function sumDownBytes(x) { return asNum(x && x.down_v4_bytes) + asNum(x && x.down_v6_bytes); }

function isAbortError(e) {
	var m = (e && e.message) ? String(e.message) : String(e || '');
	return /aborted/i.test(m) || e === '0' || (e && e.name === 'AbortError');
}

function ensureScopedCss() {
	if (document.getElementById('topo-bplus-css'))
		return;
	document.head.appendChild(E('link', {
		id: 'topo-bplus-css',
		rel: 'stylesheet',
		type: 'text/css',
		href: L.resource('bandix_plus/status.css', '?v=53')
	}));
	if (document.getElementById('topo-bplus-layout-css'))
		return;
	document.head.appendChild(E('style', { id: 'topo-bplus-layout-css' }, [
		'.topo-bandix-devlist{margin-top:14px;}',
		'.topo-bandix-devlist .bplus-panel{margin:0;}',
		'.topo-bandix-devlist .bplus-device-toolbar{display:flex;flex-wrap:wrap;gap:8px 14px;align-items:center;margin:0 0 10px;}',
		'.topo-bandix-devlist .bplus-devices-search{min-width:12em;}',
		'.topo-bandix-devlist .topo-bplus-page-nav{margin-left:auto;display:inline-flex;gap:8px;align-items:center;}',
		'.topo-bandix-devlist .table-wrapper{overflow:auto;max-width:100%;}'
	].join('')));
}

return baseclass.extend({
	_host: null,
	_pollFn: null,
	_settingsCtrl: null,
	_devices: [],
	_schedules: [],
	_iface: '',
	_period: 'all',
	_search: '',
	_limitFilter: 'all',
	_page: 1,
	_pageSize: 20,
	_sortKey: 'ipv4',
	_sortAsc: true,
	_displayMode: 'simple',
	_el: {},
	_reqSeq: 0,
	_refreshBusy: false,
	_refreshPending: false,

	getQuery: function() {
		return {
			iface: this._iface || '',
			period: this.applyPeriod(this._period)
		};
	},

	setSharedData: function(devices, schedules) {
		if (!this._host)
			return;
		this._devices = Array.isArray(devices) ? devices : [];
		if (schedules != null)
			this._schedules = Array.isArray(schedules) ? schedules : ((schedules && schedules.schedules) || []);
		for (var i = 0; i < this._devices.length; i++) {
			var d = this._devices[i];
			if (d && !d.logical_iface && deviceIfaceName(d))
				d.logical_iface = deviceIfaceName(d);
		}
		this._renderIfaceOptions();
		this._renderTable();
	},

	mount: function(host, opts) {
		opts = opts || {};
		if (!host)
			return Promise.reject(new Error('missing host'));
		this.unmount();
		this._host = host;
		this._externalPoll = !!opts.externalPoll;
		this._onRefreshRequest = opts.onRefreshRequest || null;
		ensureScopedCss();
		var ps = localStorage.getItem('bplus_devices_page_size');
		this._pageSize = ps ? Math.max(5, Math.min(200, parseInt(ps, 10) || 20)) : 20;
		this._period = localStorage.getItem('bplus_period') || 'all';
		var bdm = localStorage.getItem('bplus_device_display_mode');
		this._displayMode = bdm === 'detailed' ? 'detailed' : 'simple';
		this._buildShell(opts.noTitle ? '' : (opts.title || '设备列表'));
		if (this._externalPoll)
			return Promise.resolve(this);
		var self = this;
		return this.refresh(true).then(function() {
			if (!self._host)
				return self;
			self._pollFn = L.bind(function() {
				if (self._refreshBusy)
					return Promise.resolve();
				return self.refresh(false);
			}, self);
			poll.add(self._pollFn, 5);
			return self;
		});
	},

	unmount: function() {
		this._reqSeq = (this._reqSeq || 0) + 1;
		this._refreshBusy = false;
		this._refreshPending = false;
		if (this._pollFn) {
			poll.remove(this._pollFn);
			this._pollFn = null;
		}
		if (this._settingsCtrl && this._settingsCtrl.closeScheduleHubAll)
			this._settingsCtrl.closeScheduleHubAll();
		this._settingsCtrl = null;
		if (this._host)
			dom.content(this._host, []);
		this._host = null;
		this._el = {};
	},

	_findDevice: function(iface, mac) {
		iface = String(iface || '').trim();
		mac = normalizeMacKey(mac);
		for (var i = 0; i < this._devices.length; i++) {
			var d = this._devices[i];
			if (!d)
				continue;
			if (normalizeMacKey(d.mac) !== mac)
				continue;
			if (iface && deviceIfaceName(d) !== iface)
				continue;
			return d;
		}
		return null;
	},

	_openDeviceSettings: function(iface, mac) {
		var self = this;
		var dev = this._findDevice(iface, mac);
		if (!dev) {
			ui.addNotification(null, E('p', {}, '未找到该设备'), 'warning');
			return Promise.resolve();
		}
		var host = document.getElementById('topo-bplus-modal-host') || document.body;
		return loadBandixSettings().then(function(BandixTopoSettings) {
			return BandixTopoSettings.openForDevice(dev, {
				host: host,
				devices: self._devices,
				schedules: self._schedules || [],
				onRefresh: function() {
					if (self._externalPoll && self._onRefreshRequest)
						return self._onRefreshRequest();
					return self.refresh(false);
				},
				getCtrl: function(ctrl) {
					self._settingsCtrl = ctrl;
				}
			});
		}).catch(function(e) {
			ui.addNotification(null, E('p', {}, '无法打开限速设置：' + (e.message || String(e))), 'warning');
		});
	},

	applyPeriod: function(v) {
		return v === 'all' ? '' : v;
	},

	_fetchRpc: function(call, fallback) {
		return call.then(function(r) { return unwrapData(r, fallback); }).catch(function(e) {
			if (isAbortError(e))
				return fallback;
			throw e;
		});
	},

	refresh: function(showErr) {
		var self = this;
		if (!this._host)
			return Promise.resolve();
		if (this._refreshBusy) {
			this._refreshPending = true;
			return Promise.resolve();
		}
		this._refreshBusy = true;
		var reqSeq = ++this._reqSeq;
		var p = this.applyPeriod(this._period);
		var devErr = null;
		var schedErr = null;
		return Promise.all([
			this._fetchRpc(callGetDevices(this._iface || '', p), []).catch(function(e) {
				devErr = e;
				return [];
			}),
			this._fetchRpc(callGetSchedules(), []).catch(function(e) {
				schedErr = e;
				return [];
			})
		]).then(function(res) {
			if (reqSeq !== self._reqSeq || !self._host)
				return;
			self._devices = (res[0] || []).map(function(d) {
				if (d && !d.logical_iface && deviceIfaceName(d))
					d.logical_iface = deviceIfaceName(d);
				return d;
			});
			self._schedules = Array.isArray(res[1]) ? res[1] : (res[1] && res[1].schedules) || [];
			self._renderIfaceOptions();
			self._renderTable();
			var err = devErr || schedErr;
			if (err && showErr && !isAbortError(err))
				ui.addNotification(null, E('p', {}, 'Bandix 设备列表刷新失败：' + (err.message || String(err))), 'warning');
		}).catch(function(e) {
			if (reqSeq !== self._reqSeq || isAbortError(e))
				return;
			if (showErr)
				ui.addNotification(null, E('p', {}, 'Bandix 设备列表刷新失败：' + (e.message || String(e))), 'warning');
		}).finally(function() {
			if (reqSeq !== self._reqSeq)
				return;
			self._refreshBusy = false;
			if (self._refreshPending) {
				self._refreshPending = false;
				return self.refresh(false);
			}
		});
	},

	_buildShell: function(title) {
		var self = this;
		this._el.search = E('input', { 'class': 'cbi-input-text bplus-devices-search', 'type': 'search', 'placeholder': '搜索 IP / MAC / 名称' });
		this._el.limit = E('select', { 'class': 'cbi-input-select' }, [
			E('option', { 'value': 'all' }, [ '全部限速状态' ]),
			E('option', { 'value': 'limited' }, [ '已限速' ]),
			E('option', { 'value': 'unlimited' }, [ '未限速' ])
		]);
		this._el.iface = E('select', { 'class': 'cbi-input-select' }, [ E('option', { 'value': '' }, [ '全部接口' ]) ]);
		this._el.period = E('select', { 'class': 'cbi-input-select' }, [
			E('option', { 'value': 'all' }, [ '全部时段' ]),
			E('option', { 'value': 'today' }, [ '今天' ]),
			E('option', { 'value': 'week' }, [ '本周' ]),
			E('option', { 'value': 'month' }, [ '本月' ]),
			E('option', { 'value': 'year' }, [ '今年' ])
		]);
		this._el.period.value = this._period;
		this._el.mode = E('select', { 'class': 'cbi-input-select' }, [
			E('option', { 'value': 'simple' }, [ '简易' ]),
			E('option', { 'value': 'detailed' }, [ '详细' ])
		]);
		this._el.mode.value = this._displayMode;
		this._el.pageSize = E('select', { 'class': 'cbi-input-select' }, [
			E('option', { 'value': '10' }, [ '10 条/页' ]),
			E('option', { 'value': '20' }, [ '20 条/页' ]),
			E('option', { 'value': '50' }, [ '50 条/页' ]),
			E('option', { 'value': '100' }, [ '100 条/页' ])
		]);
		this._el.pageSize.value = String(this._pageSize);
		this._el.pagePrev = E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-neutral' }, [ '上一页' ]);
		this._el.pageNext = E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-neutral' }, [ '下一页' ]);
		this._el.count = E('span', { 'class': 'meta-pill' }, [ '在线 0 / 0' ]);
		this._el.head = E('thead');
		this._el.body = E('tbody');

		this._el.search.addEventListener('input', function() {
			self._search = self._el.search.value || '';
			self._page = 1;
			self._renderTable();
		});
		this._el.limit.addEventListener('change', function() {
			self._limitFilter = self._el.limit.value || 'all';
			self._page = 1;
			self._renderTable();
		});
		this._el.iface.addEventListener('change', function() {
			self._iface = self._el.iface.value || '';
			self._page = 1;
			if (self._externalPoll && self._onRefreshRequest)
				self._onRefreshRequest();
			else
				self.refresh(false);
		});
		this._el.period.addEventListener('change', function() {
			self._period = self._el.period.value || 'all';
			localStorage.setItem('bplus_period', self._period);
			self._page = 1;
			if (self._externalPoll && self._onRefreshRequest)
				self._onRefreshRequest();
			else
				self.refresh(false);
		});
		this._el.mode.addEventListener('change', function() {
			self._displayMode = self._el.mode.value === 'detailed' ? 'detailed' : 'simple';
			localStorage.setItem('bplus_device_display_mode', self._displayMode);
			self._renderTable();
		});
		this._el.pageSize.addEventListener('change', function() {
			self._pageSize = Math.max(5, asNum(self._el.pageSize.value) || 20);
			localStorage.setItem('bplus_devices_page_size', String(self._pageSize));
			self._page = 1;
			self._renderTable();
		});
		this._el.pagePrev.addEventListener('click', function(ev) {
			ev.preventDefault();
			if (self._page > 1) { self._page--; self._renderTable(); }
		});
		this._el.pageNext.addEventListener('click', function(ev) {
			ev.preventDefault();
			var total = self._filteredDevices().length;
			var totalPages = Math.max(1, Math.ceil(total / Math.max(5, asNum(self._pageSize) || 20)));
			if (self._page < totalPages) {
				self._page++;
				self._renderTable();
			}
		});
		this._el.body.addEventListener('click', function(ev) {
			var delBtn = ev.target.closest('.topo-bplus-delete');
			if (delBtn) {
				ev.preventDefault();
				self._deleteDevice(delBtn.getAttribute('data-iface'), delBtn.getAttribute('data-mac'));
				return;
			}
			var setBtn = ev.target.closest('.topo-bplus-settings');
			if (setBtn) {
				ev.preventDefault();
				ev.stopPropagation();
				self._openDeviceSettings(setBtn.getAttribute('data-bplus-iface'), setBtn.getAttribute('data-bplus-mac'));
			}
		});

		dom.content(this._host, [
			E('div', { 'class': 'bplus-page bplus-page--topo-embed' }, [
				E('section', { 'class': 'bplus-panel' }, [
					E('div', { 'class': 'bplus-panel-head' }, title ? [
						E('h2', {}, [ title ]),
						this._el.count
					] : [
						this._el.count
					]),
					E('div', { 'class': 'bplus-inline-form bplus-device-toolbar' }, [
						E('label', {}, [ '搜索 ', this._el.search ]),
						E('label', {}, [ '限速 ', this._el.limit ]),
						E('label', {}, [ '接口 ', this._el.iface ]),
						E('label', {}, [ '时段 ', this._el.period ]),
						E('label', {}, [ '显示 ', this._el.mode ]),
						E('label', {}, [ '每页 ', this._el.pageSize ]),
						E('span', { 'class': 'topo-bplus-page-nav' }, [
							this._el.pagePrev, this._el.pageNext
						])
					]),
					E('div', { 'class': 'table-wrapper' }, [
						E('table', { 'class': 'table bplus-table bplus-table--devices' }, [
							this._el.head, this._el.body
						])
					])
				])
			])
		]);
	},

	_renderIfaceOptions: function() {
		var sel = this._el.iface;
		if (!sel) return;
		var old = sel.value || this._iface;
		var ifaces = {};
		for (var i = 0; i < this._devices.length; i++) {
			var n = deviceIfaceName(this._devices[i]);
			if (n) ifaces[n] = 1;
		}
		dom.content(sel, [ E('option', { 'value': '' }, [ '全部接口' ]) ]);
		Object.keys(ifaces).sort().forEach(function(name) {
			sel.appendChild(E('option', { 'value': name }, [ name ]));
		});
		if (old) sel.value = old;
		this._iface = sel.value || '';
	},

	_rulesForDevice: function(dev) {
		var iface = String(deviceIfaceName(dev) || '').trim();
		var mkey = normalizeMacKey(dev && dev.mac);
		var out = [];
		for (var i = 0; i < this._schedules.length; i++) {
			var r = this._schedules[i] || {};
			if (String(r.iface || '').trim() !== iface) continue;
			if (normalizeMacKey(r.mac) !== mkey) continue;
			out.push(r);
		}
		return out;
	},

	_filteredDevices: function() {
		var self = this;
		var q = String(this._search || '').trim().toLowerCase();
		return this._devices.filter(function(d) {
			if (q) {
				var mac = String(d.mac || '').toLowerCase();
				var host = String(d.hostname || '').toLowerCase();
				var ips = ((d.ipv4 || []).concat(d.ipv6 || [])).join(' ').toLowerCase();
				if (mac.indexOf(q) < 0 && host.indexOf(q) < 0 && ips.indexOf(q) < 0)
					return false;
			}
			if (self._limitFilter !== 'all') {
				var limited = self._rulesForDevice(d).length > 0;
				if (self._limitFilter === 'limited' ? !limited : limited)
					return false;
			}
			return true;
		});
	},

	_sortedDevices: function(list) {
		var self = this;
		var key = this._sortKey;
		list = list.slice();
		list.sort(function(a, b) {
			var av, bv;
			if (key === 'ipv4') { av = deviceFirstIpv4Uint(a); bv = deviceFirstIpv4Uint(b); }
			else if (key === 'mac') { av = a.mac || ''; bv = b.mac || ''; }
			else if (key === 'rate_up') { av = sumUpBps(a.metrics); bv = sumUpBps(b.metrics); }
			else if (key === 'rate_down') { av = sumDownBps(a.metrics); bv = sumDownBps(b.metrics); }
			else if (key === 'up_bytes') { av = sumUpBytes(a.cumulative); bv = sumUpBytes(b.cumulative); }
			else if (key === 'down_bytes') { av = sumDownBytes(a.cumulative); bv = sumDownBytes(b.cumulative); }
			else { av = deviceIfaceName(a); bv = deviceIfaceName(b); }
			var cmp = compareVal(av, bv);
			if (cmp === 0) cmp = compareVal(a.mac || '', b.mac || '');
			return self._sortAsc ? cmp : -cmp;
		});
		return list;
	},

	_rateTd: function(met, upload, detailed) {
		var v4 = upload ? asNum(met.up_v4_bps) : asNum(met.down_v4_bps);
		var v6 = upload ? asNum(met.up_v6_bps) : asNum(met.down_v6_bps);
		if (!detailed)
			return E('td', {}, [ formatBpsAsByteRate(v4 + v6) ]);
		return E('td', {}, [ 'v4 ' + formatBpsAsByteRate(v4) + ' / v6 ' + formatBpsAsByteRate(v6) ]);
	},

	_bytesTd: function(cum, upload, detailed) {
		var v4 = upload ? asNum(cum.up_v4_bytes) : asNum(cum.down_v4_bytes);
		var v6 = upload ? asNum(cum.up_v6_bytes) : asNum(cum.down_v6_bytes);
		if (!detailed)
			return E('td', {}, [ formatBytes(v4 + v6) ]);
		return E('td', {}, [ 'v4 ' + formatBytes(v4) + ' / v6 ' + formatBytes(v6) ]);
	},

	_renderTable: function() {
		var self = this;
		var head = this._el.head;
		var body = this._el.body;
		if (!head || !body) return;

		function sortable(label, key) {
			var cls = 'bplus-sortable' + (self._sortKey === key ? (self._sortAsc ? ' asc' : ' desc') : '');
			return E('th', {
				'class': cls,
				'click': function() {
					if (self._sortKey === key) self._sortAsc = !self._sortAsc;
					else { self._sortKey = key; self._sortAsc = false; }
					self._renderTable();
				}
			}, [ label ]);
		}

		dom.content(head, [ E('tr', {}, [
			sortable('接口', 'iface'),
			E('th', {}, [ '名称' ]),
			sortable('MAC', 'mac'),
			sortable('IPv4', 'ipv4'),
			E('th', {}, [ 'IPv6' ]),
			sortable('上行速率', 'rate_up'),
			sortable('下行速率', 'rate_down'),
			sortable('上行流量', 'up_bytes'),
			sortable('下行流量', 'down_bytes'),
			E('th', {}, [ '限速规则' ]),
			E('th', {}, [ '操作' ])
		]) ]);

		var list = this._sortedDevices(this._filteredDevices());
		var online = 0;
		for (var oi = 0; oi < list.length; oi++)
			if (list[oi].online) online++;

		var pageSize = Math.max(5, asNum(this._pageSize) || 20);
		var total = list.length;
		var totalPages = Math.max(1, Math.ceil(total / pageSize));
		if (this._page > totalPages) this._page = totalPages;
		if (this._page < 1) this._page = 1;
		var pageList = list.slice((this._page - 1) * pageSize, (this._page - 1) * pageSize + pageSize);

		if (this._el.count)
			this._el.count.textContent = '在线 ' + String(online) + ' / ' + String(total);
		if (this._el.pagePrev) this._el.pagePrev.disabled = this._page <= 1;
		if (this._el.pageNext) this._el.pageNext.disabled = this._page >= totalPages;

		dom.content(body, []);
		if (!pageList.length) {
			body.appendChild(E('tr', {}, [ E('td', { 'colspan': '11', 'class': 'bplus-empty' }, [ '暂无设备' ]) ]));
			return;
		}

		var det = this._displayMode === 'detailed';
		for (var i = 0; i < pageList.length; i++) {
			var d = pageList[i];
			var met = d.metrics || {};
			var cum = d.cumulative || {};
			var host = (d.hostname && d.hostname !== '-') ? String(d.hostname) : '—';
			var rules = this._rulesForDevice(d);
			var ruleTxt = rules.length ? ('已配置 ' + rules.length + ' 条') : '无规则';
			var iface = deviceIfaceName(d) || '';
			body.appendChild(E('tr', { 'class': d.online ? 'is-online' : 'is-offline' }, [
				E('td', {}, [ iface || '—' ]),
				E('td', {}, [ host ]),
				E('td', { 'class': 'bplus-mono' }, [ d.mac || '—' ]),
				E('td', {}, [ (d.ipv4 && d.ipv4.length) ? d.ipv4.join(', ') : '—' ]),
				E('td', {}, [ (d.ipv6 && d.ipv6.length) ? d.ipv6.join(', ') : '—' ]),
				this._rateTd(met, true, det),
				this._rateTd(met, false, det),
				this._bytesTd(cum, true, det),
				this._bytesTd(cum, false, det),
				E('td', {}, [ ruleTxt ]),
				E('td', {}, [
					E('button', {
						'type': 'button',
						'class': 'btn cbi-button cbi-button-action topo-bplus-settings',
						'data-bplus-iface': iface,
						'data-bplus-mac': d.mac || '',
						'title': '管理该设备限速规则'
					}, [ '设置' ]),
					' ',
					E('button', {
						'type': 'button',
						'class': 'btn cbi-button cbi-button-remove topo-bplus-delete',
						'data-iface': iface,
						'data-mac': d.mac || ''
					}, [ '删除' ])
				])
			]));
		}
	},

	_deleteDevice: function(iface, mac) {
		var self = this;
		iface = String(iface || '').trim();
		mac = String(mac || '').trim();
		if (!iface || !mac) return;
		if (!confirm('确定删除该设备及其限速配置？'))
			return;
		callDeleteDevice(iface, mac).then(function(r) {
			var z = bplusJson(r);
			if (z && z.ok === false) throw new Error(z.error || 'delete failed');
			if (self._externalPoll && self._onRefreshRequest)
				return self._onRefreshRequest();
			return self.refresh(false);
		}).catch(function(e) {
			ui.addNotification(null, E('p', {}, '删除失败：' + (e.message || String(e))), 'danger');
		});
	}
});
