'use strict';
'require view';
'require form';
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
	load() {
		return Promise.all([
			uci.load('network'),
			uci.load('mwan3'),
			network.getNetworks(),
			fs.exec('/usr/libexec/lede-mwan3-setup', ['status']).then(r => this.parseJson(r)).catch(() => ({ running: 0 }))
		]).then(data => {
			if (ui.changes && typeof ui.changes.init === 'function')
				ui.changes.init();
			return data;
		});
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
			if (code === '127')
				return { ok: false, error: _('后端脚本未安装，请更新固件或联系管理员') };
			return { ok: false, error: raw.trim() || (code ? _('执行失败 (%s)').format(code) : _('没有返回')) };
		}
		try {
			return JSON.parse(raw.slice(i, j + 1));
		} catch (e) {
			return { ok: false, error: raw.trim() };
		}
	},

	isLbActive(st) {
		st = st || this._st || {};
		if (Number(st.running) !== 1)
			return false;
		const n = Number(st.enabled);
		if (!isNaN(n) && n >= 0)
			return n >= 2;
		return true;
	},

	hasEnoughWans() {
		return ((this._wans || []).length >= 2);
	},

	countEnabledMwanIfaces() {
		let n = 0;
		uci.sections('mwan3', 'interface').forEach(s => {
			if (uci.get('mwan3', s['.name'], 'enabled') === '1')
				n++;
		});
		return n;
	},

	uiShouldRun() {
		if (this.isLbActive(this._st))
			return true;
		return !!(this._wantEnable && this.countEnabledMwanIfaces() >= 2);
	},

	scheduleRunRefresh() {
		if (this._runPoll)
			return;
		this._runPoll = setTimeout(L.bind(function() {
			this._runPoll = null;
			this.refreshStatus();
		}, this), 2000);
	},

	forEachFooterAction(fn) {
		document.querySelectorAll('#view .cbi-page-actions').forEach(fn);
	},

	setFooterControl(el, can) {
		if (!el || el.id === 'lb-wipe')
			return;
		if (can) {
			el.removeAttribute('disabled');
			el.removeAttribute('aria-disabled');
		} else {
			el.setAttribute('disabled', '');
			el.setAttribute('aria-disabled', 'true');
		}
	},

	updateFooterActions() {
		const can = this.hasEnoughWans();
		this.forEachFooterAction(actions => {
			actions.classList.toggle('lb-actions-locked', !can);
			actions.querySelectorAll('button, .cbi-dropdown, .cbi-button').forEach(el => {
				this.setFooterControl(el, can);
			});
		});
		this.updateWipeButton();
	},

	scheduleFooterLock() {
		const tick = L.bind(this.updateFooterActions, this);
		tick();
		setTimeout(tick, 0);
		setTimeout(tick, 100);
	},

	updateWipeButton() {
		const btn = document.getElementById('lb-wipe');
		if (!btn)
			return;
		btn.disabled = !this.hasEnoughWans() || !this.isLbActive();
	},

	paintRunStatus() {
		const badge = document.getElementById('lb-run-status');
		if (!badge)
			return;
		if (!this.hasEnoughWans()) {
			badge.textContent = _('不可用');
			badge.style.color = '#9ca3af';
			badge.setAttribute('title', _('系统中 WAN 口少于 2 个，无法启用多线负载'));
			this.updateWipeButton();
			return;
		}
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
		if (this.uiShouldRun()) {
			if (this.isLbActive(this._st))
				this._wantEnable = false;
			badge.textContent = _('运行中');
			badge.style.color = '#16a34a';
			badge.removeAttribute('title');
			this.updateWipeButton();
			return;
		}
		if (this._wantEnable && this.countEnabledMwanIfaces() >= 2) {
			badge.textContent = _('启动中......');
			badge.style.color = '#d97706';
			badge.removeAttribute('title');
			this.scheduleRunRefresh();
			this.updateWipeButton();
			return;
		}
		badge.textContent = _('关闭');
		badge.style.color = '#dc2626';
		if (this._st && Number(this._st.service) === 1 && Number(this._st.enabled) < 2)
			badge.setAttribute('title', _('mwan3 服务在运行，但未配置多线负载'));
		else
			badge.removeAttribute('title');
		this.updateWipeButton();
	},

	refreshStatus() {
		return fs.exec('/usr/libexec/lede-mwan3-setup', ['status']).then(r => {
			this._st = this.parseJson(r);
			this.paintRunStatus();
			return this._st;
		}).catch(() => this._st);
	},

	waitRunning(want, tries) {
		const self = this;
		function step() {
			return self.refreshStatus().then(st => {
				const on = self.isLbActive(st);
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
		return uci.load('mwan3').then(() => {
			this._wans = this.collectWans(this._nets);
			return this.refreshStatus().then(() => {
				if (this._host)
					this.renderPageContent(this._host);
				this.paintRunStatus();
				const hashSel = document.getElementById('lb-hash-mode');
				if (hashSel) {
					hashSel.value = uci.get('mwan3', 'globals', 'lede_lb_hash') === 'ip' ? 'ip' : 'flow';
				}
				this.syncStickyControls();
				if (ui.changes && typeof ui.changes.init === 'function')
					ui.changes.init();
			});
		});
	},

	ok(msg) {
		ui.addNotification(null, E('p', {}, msg), 'success');
	},

	fail(e, fallback) {
		ui.addNotification(null, E('p', {}, (e && e.message) || fallback), 'error');
	},

	bumpDirty() {
		if (ui.changes && typeof ui.changes.init === 'function')
			ui.changes.init();
		const el = this._mapNode && this._mapNode.querySelector('[data-name="lede_cfg_rev"] input');
		if (el) {
			el.value = String(Date.now());
			el.dispatchEvent(new Event('change', { bubbles: true }));
		}
	},

	bindDirty(root) {
		if (!root)
			return;
		const self = this;
		root.querySelectorAll('input,select').forEach(el => {
			el.addEventListener('change', () => self.bumpDirty());
			el.addEventListener('input', () => self.bumpDirty());
		});
	},

	readForm() {
		const rows = this._wans || [];
		const ifaces = [];
		rows.forEach(w => {
			const ck = document.getElementById('lb-ck-' + w.name);
			if (!ck || !ck.checked)
				return;
			const wt = document.getElementById('lb-wt-' + w.name);
			let v = Number(wt && wt.value);
			if (!(v >= 1 && v <= 100))
				v = 1;
			ifaces.push({ name: w.name, weight: v });
		});
		const tracks = [];
		if (this._trackBox)
			(this._trackBox.querySelectorAll('input') || []).forEach(inp => {
				const v = String(inp.value || '').trim();
				if (v)
					tracks.push(v);
			});
		const hashEl = document.getElementById('lb-hash-mode');
		const hashMode = hashEl
			? (hashEl.value === 'ip' ? 'ip' : 'flow')
			: (uci.get('mwan3', 'globals', 'lede_lb_hash') === 'ip' ? 'ip' : 'flow');
		return {
			enabled: !!(document.getElementById('lb-enable') || {}).checked,
			ifaces,
			tracks: tracks.length ? tracks : DEF_TRACK.slice(),
			sticky: !!(document.getElementById('lb-sticky') || {}).checked,
			hashMode: hashMode === 'ip' ? 'ip' : 'flow',
			timeout: String((document.getElementById('lb-timeout') || {}).value || '600'),
			interval: String((document.getElementById('lb-interval') || {}).value || '5'),
			down: String((document.getElementById('lb-down') || {}).value || '3'),
			up: String((document.getElementById('lb-up') || {}).value || '3')
		};
	},

	commitProbeToUci(f) {
		f = f || this.readForm();
		uci.set('mwan3', 'globals', 'lede_lb_hash', f.hashMode === 'ip' ? 'ip' : 'flow');
		uci.set('mwan3', 'default', 'sticky', (f.sticky && f.hashMode === 'ip') ? '1' : '0');
		uci.set('mwan3', 'default', 'timeout', f.timeout);
		uci.sections('mwan3', 'interface').forEach(s => {
			const name = s['.name'];
			uci.set('mwan3', name, 'interval', f.interval);
			uci.set('mwan3', name, 'down', f.down);
			uci.set('mwan3', name, 'up', f.up);
		});
	},

	buildApplyArgs(f) {
		const args = ['apply'];
		f.ifaces.forEach(w => {
			args.push('--iface', w.name, '--weight', String(w.weight));
		});
		f.tracks.forEach(t => args.push('--track', t));
		args.push('--sticky', f.sticky && f.hashMode === 'ip' ? '1' : '0');
		args.push('--hash-mode', f.hashMode === 'ip' ? 'ip' : 'flow');
		args.push('--timeout', f.timeout);
		args.push('--interval', f.interval);
		args.push('--down', f.down);
		args.push('--up', f.up);
		return args;
	},

	applyBackend() {
		if (!this.hasEnoughWans())
			throw new Error(_('系统中 WAN 口少于 2 个，无法配置多线负载'));

		const f = this.readForm();
		const running = this.isLbActive(this._st);

		if (!f.enabled) {
			this._wantEnable = false;
			this._phase = null;
			this._phaseErr = '';
			if (!running)
				return Promise.resolve();
			return fs.exec('/usr/libexec/lede-mwan3-setup', ['stop']).then(r => {
				const j = this.parseJson(r);
				if (!j.ok)
					throw new Error(j.error || _('关闭失败'));
				return this.waitRunning(false, 20);
			});
		}

		if (f.ifaces.length < 2)
			throw new Error(_('请至少选择两条 WAN 后再启用多线负载'));

		this._wantEnable = true;
		this._phase = 'starting';
		this._phaseErr = '';
		this.paintRunStatus();
		return fs.exec('/usr/libexec/lede-mwan3-setup', this.buildApplyArgs(f)).then(r => {
			const j = this.parseJson(r);
			if (!j.ok)
				throw new Error(j.error || _('应用失败'));
			return this.waitRunning(true, 45).then(st => {
				if (!this.isLbActive(st) && f.ifaces.length >= 2) {
					this._st = Object.assign({}, st || {}, {
						ok: true,
						running: 0,
						service: Number(st && st.service) || 0,
						enabled: f.ifaces.length
					});
				}
				this._phase = null;
				this._phaseErr = '';
			});
		}).catch(e => {
			this._wantEnable = false;
			this._phase = 'start_fail';
			this._phaseErr = (e && e.message) || _('应用失败');
			throw e;
		});
	},

	refreshStatusUntilStable() {
		const self = this;
		function step(left) {
			return self.refreshStatus().then(st => {
				if (self.isLbActive(st) || !self._wantEnable || left <= 0)
					return st;
				return new Promise(ok => setTimeout(ok, 1000)).then(() => step(left - 1));
			});
		}
		return step(20);
	},

	handleSave(ev) {
		if (!this.hasEnoughWans()) {
			this.fail(null, _('系统中 WAN 口少于 2 个，无法配置多线负载'));
			return Promise.reject(new Error('wan'));
		}
		const self = this;
		return this.map.save().then(function() {
			self.commitProbeToUci();
			return uci.save();
		});
	},

	handleSaveApply(ev, mode) {
		const self = this;
		return this.handleSave(ev).then(function() {
			return ui.changes.apply(mode == '0');
		}).then(function() {
			return self.applyBackend();
		}).then(function() {
			return self.refreshStatusUntilStable();
		}).then(function() {
			return self.afterChange();
		}).catch(function(e) {
			self.fail(e, _('保存并应用失败'));
			return self.afterChange();
		});
	},

	handleReset(ev) {
		if (!this.hasEnoughWans()) {
			this.fail(null, _('系统中 WAN 口少于 2 个，无法配置多线负载'));
			return Promise.reject(new Error('wan'));
		}
		return this.map.reset().then(() => this.afterChange());
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
				if (this.isLbActive(st))
					throw new Error(_('已发出关闭，但服务仍在运行'));
				this.ok(_('已关闭'));
				return this.afterChange();
			});
		}).catch(e => this.fail(e, _('关闭失败'))).finally(() => {
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
		if (!this.hasEnoughWans()) {
			this.fail(null, _('系统中 WAN 口少于 2 个，无法配置多线负载'));
			return;
		}
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
		if (!this.hasEnoughWans()) {
			this.fail(null, _('系统中 WAN 口少于 2 个，无法配置多线负载'));
			return;
		}
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
		if (!this.hasEnoughWans())
			return;
		if (!this.isLbActive(this._st))
			return;
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

	modCard(title, body, extraClass) {
		const cls = 'lb-card lb-mod-card' + (extraClass ? (' ' + extraClass) : '');
		const row = E('div', { 'class': 'lb-mod-grid' + (title ? '' : ' lb-mod-grid-only') });
		if (title)
			row.appendChild(E('h3', { 'class': 'lb-mod-title' }, title));
		row.appendChild(E('div', { 'class': 'lb-mod-body' }, body));
		return E('section', { 'class': cls }, [row]);
	},

	sectionCard(title, body) {
		return E('section', { 'class': 'lb-card lb-section-card' }, [
			E('div', { 'class': 'lb-section-grid' }, [
				E('h3', { 'class': 'lb-section-title' }, title),
				E('div', { 'class': 'lb-section-body' }, body)
			])
		]);
	},

	wanSelect(id) {
		const sel = E('select', { id: id, 'class': 'lb-sel' });
		this.wanChoices().forEach(n => sel.appendChild(E('option', { value: n }, n)));
		return sel;
	},

	hashSelect(val) {
		const mode = (val === 'ip') ? 'ip' : 'flow';
		const sel = E('select', {
			id: 'lb-hash-mode',
			'class': 'lb-sel lb-hash-sel',
			style: 'width:240px;min-width:240px;max-width:240px;box-sizing:border-box;'
		}, [
			E('option', { value: 'flow' }, _('连接数')),
			E('option', { value: 'ip' }, _('源IP'))
		]);
		sel.value = mode;
		sel.addEventListener('change', L.bind(function() {
			this.bumpDirty();
			this.syncStickyControls();
		}, this));
		const wrap = E('div', { 'class': 'lb-hash-sel-wrap' }, sel);
		wrap._hashSel = sel;
		return wrap;
	},

	stickyDefaultOn() {
		const stickyUci = uci.get('mwan3', 'default', 'sticky');
		return !(stickyUci === '0' || stickyUci === false);
	},

	syncStickyControls() {
		const can = this.hasEnoughWans();
		const modeEl = document.getElementById('lb-hash-mode');
		const stickyEl = document.getElementById('lb-sticky');
		if (!stickyEl)
			return;
		const ip = !!(modeEl && modeEl.value === 'ip');
		stickyEl.disabled = !can || !ip;
		if (!ip)
			stickyEl.checked = false;
		if (!can)
			stickyEl.setAttribute('title', _('系统中 WAN 口少于 2 个，无法配置'));
		else if (!ip)
			stickyEl.setAttribute('title', _('粘滞仅适用于「源IP」负载模式'));
		else
			stickyEl.removeAttribute('title');
	},

	addFooter() {
		const footer = this.super('addFooter', []);
		const actions = footer.querySelector('.cbi-page-actions');
		if (actions && !actions.querySelector('#lb-wipe')) {
			actions.appendChild(E('button', {
				type: 'button',
				id: 'lb-wipe',
				'class': 'cbi-button cbi-button-remove important',
				disabled: true,
				click: L.bind(this.wipeLb, this)
			}, _('删除负载')));
		}
		this.scheduleFooterLock();
		return footer;
	},

	renderPageContent(host) {
		if (!host)
			return;
		const canConfig = this.hasEnoughWans();
		const running = canConfig && this.uiShouldRun();
		host.innerHTML = '';
		const body = E('div', { 'class': 'lb-page-body' });
		if (!canConfig) {
			host.appendChild(E('div', { 'class': 'cbi-map-desc lb-wan-hint' }, [
				E('p', {}, _('系统中 WAN 口少于 2 个，多线负载暂不可用，请先配置第二条 WAN。'))
			]));
		}
		host.appendChild(body);
		const wans = this._wans || [];
		const tracks = this.currentTracks();
		const hashMode = uci.get('mwan3', 'globals', 'lede_lb_hash') === 'ip' ? 'ip' : 'flow';
		const hashSelWrap = this.hashSelect(hashMode);
		const sticky = E('input', { type: 'checkbox', id: 'lb-sticky' });
		sticky.checked = (hashMode === 'ip') && this.stickyDefaultOn();
		sticky.addEventListener('change', L.bind(this.bumpDirty, this));
		const timeout = uci.get('mwan3', 'default', 'timeout') || '600';
		const firstIf = (uci.sections('mwan3', 'interface')[0] || {})['.name'];
		const interval = firstIf ? (uci.get('mwan3', firstIf, 'interval') || '5') : '5';
		const down = firstIf ? (uci.get('mwan3', firstIf, 'down') || '3') : '3';
		const up = firstIf ? (uci.get('mwan3', firstIf, 'up') || '3') : '3';

		const enableCk = E('input', { type: 'checkbox', id: 'lb-enable' });
		enableCk.checked = running;
		enableCk.disabled = !canConfig;
		enableCk.addEventListener('change', L.bind(this.bumpDirty, this));

		body.appendChild(E('div', { 'class': 'lb-top-mods' }, [
			this.modCard('', E('div', { 'class': 'lb-run-line' }, [
				E('div', { 'class': 'lb-enable-group' }, [
					E('span', { 'class': 'lb-enable-text' }, _('多线负载')),
					enableCk
				]),
				E('span', { id: 'lb-run-status', 'class': 'lb-status' })
			]), 'lb-mod-run'),
			this.modCard(_('负载模式'), E('div', { 'class': 'lb-hash-row' }, [
				hashSelWrap,
				E('div', { 'class': 'lb-sticky-field' }, [
					E('div', { 'class': 'lb-sticky-ck' }, [
						sticky,
						E('label', { 'class': 'lb-sticky-lbl', 'for': 'lb-sticky' }, _('粘滞'))
					]),
					this.numInput('lb-timeout', timeout, 0, 86400, '6em'),
					E('span', { 'class': 'lb-sticky-unit' }, _('秒'))
				])
			]), 'lb-mod-hash lb-mod-hash-row')
		]));

		if (running) {
			body.appendChild(E('div', { 'class': 'cbi-map-desc', style: 'margin:0 0 1em' }, [
				E('p', {}, _('下方「探测地址」用于检测各 WAN 是否在线。「分流规则」里手动添加的绑定不受负载模式影响。'))
			]));
		}

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
		body.appendChild(this.card(_('宽带'), E('table', { 'class': 'table' }, [
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

		body.appendChild(this.sectionCard(_('探测地址'), E('div', { 'class': 'lb-probe' }, [
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
				])
			])
		])));

		this.syncStickyControls();

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
		body.appendChild(this.sectionCard(_('分流规则'), E('div', {}, [
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
			E('div', { 'class': 'lb-rule-table-wrap' }, [
				E('table', { 'class': 'table lb-rule-table' }, [
					E('tr', { 'class': 'tr table-titles' }, [
						E('th', { 'class': 'th lb-rule-col', style: 'text-align:left' }, _('规则')),
						E('th', { 'class': 'th lb-rule-col', style: 'text-align:left' }, _('匹配')),
						E('th', { 'class': 'th lb-rule-col', style: 'text-align:left' }, _('策略')),
						E('th', { 'class': 'th lb-op' }, '')
					]),
					...(rules.length ? rules.map(r => E('tr', { 'class': 'tr' }, [
						E('td', { 'class': 'td lb-rule-col', style: 'text-align:left' }, r.auto ? _('基础') : r.name),
						E('td', { 'class': 'td lb-rule-col', style: 'text-align:left' }, r.match),
						E('td', { 'class': 'td lb-rule-col', style: 'text-align:left' }, r.pol),
						E('td', { 'class': 'td lb-op' }, r.auto ? '' : E('button', {
							'class': 'cbi-button cbi-button-remove',
							click: ev => this.extraDel(ev, r.name)
						}, _('删除')))
					])) : [
						E('tr', { 'class': 'tr' },
							E('td', {
								'class': 'td lb-rule-col',
								colspan: 4,
								style: 'text-align:left'
							}, _('暂无')))
					])
				])
			])
		])));

		if (!canConfig)
			body.classList.add('lb-root-disabled');
		this.bindDirty(body);
		this.scheduleFooterLock();
	},

	render(data) {
		this._lastData = data;
		this._nets = data && data[2];
		this._st = data && data[3] && data[3].ok === false ? { running: 0 } : (data && data[3]) || { running: 0 };
		this._wans = this.collectWans(this._nets);

		const m = new form.Map('mwan3', _('多线负载'));
		this.map = m;

		const sg = m.section(form.NamedSection, 'globals', 'globals');
		sg.anonymous = true;
		sg.addremove = false;

		const oRev = sg.option(form.Value, 'lede_cfg_rev', ' ');
		oRev.datatype = 'uinteger';
		oRev.cfgvalue = () => '0';
		oRev.write = function() {};
		oRev.rmempty = true;

		const oBody = sg.option(form.DummyValue, 'lede_lb_body', null);
		oBody.cfgvalue = function() { return ''; };
		oBody.write = function() {};
		oBody.render = L.bind(function() {
			const host = E('div', { id: 'lb-root', 'class': 'lb-page' });
			this._host = host;
			return host;
		}, this);

		return m.render().then(L.bind(function(mapNode) {
			this._mapNode = mapNode;
			const title = mapNode.querySelector('.cbi-map > h2');
			if (title)
				title.remove();
			this.renderPageContent(this._host);
			this.paintRunStatus();
			this.scheduleFooterLock();
			if (!this._poll) {
				this._poll = true;
				poll.add(L.bind(this.refreshStatus, this), 5);
			}
			const wrap = E('div', { 'class': 'lb-wrap lb-page' }, mapNode);
			wrap.appendChild(E('style', {}, `
				.lb-wrap { width: 100%; max-width: none; }
				.lb-wrap .cbi-map,
				.lb-wrap .cbi-section,
				.lb-wrap .cbi-section-node { max-width: none !important; width: 100% !important; }
				.lb-wrap .cbi-section {
					border: none; padding: 0; margin: 0; background: transparent;
					box-shadow: none;
				}
				.lb-wrap .cbi-section > h3,
				.lb-wrap .cbi-section > .cbi-section-desc { display: none !important; }
				.lb-wrap [data-name="lede_cfg_rev"] { display: none !important; }
				.lb-wrap [data-name="lede_lb_body"] .cbi-value-title { display: none !important; }
				.lb-wrap [data-name="lede_lb_body"] .cbi-value-field { width: 100%; max-width: none; padding: 0; }
				.lb-top-mods {
					display: flex; flex-direction: column;
					gap: 14px; width: 100%; margin: 0 0 14px;
				}
				.lb-top-mods .lb-mod-card {
					width: 100%; margin: 0;
					padding: 22px 26px; min-height: 78px;
					box-sizing: border-box;
				}
				.lb-mod-grid {
					display: grid;
					grid-template-columns: auto 1fr;
					grid-template-rows: auto;
					column-gap: 20px;
					align-items: baseline;
				}
				.lb-mod-title {
					grid-column: 1; grid-row: 1;
					margin: 0; padding: 0;
					font-size: 15px; font-weight: 700;
					line-height: 1.4; white-space: nowrap;
					color: var(--text-color-high, #333);
				}
				.lb-mod-body {
					grid-column: 2; grid-row: 1;
					text-align: left; min-width: 0;
					line-height: 1.4;
				}
				.lb-mod-grid-only { grid-template-columns: 1fr; }
				.lb-mod-grid-only .lb-mod-body { grid-column: 1; }
				.lb-mod-run .lb-run-line {
					display: flex; flex-wrap: nowrap; align-items: center;
					gap: 50px; min-height: 32px;
				}
				.lb-mod-run .lb-enable-group {
					display: inline-flex; align-items: center;
					gap: 10px; height: 32px; white-space: nowrap;
				}
				.lb-mod-run .lb-enable-text,
				.lb-mod-run .lb-status,
				.lb-mod-run #lb-enable {
					box-sizing: border-box;
				}
				.lb-mod-run .lb-enable-text {
					display: inline-flex; align-items: center;
					height: 32px; margin: 0;
					font-size: 15px; font-weight: 700; line-height: 32px;
					white-space: nowrap;
					color: var(--text-color-high, #333);
				}
				.lb-mod-run #lb-enable {
					margin: 0; width: 16px; height: 16px;
					flex: 0 0 16px; cursor: pointer;
				}
				.lb-mod-run .lb-status {
					display: inline-flex; align-items: center;
					height: 32px; margin: 0;
					font-size: 14px; font-weight: 600; line-height: 32px;
					white-space: nowrap;
				}
				#lb-wipe:disabled {
					opacity: 0.45; cursor: not-allowed; pointer-events: none;
				}
				.lb-wan-hint {
					margin: 0 0 14px;
					color: var(--text-color-high, #333);
				}
				.lb-wan-hint p {
					margin: 0; font-size: 14px; line-height: 1.5;
				}
				.lb-root-disabled {
					opacity: 0.55; pointer-events: none; user-select: none;
				}
				.lb-root-disabled input,
				.lb-root-disabled select,
				.lb-root-disabled button,
				.lb-root-disabled textarea {
					cursor: not-allowed !important;
				}
				.lb-wrap .cbi-map > .cbi-page-actions {
					display: none !important;
				}
				#view .cbi-page-actions.lb-actions-locked {
					opacity: 0.45; cursor: not-allowed;
					pointer-events: none !important;
				}
				#view .cbi-page-actions.lb-actions-locked .cbi-dropdown,
				#view .cbi-page-actions.lb-actions-locked button,
				#view .cbi-page-actions button:disabled,
				#view .cbi-page-actions .cbi-dropdown[disabled] {
					opacity: 0.45; cursor: not-allowed; pointer-events: none !important;
				}
				.lb-mod-hash-row .lb-mod-grid { align-items: baseline; }
				.lb-hash-row {
					display: flex; flex-wrap: wrap;
					align-items: center; gap: 12px 18px;
					line-height: 1.4;
				}
				.lb-sticky-field {
					display: inline-flex; align-items: center;
					gap: 10px 14px; margin-left: 80px;
					height: 38px; white-space: nowrap;
				}
				.lb-sticky-ck {
					display: inline-flex; align-items: center;
					gap: 8px; height: 38px;
				}
				#lb-sticky {
					margin: 0; width: 16px; height: 16px;
					flex: 0 0 16px; cursor: pointer;
					vertical-align: middle;
				}
				.lb-sticky-lbl {
					display: inline-flex; align-items: center;
					margin: 0; padding: 0; height: 38px;
					line-height: 38px; font-size: 14px;
					font-weight: 600; cursor: pointer;
					color: var(--text-color-high, #333);
				}
				.lb-sticky-unit {
					display: inline-flex; align-items: center;
					height: 38px; line-height: 38px;
				}
				#lb-sticky:disabled + .lb-sticky-lbl {
					opacity: 0.55; cursor: not-allowed;
				}
				.lb-hash-sel-wrap {
					width: 240px; flex: 0 0 240px; max-width: 240px;
					overflow: visible;
				}
				#lb-hash-mode,
				.lb-wrap select.lb-sel.lb-hash-sel {
					width: 240px !important; min-width: 240px !important;
					max-width: 240px !important;
					height: auto; min-height: 38px;
					line-height: 1.4; padding: 8px 2em 8px 10px;
					font-size: 14px; flex: 0 0 auto;
					vertical-align: middle;
					box-sizing: border-box;
					overflow: visible;
				}
				.lb-section-grid {
					display: flex; flex-direction: column;
					align-items: flex-start; width: 100%;
				}
				.lb-section-title {
					width: 100%;
					margin: 0 0 12px; padding: 0;
					font-size: 15px; font-weight: 700;
					line-height: 1.4;
				}
				.lb-section-body {
					width: 100%; min-width: 0;
					padding-left: 150px; box-sizing: border-box;
				}
				.lb-section-card { padding: 18px 20px 20px; }
				#view .cbi-page-actions {
					display: flex; flex-wrap: wrap; justify-content: flex-end; gap: .5em;
					width: 100%; max-width: none;
				}
				#view .cbi-page-actions #lb-wipe {
					display: inline-block !important; visibility: visible !important;
				}
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
				.lb-section-body .lb-rule-table-wrap {
					margin-left: -150px;
					width: calc(100% + 150px);
					max-width: calc(100% + 150px);
				}
				.lb-wrap table.lb-rule-table {
					width: 100% !important;
					display: table !important;
					table-layout: fixed;
				}
				.lb-wrap table.lb-rule-table > .tr {
					display: table-row !important;
					width: 100%;
				}
				.lb-wrap table.lb-rule-table .th,
				.lb-wrap table.lb-rule-table .td {
					display: table-cell !important;
				}
				.lb-wrap table.lb-rule-table .lb-rule-col {
					text-align: left !important;
				}
				.lb-wrap table.lb-rule-table .th:nth-child(1),
				.lb-wrap table.lb-rule-table .td:nth-child(1) { width: 16%; }
				.lb-wrap table.lb-rule-table .th:nth-child(2),
				.lb-wrap table.lb-rule-table .td:nth-child(2) { width: 44%; }
				.lb-wrap table.lb-rule-table .th:nth-child(3),
				.lb-wrap table.lb-rule-table .td:nth-child(3) { width: 28%; }
				.lb-wrap table.lb-rule-table .th:nth-child(4),
				.lb-wrap table.lb-rule-table .td:nth-child(4) { width: 12%; }
				.lb-mid { display: inline-flex; min-width: 12em; }
				.lb-mid input, .lb-mid select { width: 100%; }
				.lb-arrow { font-weight: 700; opacity: 0.55; padding: 0 2px; }
				.lb-k { min-width: 3.2em; font-weight: 600; }
				.lb-field { display:inline-flex; align-items:center; gap:6px; white-space:nowrap; }
				.lb-ip { width: 10.5em; }
				.lb-mac { width: 13.5em; height: 2em; }
				.lb-num, .lb-ip { height: 2em; }
				.lb-wrap select.lb-sel:not(.lb-hash-sel) {
					min-width: 9em; width: auto; max-width: none;
					height: 32px; line-height: 30px;
					padding: 0 2em 0 8px; box-sizing: border-box;
				}
				.lb-op { text-align: right; width: 5em; }
			`));
			return wrap;
		}, this));
	}
});
