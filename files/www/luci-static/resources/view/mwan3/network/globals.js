'use strict';
'require view';
'require ui';
'require uci';
'require fs';
'require network';
'require poll';

const DEF_TRACK = ['223.5.5.5', '119.29.29.29'];

function skipNet(name, proto, device) {
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

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load() {
		return Promise.all([
			uci.load('network'),
			uci.load('mwan3'),
			network.getNetworks(),
			fs.exec('/usr/libexec/lede-mwan3-setup', ['status']).then(r => this.parseJson(r)).catch(() => ({ running: 0 }))
		]);
	},

	collectWans(nets) {
		const out = [];
		const seen = {};
		(nets || []).forEach(net => {
			const name = net.getName ? net.getName() : '';
			const proto = net.getProtocol ? net.getProtocol() : (uci.get('network', name, 'proto') || '');
			const dev = net.getDevice ? (net.getDevice() && net.getDevice().getName()) : (uci.get('network', name, 'device') || '');
			if (skipNet(name, proto, dev) || seen[name])
				return;
			seen[name] = true;
			const en = uci.get('mwan3', name, 'enabled');
			const mem = uci.sections('mwan3', 'member').find(s =>
				uci.get('mwan3', s['.name'], 'interface') === name);
			const weight = mem ? (uci.get('mwan3', mem['.name'], 'weight') || '1') : '1';
			out.push({
				name,
				proto: proto || '',
				device: dev || '',
				up: net.isUp ? net.isUp() : false,
				checked: en === '1' || en === true,
				weight: String(weight)
			});
		});
		uci.sections('network', 'interface').forEach(s => {
			const name = s['.name'];
			if (seen[name] || skipNet(name, s.proto, s.device))
				return;
			seen[name] = true;
			const en = uci.get('mwan3', name, 'enabled');
			out.push({
				name,
				proto: s.proto || '',
				device: s.device || '',
				up: false,
				checked: en === '1',
				weight: '1'
			});
		});
		return out;
	},

	currentTracks() {
		const names = [];
		uci.sections('mwan3', 'interface').forEach(s => names.push(s['.name']));
		if (!names.length)
			return DEF_TRACK.slice();
		const t = uci.get('mwan3', names[0], 'track_ip');
		if (Array.isArray(t) && t.length)
			return t.map(String);
		if (t)
			return [String(t)];
		return DEF_TRACK.slice();
	},

	parseJson(r) {
		const raw = String((r && r.stdout) || '') + String((r && r.stderr) || '');
		const i = raw.indexOf('{');
		const j = raw.lastIndexOf('}');
		if (i < 0 || j <= i) {
			const code = r && r.code != null ? String(r.code) : '';
			return { ok: false, error: raw.trim() || (code ? _('执行失败 (%s)').format(code) : _('没有返回')) };
		}
		try {
			return JSON.parse(raw.slice(i, j + 1));
		} catch (e) {
			return { ok: false, error: raw.trim() };
		}
	},

	paintBadge() {
		const badge = document.getElementById('lb-status');
		if (!badge)
			return;
		if (this._phase === 'starting') {
			badge.textContent = _('启动中......');
			badge.style.color = '#d97706';
			badge.removeAttribute('title');
			return;
		}
		if (this._phase === 'start_fail') {
			badge.textContent = _('启动失败');
			badge.style.color = '#dc2626';
			if (this._phaseErr)
				badge.setAttribute('title', this._phaseErr);
			else
				badge.removeAttribute('title');
			return;
		}
		const on = !!(this._st && Number(this._st.running) === 1);
		badge.textContent = on ? _('运行中') : _('未运行');
		badge.style.color = on ? '#16a34a' : '#dc2626';
		badge.removeAttribute('title');
	},

	refreshStatus() {
		return fs.exec('/usr/libexec/lede-mwan3-setup', ['status']).then(r => {
			this._st = this.parseJson(r);
			this.paintBadge();
			return this._st;
		}).catch(() => this._st);
	},

	waitRunning(want, tries) {
		const self = this;
		function step() {
			return self.refreshStatus().then(st => {
				const on = !!(st && Number(st.running) === 1);
				if (on === want)
					return st;
				if (tries <= 0)
					return st;
				tries--;
				return new Promise(ok => setTimeout(ok, 1000)).then(step);
			});
		}
		return step();
	},

	afterChange() {
		uci.unload('mwan3');
		return uci.load('mwan3').then(() => {
			this._wans = this.collectWans(this._nets);
			return this.refreshStatus().then(() => this.renderPage());
		});
	},

	ok(msg) {
		ui.addNotification(null, E('p', {}, msg), 'success');
	},

	fail(e, fallback) {
		ui.addNotification(null, E('p', {}, (e && e.message) || fallback), 'error');
	},

	stopLb(ev) {
		if (ev)
			ev.preventDefault();
		const btn = document.getElementById('lb-stop');
		if (btn)
			btn.classList.add('spinning');
		return fs.exec('/usr/libexec/lede-mwan3-setup', ['stop']).then(r => {
			const j = this.parseJson(r);
			if (!j.ok)
				throw new Error(j.error || _('关闭失败'));
			return this.waitRunning(false, 20).then(st => {
				if (st && Number(st.running) === 1)
					throw new Error(_('已发出关闭，但服务仍在运行'));
				this.ok(_('已关闭'));
				return this.afterChange();
			});
		}).catch(e => this.fail(e, _('关闭失败'))).finally(() => {
			if (btn)
				btn.classList.remove('spinning');
		});
	},

	restartLb(ev) {
		if (ev)
			ev.preventDefault();
		const btn = document.getElementById('lb-restart');
		if (btn)
			btn.classList.add('spinning');
		const hashMode = (document.getElementById('lb-hash') || {}).value || 'flow';
		const flow = hashMode !== 'ip';
		uci.set('mwan3', 'globals', 'lede_lb_hash', flow ? 'flow' : 'ip');
		if (flow)
			uci.set('mwan3', 'default', 'sticky', '0');
		return uci.save().then(() => fs.exec('/usr/libexec/lede-mwan3-setup', ['restart']).then(r => {
			const j = this.parseJson(r);
			if (!j.ok)
				throw new Error(j.error || _('重启失败'));
			return this.waitRunning(true, 25).then(st => {
				if (!(st && Number(st.running) === 1))
					throw new Error(_('已发出重启，但服务未起来'));
				this.ok(_('已重启'));
				return this.afterChange();
			});
		})).catch(e => this.fail(e, _('重启失败'))).finally(() => {
			if (btn)
				btn.classList.remove('spinning');
		});
	},

	wanChoices() {
		const names = [];
		const seen = {};
		uci.sections('mwan3', 'interface').forEach(s => {
			if (s['.name'] && !seen[s['.name']]) {
				seen[s['.name']] = true;
				names.push(s['.name']);
			}
		});
		(this._wans || []).forEach(w => {
			if (w.name && !seen[w.name]) {
				seen[w.name] = true;
				names.push(w.name);
			}
		});
		return names;
	},

	ruleSummary(s) {
		const name = s['.name'];
		const src = uci.get('mwan3', name, 'src_ip') || '';
		const mac = uci.get('mwan3', name, 'lede_mac') || '';
		const ipset = uci.get('mwan3', name, 'ipset') || '';
		const dest = uci.get('mwan3', name, 'dest_ip') || '';
		const pol = uci.get('mwan3', name, 'use_policy') || '';
		const isp = {
			isp_chinanet: _('电信'),
			isp_unicom: _('联通'),
			isp_cmcc: _('移动'),
			isp_other: _('其它 ISP')
		}[ipset];
		let match = _('其余流量');
		if (mac)
			match = mac + (src ? ' / ' + src : '');
		else if (src && isp)
			match = src + ' → ' + isp;
		else if (src)
			match = src;
		else if (isp)
			match = isp;
		else if (ipset)
			match = ipset;
		else if (dest)
			match = dest;
		return { name, match, pol, auto: uci.get('mwan3', name, 'lede_auto') === '1' };
	},

	extraAdd(ev) {
		if (ev)
			ev.preventDefault();
		const kind = String((document.getElementById('lb-kind') || {}).value || 'ip');
		const ifc = String((document.getElementById('lb-rule-wan') || {}).value || '');
		if (!ifc) {
			this.fail(null, _('请选择宽带'));
			return;
		}
		let args;
		if (kind === 'mac') {
			const mac = String((document.getElementById('lb-pin-mac') || {}).value || '').trim();
			if (!mac) {
				this.fail(null, _('请填写源 MAC'));
				return;
			}
			args = ['extra', 'pin', '--mac', mac, '--iface', ifc];
		} else if (kind === 'dest') {
			const set = String((document.getElementById('lb-isp-set') || {}).value || '');
			if (!set) {
				this.fail(null, _('请选择目的地址'));
				return;
			}
			args = ['extra', 'isp', '--set', set, '--iface', ifc];
		} else {
			const src = String((document.getElementById('lb-pin-val') || {}).value || '').trim();
			if (!src) {
				this.fail(null, _('请填写源 IP'));
				return;
			}
			args = ['extra', 'pin', '--src', src, '--iface', ifc];
		}
		return fs.exec('/usr/libexec/lede-mwan3-setup', args).then(r => {
			const j = this.parseJson(r);
			if (!j.ok)
				throw new Error(j.error || _('添加失败'));
			this.ok(_('已添加'));
			return this.afterChange();
		}).catch(e => this.fail(e, _('添加失败')));
	},

	ruleMid(kind) {
		if (kind === 'mac')
			return E('input', {
				type: 'text', id: 'lb-pin-mac', placeholder: 'aa:bb:cc:dd:ee:ff', 'class': 'lb-mac'
			});
		if (kind === 'dest')
			return E('select', { id: 'lb-isp-set', 'class': 'lb-sel' }, [
				E('option', { value: 'isp_chinanet' }, _('中国电信')),
				E('option', { value: 'isp_unicom' }, _('中国联通')),
				E('option', { value: 'isp_cmcc' }, _('中国移动')),
				E('option', { value: 'isp_other' }, _('其它'))
			]);
		return E('input', {
			type: 'text', id: 'lb-pin-val', placeholder: '192.168.8.10', 'class': 'lb-ip'
		});
	},

	extraDel(ev, name) {
		if (ev)
			ev.preventDefault();
		if (!name)
			return;
		return fs.exec('/usr/libexec/lede-mwan3-setup', ['extra', 'del', '--name', name]).then(r => {
			const j = this.parseJson(r);
			if (!j.ok)
				throw new Error(j.error || _('删除失败'));
			this.ok(_('已删除'));
			return this.afterChange();
		}).catch(e => this.fail(e, _('删除失败')));
	},

	wipeLb(ev) {
		if (ev)
			ev.preventDefault();
		if (!window.confirm(_('停止服务并删除全部规则，确定？')))
			return;
		const btn = document.getElementById('lb-wipe');
		if (btn)
			btn.classList.add('spinning');
		return fs.exec('/usr/libexec/lede-mwan3-setup', ['wipe']).then(r => {
			const j = this.parseJson(r);
			if (!j.ok)
				throw new Error(j.error || _('删除失败'));
			this.ok(_('已删除'));
			return this.afterChange();
		}).catch(e => this.fail(e, _('删除失败'))).finally(() => {
			if (btn)
				btn.classList.remove('spinning');
		});
	},

	applyLb(ev) {
		if (ev)
			ev.preventDefault();
		const rows = this._wans || [];
		const args = ['apply'];
		let n = 0;
		rows.forEach(w => {
			const ck = document.getElementById('lb-ck-' + w.name);
			if (!ck || !ck.checked)
				return;
			n++;
			args.push('--iface', w.name);
			const wt = document.getElementById('lb-wt-' + w.name);
			let v = Number(wt && wt.value);
			if (!(v >= 1 && v <= 100))
				v = 1;
			args.push('--weight', String(v));
		});
		if (n < 2) {
			this.fail(null, _('至少勾选两条宽带'));
			return;
		}
		const tracks = [];
		(this._trackBox.querySelectorAll('input') || []).forEach(inp => {
			const v = String(inp.value || '').trim();
			if (v)
				tracks.push(v);
		});
		(tracks.length ? tracks : DEF_TRACK).forEach(t => args.push('--track', t));
		const sticky = document.getElementById('lb-sticky');
		args.push('--sticky', sticky && sticky.checked ? '1' : '0');
		const hashMode = (document.getElementById('lb-hash') || {}).value || 'flow';
		args.push('--hash-mode', hashMode === 'ip' ? 'ip' : 'flow');
		args.push('--timeout', String((document.getElementById('lb-timeout') || {}).value || '600'));
		args.push('--interval', String((document.getElementById('lb-interval') || {}).value || '5'));
		args.push('--down', String((document.getElementById('lb-down') || {}).value || '3'));
		args.push('--up', String((document.getElementById('lb-up') || {}).value || '3'));

		const btn = document.getElementById('lb-apply');
		if (btn)
			btn.classList.add('spinning');
		this._phase = 'starting';
		this._phaseErr = '';
		this.paintBadge();
		return fs.exec('/usr/libexec/lede-mwan3-setup', args).then(r => {
			const j = this.parseJson(r);
			if (!j.ok)
				throw new Error(j.error || _('启动失败'));
			return this.waitRunning(true, 25).then(st => {
				if (!(st && Number(st.running) === 1))
					throw new Error(_('服务未起来'));
				this._phase = null;
				this._phaseErr = '';
				return this.afterChange();
			});
		}).catch(e => {
			this._phase = 'start_fail';
			this._phaseErr = (e && e.message) || _('启动失败');
			return this.afterChange();
		}).finally(() => {
			if (btn)
				btn.classList.remove('spinning');
		});
	},

	numInput(id, val, min, max, width) {
		return E('input', {
			type: 'number', id: id, min: String(min), max: String(max), step: '1',
			value: val, 'class': 'lb-num', style: 'width:' + (width || '4.5em')
		});
	},

	card(title, body) {
		return E('section', { 'class': 'lb-card' }, [
			E('h3', {}, title),
			body
		]);
	},

	wanSelect(id) {
		const sel = E('select', { id: id, 'class': 'lb-sel' });
		this.wanChoices().forEach(n => sel.appendChild(E('option', { value: n }, n)));
		return sel;
	},

	renderPage() {
		const host = this._host || document.getElementById('lb-root');
		if (!host)
			return;
		const running = !!(this._st && Number(this._st.running) === 1);
		host.innerHTML = '';
		const wans = this._wans || [];
		const tracks = this.currentTracks();
		const stickyOn = (uci.get('mwan3', 'default', 'sticky') !== '0');
		const hashMode = uci.get('mwan3', 'globals', 'lede_lb_hash') || 'flow';
		const timeout = uci.get('mwan3', 'default', 'timeout') || '600';
		const firstIf = (uci.sections('mwan3', 'interface')[0] || {})['.name'];
		const interval = firstIf ? (uci.get('mwan3', firstIf, 'interval') || '5') : '5';
		const down = firstIf ? (uci.get('mwan3', firstIf, 'down') || '3') : '3';
		const up = firstIf ? (uci.get('mwan3', firstIf, 'up') || '3') : '3';

		const btns = [];
		if (running) {
			btns.push(E('button', {
				id: 'lb-stop', 'class': 'cbi-button cbi-button-reset',
				click: L.bind(this.stopLb, this)
			}, _('关闭负载')));
			btns.push(E('button', {
				id: 'lb-restart', 'class': 'cbi-button cbi-button-save',
				click: L.bind(this.restartLb, this)
			}, _('重启服务')));
		} else {
			btns.push(E('button', {
				id: 'lb-apply', 'class': 'cbi-button cbi-button-save',
				click: L.bind(this.applyLb, this)
			}, _('启用负载')));
		}
		btns.push(E('button', {
			id: 'lb-wipe', 'class': 'cbi-button cbi-button-remove',
			click: L.bind(this.wipeLb, this)
		}, _('删除负载')));

		host.appendChild(E('div', { 'class': 'lb-head' }, [
			E('div', { 'class': 'lb-title' }, [
				E('h2', {}, _('负载均衡')),
				E('span', { id: 'lb-status', 'class': 'lb-status' }),
				running ? E('span', {
					id: 'lb-hash-badge',
					'class': 'lb-status',
					style: 'margin-left:.75em;color:#2563eb'
				}, _('均衡') + '：' + (hashMode === 'ip' ? _('源IP') : _('连接'))) : ''
			]),
			E('div', { 'class': 'lb-actions' }, btns)
		]));
		if (running) {
			host.appendChild(E('div', { 'class': 'cbi-map-desc', style: 'margin:0 0 1em' }, [
				E('p', {}, _('下方「探测地址」区域的「均衡」决定默认流量如何分摊到各 WAN（连接=五元组哈希，更均匀；源IP=整 IP 固定一条线）。「分流规则」里手动添加的绑定不受此项影响。'))
			]));
		}
		this.paintBadge();

		const rows = wans.map(w => {
			const ck = E('input', { type: 'checkbox', id: 'lb-ck-' + w.name });
			ck.checked = !!w.checked;
			if (!running && !wans.some(x => x.checked) && wans.length >= 2)
				ck.checked = true;
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, ck),
				E('td', { 'class': 'td' }, w.name),
				E('td', { 'class': 'td' }, (w.proto || '') + (w.device ? ' / ' + w.device : '')),
				E('td', { 'class': 'td' }, w.up ? _('已连接') : _('未连接')),
				E('td', { 'class': 'td' }, this.numInput('lb-wt-' + w.name, w.weight || '1', 1, 100))
			]);
		});
		host.appendChild(this.card(_('宽带'), E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('使用')),
				E('th', { 'class': 'th' }, _('接口')),
				E('th', { 'class': 'th' }, _('协议 / 网卡')),
				E('th', { 'class': 'th' }, _('状态')),
				E('th', { 'class': 'th' }, _('权重'))
			]),
			...(rows.length ? rows : [
				E('tr', { 'class': 'tr' },
					E('td', { 'class': 'td', colspan: 5 }, _('没有可用的 WAN 接口')))
			])
		])));

		this._trackBox = E('div', { 'class': 'lb-tracks' });
		this._trackBox.appendChild(E('datalist', { id: 'lb-track-dl' }, [
			E('option', { value: '223.5.5.5' }),
			E('option', { value: '223.6.6.6' }),
			E('option', { value: '119.29.29.29' }),
			E('option', { value: '114.114.114.114' }),
			E('option', { value: '180.76.76.76' })
		]));
		const addBtn = E('button', {
			type: 'button',
			'class': 'lb-icon-btn lb-icon-add',
			title: _('添加'),
			click: ev => {
				ev.preventDefault();
				ev.stopPropagation();
				addTrack('');
			}
		}, '+');
		const addTrack = (val) => {
			const item = E('div', { 'class': 'lb-track' });
			item.appendChild(E('input', {
				type: 'text', value: val || '', placeholder: '223.5.5.5',
				'class': 'cbi-input-text', list: 'lb-track-dl'
			}));
			item.appendChild(E('button', {
				type: 'button',
				'class': 'lb-icon-btn',
				title: _('删除'),
				click: ev => {
					ev.preventDefault();
					ev.stopPropagation();
					item.remove();
				}
			}, '−'));
			this._trackBox.insertBefore(item, addBtn);
		};
		this._trackBox.appendChild(addBtn);
		(tracks.length ? tracks : DEF_TRACK).forEach(addTrack);
		const sticky = E('input', { type: 'checkbox', id: 'lb-sticky' });
		sticky.checked = stickyOn;
		const hashSel = E('select', { id: 'lb-hash', 'class': 'lb-sel' }, [
			E('option', { value: 'flow', selected: hashMode !== 'ip' }, _('连接（推荐）')),
			E('option', { value: 'ip', selected: hashMode === 'ip' }, _('源IP'))
		]);
		const syncHashUi = () => {
			const flow = hashSel.value !== 'ip';
			if (flow) {
				sticky.checked = false;
				sticky.disabled = true;
			} else {
				sticky.disabled = false;
			}
		};
		hashSel.addEventListener('change', syncHashUi);
		syncHashUi();
		host.appendChild(this.card(_('探测地址'), E('div', { 'class': 'lb-probe' }, [
			E('div', { 'class': 'lb-probe-l' }, this._trackBox),
			E('div', { 'class': 'lb-probe-r' }, [
				E('span', { 'class': 'lb-field' }, [
					E('span', { 'class': 'lb-k' }, _('间隔')),
					this.numInput('lb-interval', interval, 1, 60, '4em'),
					E('span', {}, _('秒'))
				]),
				E('span', { 'class': 'lb-field' }, [
					E('span', { 'class': 'lb-k' }, _('失败')),
					this.numInput('lb-down', down, 1, 20, '4em'),
					E('span', {}, _('次'))
				]),
				E('span', { 'class': 'lb-field' }, [
					E('span', { 'class': 'lb-k' }, _('成功')),
					this.numInput('lb-up', up, 1, 20, '4em'),
					E('span', {}, _('次'))
				]),
				E('span', { 'class': 'lb-field' }, [
					E('label', { 'class': 'lb-field' }, [sticky, ' ', _('粘滞')]),
					this.numInput('lb-timeout', timeout, 0, 86400, '6em'),
					E('span', {}, _('秒'))
				]),
				E('span', { 'class': 'lb-field' }, [
					E('span', { 'class': 'lb-k' }, _('均衡')),
					hashSel,
					E('span', { id: 'lb-hash-tip', style: 'margin-left:.5em;color:#64748b;font-size:.9em' },
						_('改后点「重启服务」生效'))
				])
			])
		])));

		const rules = uci.sections('mwan3', 'rule').map(s => this.ruleSummary(s));
		const kind = E('select', { id: 'lb-kind', 'class': 'lb-sel' }, [
			E('option', { value: 'ip' }, _('源IP')),
			E('option', { value: 'mac' }, _('源MAC')),
			E('option', { value: 'dest' }, _('目的IP'))
		]);
		const mid = E('span', { id: 'lb-mid', 'class': 'lb-mid' }, this.ruleMid('ip'));
		kind.addEventListener('change', () => {
			const k = kind.value;
			mid.innerHTML = '';
			mid.appendChild(this.ruleMid(k));
		});
		host.appendChild(this.card(_('分流规则'), E('div', {}, [
			E('div', { 'class': 'lb-rule-form' }, [
				kind,
				mid,
				E('span', { 'class': 'lb-arrow' }, '→'),
				this.wanSelect('lb-rule-wan'),
				E('button', {
					'class': 'cbi-button cbi-button-action',
					click: L.bind(this.extraAdd, this)
				}, _('添加'))
			]),
			E('table', { 'class': 'table' }, [
				E('tr', { 'class': 'tr table-titles' }, [
					E('th', { 'class': 'th' }, _('规则')),
					E('th', { 'class': 'th' }, _('匹配')),
					E('th', { 'class': 'th' }, _('策略')),
					E('th', { 'class': 'th' }, '')
				]),
				...(rules.length ? rules.map(r => E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td' }, r.auto ? _('基础') : r.name),
					E('td', { 'class': 'td' }, r.match),
					E('td', { 'class': 'td' }, r.pol),
					E('td', { 'class': 'td lb-op' }, r.auto ? '' : E('button', {
						'class': 'cbi-button cbi-button-remove',
						click: ev => this.extraDel(ev, r.name)
					}, _('删除')))
				])) : [
					E('tr', { 'class': 'tr' },
						E('td', { 'class': 'td', colspan: 4 }, _('暂无')))
				])
			])
		])));
	},

	render(data) {
		this._nets = data && data[2];
		this._st = data && data[3] && data[3].ok === false ? { running: 0 } : (data && data[3]) || { running: 0 };
		this._wans = this.collectWans(this._nets);
		this._host = E('div', { id: 'lb-root', 'class': 'lb-page' });
		this.renderPage();
		if (!this._poll) {
			this._poll = true;
			poll.add(L.bind(this.refreshStatus, this), 5);
		}
		return E('div', {}, [
			this._host,
			E('style', {}, `
				.lb-page { max-width: 1080px; }
				.lb-head { display:flex; justify-content:space-between; align-items:center;
					gap:12px; flex-wrap:wrap; margin:0 0 16px; }
				.lb-title { display:flex; align-items:baseline; gap:10px; }
				.lb-title h2 { margin:0; font-size:1.45em; }
				.lb-status { font-size:14px; font-weight:700; }
				.lb-actions { display:flex; gap:8px; flex-wrap:wrap; }
				.lb-card { background: var(--background-color-high, #fff);
					border: 1px solid var(--border-color-medium, rgba(127,127,127,.18));
					border-radius: 10px; padding: 14px 16px 16px; margin: 0 0 14px; }
				.lb-card h3 { margin: 0 0 12px; font-size: 15px; font-weight: 700; }
				.lb-card .table { margin: 0; }
				.lb-probe { display:flex; gap:28px; align-items:flex-start; }
				.lb-probe-l { flex: 1 1 auto; min-width: 0; max-width: 22em; }
				.lb-probe-r { flex: 0 0 14em; display:flex; flex-direction:column; gap:8px; }
				.lb-tracks { display:flex; flex-direction:column; gap:6px; align-items:flex-start; }
				.lb-track { display:flex; align-items:center; gap:6px; width:100%; }
				.lb-track input { flex:1; min-width:0; height:2em; }
				.lb-icon-btn {
					width: 1.9em; height: 1.9em; padding: 0; line-height: 1.7em;
					text-align: center; font-size: 16px; font-weight: 700;
					border: 1px solid var(--border-color-medium, #bbb);
					background: var(--background-color-high, #fff) !important;
					color: var(--text-color-high, #333) !important; cursor: pointer; border-radius: 4px;
				}
				.lb-rule-form {
					display: flex; flex-wrap: wrap; align-items: center; gap: 8px 10px;
					margin-bottom: 12px;
				}
				.lb-mid { display: inline-flex; min-width: 12em; }
				.lb-mid input, .lb-mid select { width: 100%; }
				.lb-arrow { font-weight: 700; opacity: 0.55; padding: 0 2px; }
				.lb-row { display:flex; flex-wrap:wrap; gap:10px 16px; align-items:center; margin: 0 0 10px; }
				.lb-row:last-child { margin-bottom: 0; }
				.lb-k { min-width: 3.2em; font-weight: 600; }
				.lb-field { display:inline-flex; align-items:center; gap:6px; white-space:nowrap; }
				.lb-ip { width: 10.5em; }
				.lb-mac { width: 13.5em; height: 2em; }
				.lb-num, .lb-ip { height: 2em; }
				.lb-page select.lb-sel {
					min-width: 9em; width: auto; max-width: none;
					height: 32px; line-height: 30px;
					padding: 0 2em 0 8px; box-sizing: border-box;
				}
				.lb-kind { min-width: 7.5em; }
				.lb-op { text-align: right; width: 5em; }
			`)
		]);
	}
});
