'use strict';
'require baseclass';
'require dom';
'require rpc';
'require ui';

var callGetSchedules = rpc.declare({
	object: 'luci.bandix_plus',
	method: 'getSchedules',
	expect: {}
});
var callCreateSchedule = rpc.declare({
	object: 'luci.bandix_plus',
	method: 'createSchedule',
	params: [ 'payload' ],
	expect: {}
});
var callUpdateSchedule = rpc.declare({
	object: 'luci.bandix_plus',
	method: 'updateSchedule',
	params: [ 'pair' ],
	expect: {}
});
var callDeleteSchedule = rpc.declare({
	object: 'luci.bandix_plus',
	method: 'deleteSchedule',
	params: [ 'id' ],
	expect: {}
});
var callSetDeviceHostname = rpc.declare({
	object: 'luci.bandix_plus',
	method: 'setDeviceHostname',
	params: [ 'iface', 'mac', 'hostname' ],
	expect: {}
});

var _inst = null;

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

function formatLimitKbps(v) {
	var n = asNum(v);
	if (n <= 0) return '不限速';
	if (n >= 1000) return (n / 1000).toFixed(2) + ' Mbps';
	return Math.round(n) + ' kbps';
}

function formatDayLabels(days) {
	if (!days || !days.length) return '—';
	var labels = [ '', '周一', '周二', '周三', '周四', '周五', '周六', '周日' ];
	var parts = [];
	for (var i = 0; i < days.length; i++) {
		var d = asNum(days[i]);
		parts.push(labels[d] || String(days[i]));
	}
	return parts.join('、');
}

function ensureCss() {
	if (document.getElementById('topo-bplus-modal-css'))
		return;
	document.head.appendChild(E('link', {
		id: 'topo-bplus-modal-css',
		rel: 'stylesheet',
		type: 'text/css',
		href: L.resource('bandix_plus/status.css', '?v=53')
	}));
	document.head.appendChild(E('style', { id: 'topo-bplus-modal-inline-css' }, [
		'.topo-bplus-modal-root{position:fixed;inset:0;z-index:10050;display:none;pointer-events:none;}',
		'.topo-bplus-modal-root.show{display:block;pointer-events:auto;}',
		'.topo-bplus-modal-root .bplus-modal-overlay{display:none;position:fixed;inset:0;',
		'align-items:center;justify-content:center;background:rgba(15,23,42,.55);padding:16px;}',
		'.topo-bplus-modal-root .bplus-modal-overlay.show{display:flex;}',
		'.topo-bplus-modal-root .bplus-modal-panel{background:#fff;color:#1f2937;border-radius:12px;',
		'max-width:640px;width:min(640px,calc(100vw - 32px));max-height:calc(100vh - 32px);overflow:auto;',
		'box-shadow:0 20px 50px rgba(0,0,0,.25);}',
		'.topo-bplus-modal-root .bplus-modal-header{display:flex;align-items:center;justify-content:space-between;',
		'padding:14px 18px;border-bottom:1px solid #e5e7eb;}',
		'.topo-bplus-modal-root .bplus-modal-body{padding:16px 18px;}',
		'.topo-bplus-modal-root .bplus-modal-form-footer{display:flex;justify-content:flex-end;gap:8px;margin-top:14px;}',
		'.topo-bplus-modal-root .bplus-schedule-hub-primary{font-weight:700;font-size:1.05em;}',
		'.topo-bplus-modal-root .bplus-schedule-hub-meta{margin-top:4px;color:#64748b;font-size:13px;}',
		'.topo-bplus-modal-root .bplus-schedule-rules-list{margin:10px 0;}',
		'.topo-bplus-modal-root .bplus-schedule-rule-item{display:flex;gap:12px;justify-content:space-between;',
		'padding:10px 0;border-bottom:1px solid #eef2f7;}',
		'.topo-bplus-modal-root .bplus-schedule-rules-empty{color:#64748b;font-size:13px;padding:8px 0;}',
		'.topo-bplus-modal-root .bplus-schedule-days{display:flex;flex-wrap:wrap;gap:6px;}',
		'.topo-bplus-modal-root .bplus-schedule-day-btn{border:1px solid #cbd5e1;background:#fff;border-radius:8px;padding:6px 10px;cursor:pointer;}',
		'.topo-bplus-modal-root .bplus-schedule-day-btn.active{background:#0ea5e9;color:#fff;border-color:#0ea5e9;}',
		'.topo-bplus-modal-root .bplus-form-group{margin:0 0 12px;}',
		'.topo-bplus-modal-root .bplus-form-label{display:block;font-weight:650;margin:0 0 6px;}',
		'.topo-bplus-modal-root .bplus-form-hint{font-size:12px;color:#64748b;margin-top:4px;}',
		'.topo-bplus-modal-root .bplus-schedule-hostname-actions{display:flex;gap:8px;align-items:center;}',
		'.topo-bplus-modal-root .bplus-schedule-hub-toolbar{display:flex;align-items:center;justify-content:space-between;margin:12px 0 6px;}',
		'.topo-bplus-modal-root .bplus-schedule-rate-pair{display:grid;grid-template-columns:1fr 1fr;gap:10px;}',
		'.topo-bplus-modal-root .bplus-rate-input-row{display:flex;gap:6px;align-items:center;}',
		'.topo-bplus-modal-root .confirm-dialog{background:#fff;border-radius:12px;padding:18px;max-width:420px;width:100%;}',
		'.topo-bplus-modal-root .confirm-dialog-footer{display:flex;justify-content:flex-end;gap:8px;margin-top:14px;}'
	].join('')));
}

var TopoBplusSettings = baseclass.extend({
	schedules: [],
	device: null,
	editingId: null,
	pendingDeleteId: null,
	onRefresh: null,
	el: {},

	ensureDom: function(host) {
		ensureCss();
		if (this.el.root)
			return;
		host = host || document.getElementById('topo-bplus-modal-host') || document.body;

		this.el.schStart = E('input', { 'class': 'cbi-input-text', 'type': 'time', 'value': '09:00' });
		this.el.schEnd = E('input', { 'class': 'cbi-input-text', 'type': 'time', 'value': '18:00' });
		this.el.schD4 = E('input', { 'class': 'cbi-input-text', 'type': 'number', 'min': '0', 'step': '1', 'value': '0', 'placeholder': 'kbps' });
		this.el.schD6 = E('input', { 'class': 'cbi-input-text', 'type': 'number', 'min': '0', 'step': '1', 'value': '0', 'placeholder': 'kbps' });
		this.el.schU4 = E('input', { 'class': 'cbi-input-text', 'type': 'number', 'min': '0', 'step': '1', 'value': '0', 'placeholder': 'kbps' });
		this.el.schU6 = E('input', { 'class': 'cbi-input-text', 'type': 'number', 'min': '0', 'step': '1', 'value': '0', 'placeholder': 'kbps' });
		this.el.schCancel = E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-reset' }, [ '取消' ]);
		this.el.schSave = E('button', { 'type': 'submit', 'class': 'btn cbi-button cbi-button-save' }, [ '添加' ]);
		this.el.scheduleDayWrap = E('div', { 'class': 'bplus-schedule-days' });
		var dayLabels = [ '周一', '周二', '周三', '周四', '周五', '周六', '周日' ];
		for (var dnx = 1; dnx <= 7; dnx++) {
			this.el.scheduleDayWrap.appendChild(E('button', {
				'type': 'button',
				'class': 'bplus-schedule-day-btn' + (dnx <= 5 ? ' active' : ''),
				'data-day': String(dnx)
			}, [ dayLabels[dnx - 1] ]));
		}
		this.scheduleDayButtonList = Array.prototype.slice.call(
			this.el.scheduleDayWrap.querySelectorAll('.bplus-schedule-day-btn')
		);
		this.el.scheduleRuleTitle = E('h3', { 'class': 'bplus-modal-title' }, [ '添加限速规则' ]);
		this.el.scheduleRuleForm = E('form', { 'class': 'bplus-schedule-form' }, [
			E('div', { 'class': 'bplus-form-group' }, [
				E('div', { 'class': 'bplus-schedule-time-row' }, [
					this.el.schStart, E('span', {}, [ ' — ' ]), this.el.schEnd
				])
			]),
			E('div', { 'class': 'bplus-form-group' }, [ this.el.scheduleDayWrap ]),
			E('div', { 'class': 'bplus-form-group' }, [
				E('label', { 'class': 'bplus-form-label' }, [ '下载限速 (kbps，0=不限)' ]),
				E('div', { 'class': 'bplus-schedule-rate-pair' }, [
					E('label', {}, [ 'IPv4 ', this.el.schD4 ]),
					E('label', {}, [ 'IPv6 ', this.el.schD6 ])
				])
			]),
			E('div', { 'class': 'bplus-form-group' }, [
				E('label', { 'class': 'bplus-form-label' }, [ '上传限速 (kbps，0=不限)' ]),
				E('div', { 'class': 'bplus-schedule-rate-pair' }, [
					E('label', {}, [ 'IPv4 ', this.el.schU4 ]),
					E('label', {}, [ 'IPv6 ', this.el.schU6 ])
				])
			]),
			E('div', { 'class': 'bplus-modal-form-footer' }, [ this.el.schCancel, this.el.schSave ])
		]);
		this.el.scheduleRulePanel = E('div', { 'class': 'bplus-modal-panel bplus-modal-panel--rule' }, [
			E('div', { 'class': 'bplus-modal-header' }, [ this.el.scheduleRuleTitle ]),
			E('div', { 'class': 'bplus-modal-body' }, [ this.el.scheduleRuleForm ])
		]);
		this.el.scheduleRuleOverlay = E('div', { 'class': 'bplus-modal-overlay bplus-modal-overlay--stack' }, [
			this.el.scheduleRulePanel
		]);

		this.el.hubPrimary = E('div', { 'class': 'bplus-schedule-hub-primary' });
		this.el.hubMeta = E('div', { 'class': 'bplus-schedule-hub-meta' });
		this.el.hubHostname = E('input', { 'class': 'cbi-input-text', 'type': 'text', 'placeholder': '设备名称' });
		this.el.hubHostnameSave = E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-save' }, [ '保存名称' ]);
		this.el.hubAddRule = E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-action' }, [ '添加规则' ]);
		this.el.hubRulesList = E('div', { 'class': 'bplus-schedule-rules-list' });
		this.el.hubClose = E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-reset' }, [ '关闭' ]);
		this.el.hubPanel = E('div', { 'class': 'bplus-modal-panel bplus-modal-panel--hub' }, [
			E('div', { 'class': 'bplus-modal-header' }, [ E('h3', { 'class': 'bplus-modal-title' }, [ '限速规则' ]) ]),
			E('div', { 'class': 'bplus-modal-body' }, [
				E('div', { 'class': 'bplus-schedule-hub-summary' }, [ this.el.hubPrimary, this.el.hubMeta ]),
				E('div', { 'class': 'bplus-form-group' }, [
					E('label', { 'class': 'bplus-form-label' }, [ '设备名称' ]),
					E('div', { 'class': 'bplus-schedule-hostname-actions' }, [
						this.el.hubHostname, this.el.hubHostnameSave
					])
				]),
				E('div', { 'class': 'bplus-schedule-hub-toolbar' }, [
					E('span', {}, [ '定时限速规则' ]), this.el.hubAddRule
				]),
				this.el.hubRulesList,
				E('div', { 'class': 'bplus-modal-form-footer' }, [ this.el.hubClose ])
			])
		]);
		this.el.hubOverlay = E('div', { 'class': 'bplus-modal-overlay' }, [ this.el.hubPanel ]);

		this.el.delCancel = E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-reset' }, [ '取消' ]);
		this.el.delOk = E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-negative' }, [ '删除' ]);
		this.el.delOverlay = E('div', { 'class': 'bplus-modal-overlay bplus-modal-overlay--stack' }, [
			E('div', { 'class': 'confirm-dialog' }, [
				E('div', { 'class': 'confirm-dialog-title' }, [ '删除限速规则' ]),
				E('div', { 'class': 'confirm-dialog-message' }, [ '确定删除这条定时限速规则？' ]),
				E('div', { 'class': 'confirm-dialog-footer' }, [ this.el.delCancel, this.el.delOk ])
			])
		]);

		this.el.root = E('div', { 'class': 'topo-bplus-modal-root', 'id': 'topo-bplus-modal-root' }, [
			this.el.hubOverlay,
			this.el.scheduleRuleOverlay,
			this.el.delOverlay
		]);
		host.appendChild(this.el.root);
		this.bindEvents();
	},

	bindEvents: function() {
		if (this._eventsBound)
			return;
		this._eventsBound = true;
		var self = this;
		this.el.scheduleDayWrap.addEventListener('click', function(ev) {
			var t = ev.target;
			if (t && t.classList && t.classList.contains('bplus-schedule-day-btn'))
				t.classList.toggle('active');
		});
		this.el.hubClose.addEventListener('click', function(ev) {
			ev.preventDefault();
			self.closeAll();
		});
		this.el.hubAddRule.addEventListener('click', function(ev) {
			ev.preventDefault();
			self.openRuleAdd();
		});
		this.el.hubHostnameSave.addEventListener('click', function(ev) {
			ev.preventDefault();
			self.saveHostname();
		});
		this.el.schCancel.addEventListener('click', function(ev) {
			ev.preventDefault();
			self.hideRuleModal();
		});
		this.el.scheduleRuleForm.addEventListener('submit', function(ev) {
			self.submitRule(ev);
		});
		this.el.schSave.addEventListener('click', function(ev) {
			ev.preventDefault();
			self.submitRule(ev);
		});
		this.el.delCancel.addEventListener('click', function(ev) {
			ev.preventDefault();
			self.hideDeleteConfirm();
		});
		this.el.delOk.addEventListener('click', function(ev) {
			ev.preventDefault();
			self.confirmDelete();
		});
		this.el.hubOverlay.addEventListener('click', function(ev) {
			if (ev.target === self.el.hubOverlay)
				self.closeAll();
		});
	},

	refreshSchedules: function() {
		return callGetSchedules().then(function(r) {
			return unwrapData(r, []);
		}).then(L.bind(function(list) {
			this.schedules = Array.isArray(list) ? list : [];
			return this.schedules;
		}, this));
	},

	fillDevice: function(dev) {
		this.device = dev;
		var hn = dev.hostname && dev.hostname !== '-' && String(dev.hostname).trim()
			? String(dev.hostname) : '';
		var primary = hn || ((dev.ipv4 && dev.ipv4.length) ? dev.ipv4[0] : '') || (dev.mac || '—');
		var iface = deviceIfaceName(dev) || '—';
		var ip = (dev.ipv4 && dev.ipv4.length) ? dev.ipv4.join(', ') : '—';
		var v6 = (dev.ipv6 && dev.ipv6.length) ? dev.ipv6.join(', ') : '—';
		this.el.hubPrimary.textContent = primary;
		this.el.hubMeta.textContent = '接口 ' + iface + ' · MAC ' + (dev.mac || '—') +
			' · IPv4 ' + ip + ' · IPv6 ' + v6;
		this.el.hubHostname.value = hn;
	},

	renderRules: function() {
		var wrap = this.el.hubRulesList;
		var dev = this.device;
		dom.content(wrap, []);
		if (!dev) return;
		var mkey = normalizeMacKey(dev.mac);
		var iface = String(deviceIfaceName(dev) || '');
		var rules = (this.schedules || []).filter(function(r) {
			return normalizeMacKey(r.mac) === mkey && String(r.iface || '') === iface;
		});
		if (!rules.length) {
			wrap.appendChild(E('div', { 'class': 'bplus-schedule-rules-empty' },
				[ '暂无规则，点击「添加规则」。' ]));
			return;
		}
		var self = this;
		for (var i = 0; i < rules.length; i++) {
			(function(r) {
				var t = r.time_slot || {};
				var item = E('div', { 'class': 'bplus-schedule-rule-item' }, [
					E('div', { 'class': 'bplus-schedule-rule-info' }, [
						E('div', {}, [ (t.start || '--:--') + ' – ' + (t.end || '--:--') ]),
						E('div', {}, [ formatDayLabels(t.days) ]),
						E('div', {}, [
							'IPv4 下/上 ' + formatLimitKbps(r.down_v4_kbps) + ' / ' + formatLimitKbps(r.up_v4_kbps)
						]),
						E('div', {}, [
							'IPv6 下/上 ' + formatLimitKbps(r.down_v6_kbps) + ' / ' + formatLimitKbps(r.up_v6_kbps)
						])
					]),
					E('div', { 'class': 'bplus-schedule-rule-actions' }, [
						E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-edit' }, [ '编辑' ]),
						E('button', { 'type': 'button', 'class': 'btn cbi-button cbi-button-remove' }, [ '删除' ])
					])
				]);
				item.querySelector('.cbi-button-edit').addEventListener('click', function(ev) {
					ev.preventDefault();
					self.openRuleEdit(r);
				});
				item.querySelector('.cbi-button-remove').addEventListener('click', function(ev) {
					ev.preventDefault();
					self.pendingDeleteId = String(r.id);
					self.el.delOverlay.classList.add('show');
					self.syncVisible();
				});
				wrap.appendChild(item);
			})(rules[i]);
		}
	},

	resetRuleForm: function() {
		this.editingId = null;
		this.el.schSave.textContent = '添加';
		this.el.scheduleRuleTitle.textContent = '添加限速规则';
		for (var di = 0; di < this.scheduleDayButtonList.length; di++) {
			var btn = this.scheduleDayButtonList[di];
			var num = asNum(btn.getAttribute('data-day'));
			btn.classList.toggle('active', num >= 1 && num <= 5);
		}
		this.el.schStart.value = '09:00';
		this.el.schEnd.value = '18:00';
		this.el.schD4.value = '0';
		this.el.schD6.value = '0';
		this.el.schU4.value = '0';
		this.el.schU6.value = '0';
	},

	applyRuleToForm: function(r) {
		var t = r.time_slot || {};
		this.editingId = String(r.id);
		this.el.schSave.textContent = '更新';
		this.el.scheduleRuleTitle.textContent = '编辑限速规则';
		this.el.schStart.value = t.start || '09:00';
		this.el.schEnd.value = t.end || '18:00';
		var daySet = {};
		var daysArr = t.days || [];
		for (var qd = 0; qd < daysArr.length; qd++)
			daySet[String(daysArr[qd])] = true;
		for (var di = 0; di < this.scheduleDayButtonList.length; di++) {
			var btn = this.scheduleDayButtonList[di];
			btn.classList.toggle('active', !!daySet[String(asNum(btn.getAttribute('data-day')))]);
		}
		this.el.schD4.value = String(asNum(r.down_v4_kbps));
		this.el.schD6.value = String(asNum(r.down_v6_kbps));
		this.el.schU4.value = String(asNum(r.up_v4_kbps));
		this.el.schU6.value = String(asNum(r.up_v6_kbps));
	},

	openRuleAdd: function() {
		this.resetRuleForm();
		this.el.scheduleRuleOverlay.classList.add('show');
		this.syncVisible();
	},

	openRuleEdit: function(r) {
		this.applyRuleToForm(r);
		this.el.scheduleRuleOverlay.classList.add('show');
		this.syncVisible();
	},

	hideRuleModal: function() {
		this.el.scheduleRuleOverlay.classList.remove('show');
		this.resetRuleForm();
		this.syncVisible();
	},

	hideDeleteConfirm: function() {
		this.pendingDeleteId = null;
		this.el.delOverlay.classList.remove('show');
		this.syncVisible();
	},

	syncVisible: function() {
		var open = this.el.hubOverlay.classList.contains('show') ||
			this.el.scheduleRuleOverlay.classList.contains('show') ||
			this.el.delOverlay.classList.contains('show');
		this.el.root.classList.toggle('show', open);
	},

	submitRule: function(ev) {
		ev.preventDefault();
		var days = [];
		for (var di = 0; di < this.scheduleDayButtonList.length; di++) {
			var b = this.scheduleDayButtonList[di];
			if (b.classList.contains('active'))
				days.push(asNum(b.getAttribute('data-day')));
		}
		days.sort(function(a, bb) { return a - bb; });
		if (!days.length) {
			ui.addNotification(null, E('p', {}, '请至少选择一天'), 'warning');
			return;
		}
		var dev = this.device;
		if (!dev) return;
		var iface = String(deviceIfaceName(dev) || '').trim();
		var mac = String(dev.mac || '').trim();
		if (!iface || !mac) return;
		var payload = {
			iface: iface,
			mac: mac,
			time_slot: {
				start: this.el.schStart.value || '00:00',
				end: this.el.schEnd.value || '23:59',
				days: days
			},
			down_v4_kbps: asNum(this.el.schD4.value),
			down_v6_kbps: asNum(this.el.schD6.value),
			up_v4_kbps: asNum(this.el.schU4.value),
			up_v6_kbps: asNum(this.el.schU6.value)
		};
		var req = this.editingId
			? callUpdateSchedule([ this.editingId, payload ])
			: callCreateSchedule(payload);
		var self = this;
		var saveBtn = this.el.schSave;
		if (saveBtn) {
			saveBtn.disabled = true;
			saveBtn.setAttribute('aria-busy', 'true');
		}
		req.then(bplusJson).then(function(r) {
			if (r && r.ok === false) throw new Error(r.error || 'submit failed');
			return self.refreshSchedules();
		}).then(function() {
			self.hideRuleModal();
			self.renderRules();
			if (typeof self.onRefresh === 'function')
				return self.onRefresh();
		}).catch(function(e) {
			ui.addNotification(null, E('p', {}, '保存失败：' + (e.message || String(e))), 'danger');
		}).finally(function() {
			if (saveBtn) {
				saveBtn.disabled = false;
				saveBtn.removeAttribute('aria-busy');
			}
		});
	},

	confirmDelete: function() {
		var id = this.pendingDeleteId;
		this.hideDeleteConfirm();
		if (!id) return;
		var self = this;
		callDeleteSchedule(id).then(bplusJson).then(function(r) {
			if (r && r.ok === false) throw new Error(r.error || 'delete failed');
			return self.refreshSchedules();
		}).then(function() {
			self.renderRules();
			if (typeof self.onRefresh === 'function')
				return self.onRefresh();
		}).catch(function(e) {
			ui.addNotification(null, E('p', {}, '删除失败：' + (e.message || String(e))), 'danger');
		});
	},

	saveHostname: function() {
		var dev = this.device;
		var hostname = this.el.hubHostname.value.trim();
		if (!dev || !hostname) {
			ui.addNotification(null, E('p', {}, '请输入设备名称'), 'warning');
			return;
		}
		var iface = String(deviceIfaceName(dev) || '').trim();
		var mac = String(dev.mac || '').trim();
		var self = this;
		callSetDeviceHostname(iface, mac, hostname).then(bplusJson).then(function(r) {
			if (r && r.ok === false) throw new Error(r.error || 'hostname failed');
			dev.hostname = hostname;
			self.fillDevice(dev);
			if (typeof self.onRefresh === 'function')
				return self.onRefresh();
		}).catch(function(e) {
			ui.addNotification(null, E('p', {}, '保存名称失败：' + (e.message || String(e))), 'danger');
		});
	},

	openForDevice: function(dev, ctx) {
		ctx = ctx || {};
		if (!dev)
			return Promise.reject(new Error('missing device'));
		this.onRefresh = typeof ctx.onRefresh === 'function' ? ctx.onRefresh : null;
		if (ctx.schedules)
			this.schedules = ctx.schedules;
		this.ensureDom(ctx.host);
		var self = this;
		return this.refreshSchedules().then(function() {
			self.fillDevice(dev);
			self.renderRules();
			self.el.hubOverlay.classList.add('show');
			self.syncVisible();
			if (typeof ctx.getCtrl === 'function')
				ctx.getCtrl(self);
			return self;
		});
	},

	closeAll: function() {
		this.hideDeleteConfirm();
		this.hideRuleModal();
		this.el.hubOverlay.classList.remove('show');
		this.device = null;
		this.syncVisible();
	}
});

return baseclass.extend({
	openForDevice: function(dev, ctx) {
		if (!_inst)
			_inst = new TopoBplusSettings({});
		return _inst.openForDevice(dev, ctx);
	},
	close: function() {
		if (_inst)
			_inst.closeAll();
	}
});
