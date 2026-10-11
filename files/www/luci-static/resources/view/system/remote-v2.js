'use strict';
'require view';
'require form';
'require fs';
'require uci';
'require ui';

function parseJsonStatus(res, fallback) {
	var text = String((res && (res.stdout || res.stderr)) || '').trim();
	var i = text.indexOf('{');
	if (i >= 0)
		text = text.slice(i);
	try {
		return JSON.parse(text);
	}
	catch (e) {
		return fallback;
	}
}

function stripMapChrome(node, stripActions) {
	if (!node)
		return node;
	node.querySelectorAll('h2, .cbi-map-descr').forEach(function(el) {
		el.parentNode.removeChild(el);
	});
	if (stripActions) {
		node.querySelectorAll('.cbi-page-actions').forEach(function(el) {
			el.parentNode.removeChild(el);
		});
	}
	return node;
}

var TAB_STORAGE_KEY = 'lede.remote.activeTab';

function readActiveTab() {
	var id;
	try {
		id = sessionStorage.getItem(TAB_STORAGE_KEY);
		if (id === 'center' || id === 'wan')
			return id;
	} catch (e) {}
	if (location.hash === '#tab-center')
		return 'center';
	return 'wan';
}

function persistActiveTab(id) {
	try {
		sessionStorage.setItem(TAB_STORAGE_KEY, id);
	} catch (e) {}
}

function tabItem(view, id, label, active) {
	return E('li', {
		'class': (active ? 'cbi-tab cbi-tab-active ' : 'cbi-tab ') + 'lede-remote-tab lede-remote-tab--' + id,
		'data-tab': id,
		'click': ui.createHandlerFn(view, function(ev) {
			ev.preventDefault();
			view._activeTab = id;
			persistActiveTab(id);
			view._syncTabs();
		})
	}, E('a', { href: '#tab-' + id }, label));
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('lede-remote'),
			uci.load('lede-center'),
			fs.exec('/usr/libexec/lede-wan-https', ['status']),
			fs.exec('/usr/libexec/lede-center-frpc', ['status'])
		]);
	},

	_syncTabs: function() {
		var id = this._activeTab || 'wan';
		if (!this._tabMenu || !this._panes)
			return;
		this._tabMenu.querySelectorAll('li').forEach(function(li) {
			li.classList.toggle('cbi-tab-active', li.getAttribute('data-tab') === id);
		});
		this._panes.querySelectorAll('[data-pane]').forEach(function(p) {
			p.style.display = p.getAttribute('data-pane') === id ? '' : 'none';
		});
	},

	_buildRemoteMap: function(st) {
		var m = new form.Map('lede-remote');
		var s = m.section(form.NamedSection, 'main', 'https');
		s.addremove = false;

		var o = s.option(form.DummyValue, '_state', _('当前状态'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			return st.enabled ? _('已开启') : _('已关闭');
		};

		o = s.option(form.DummyValue, '_fw', _('防火墙规则'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			var p = String(st.port || uci.get('lede-remote', 'main', 'port') || '10443');
			if (!st.firewall)
				return _('未添加');
			return '%s　%s → %s　%s/%s　%s'.format(
				st.rule || 'Allow-WAN-HTTPS',
				st.src || 'wan',
				_('本机'),
				st.proto || 'tcp',
				p,
				st.target || 'ACCEPT'
			);
		};

		o = s.option(form.DummyValue, '_listen', _('监听'));
		o.cfgvalue = function() {
			var p = String(st.port || uci.get('lede-remote', 'main', 'port') || '10443');
			if (st.listen)
				return '0.0.0.0:%s'.format(p);
			if (st.nginx)
				return _('配置已生成，等待监听');
			return _('未监听');
		};

		o = s.option(form.Flag, 'enabled', _('允许外网访问管理页'));
		o.rmempty = false;
		o.default = '0';

		o = s.option(form.Value, 'port', _('外网端口'));
		o.datatype = 'range(1024,65535)';
		o.default = '10443';
		o.rmempty = false;

		o = s.option(form.Flag, 'scan_enabled', _('记录并聚合扫描行为'),
			_('记录 WAN 管理端口的访问；同一来源在时间窗口内反复访问不存在的路径或异常请求时，只生成一条聚合报警。'));
		o.default = o.enabled;
		o.rmempty = false;

		o = s.option(form.Flag, 'auto_ban', _('达到阈值后临时封禁'),
			_('按来源 IP 临时封禁，不要求固定 IP；到期自动解封。局域网管理不受影响。'));
		o.default = o.enabled;
		o.rmempty = false;
		o.depends('scan_enabled', '1');

		o = s.option(form.Value, 'scan_window_min', _('扫描统计窗口（分钟）'));
		o.datatype = 'range(1,60)';
		o.default = '5';
		o.rmempty = false;
		o.depends('scan_enabled', '1');

		o = s.option(form.Value, 'scan_alert_n', _('扫描报警阈值'));
		o.datatype = 'range(3,1000)';
		o.default = '10';
		o.rmempty = false;
		o.depends('scan_enabled', '1');

		o = s.option(form.Value, 'scan_ban_n', _('扫描封禁阈值'));
		o.datatype = 'range(5,5000)';
		o.default = '30';
		o.rmempty = false;
		o.depends('auto_ban', '1');

		o = s.option(form.Value, 'login_window_min', _('登录尝试统计窗口（分钟）'));
		o.datatype = 'range(1,60)';
		o.default = '10';
		o.rmempty = false;
		o.depends('scan_enabled', '1');

		o = s.option(form.Value, 'login_ban_n', _('登录失败封禁阈值'),
			_('仅统计 session.login 且 HTTP 401/403 的失败次数；成功登录不计入。'));
		o.datatype = 'range(3,100)';
		o.default = '8';
		o.rmempty = false;
		o.depends('auto_ban', '1');

		o = s.option(form.Value, 'ban_minutes', _('临时封禁时长（分钟）'));
		o.datatype = 'range(1,1440)';
		o.default = '30';
		o.rmempty = false;
		o.depends('auto_ban', '1');

		return m;
	},

	_buildCenterMap: function(st) {
		var viewRef = this;
		var m = new form.Map('lede-center');
		var s = m.section(form.NamedSection, 'main', 'frpc');
		s.addremove = false;

		var o = s.option(form.DummyValue, '_state', _('隧道状态'));
		o.rawhtml = true;
		o.cfgvalue = function() {
			if (!st.enabled)
				return _('未启用');
			if (st.running)
				return E('span', {}, [
					_('已连接（'),
					E('span', { 'class': 'lede-remote-frpc-state--up' }, _('frpc 运行中')),
					_('）')
				]);
			if (st.config || st.uci_ok)
				return E('span', { 'class': 'lede-remote-frpc-state--down' },
					_('未连接：frpc 未运行。请「保存并应用」，或 SSH：/usr/libexec/lede-center-frpc apply'));
			return _('配置不完整（请填写站点 ID、Token、映射端口）');
		};

		o = s.option(form.Flag, 'enabled', _('启用区域接入'));
		o.rmempty = false;
		o.default = '0';

		o = s.option(form.Value, 'site_id', _('站点 ID'),
			_('全局唯一，仅字母、数字、下划线、连字符；用于 frp 代理名。'));
		o.datatype = 'rangelength(2,32)';
		o.rmempty = true;
		o.placeholder = 'shop-gz-01';
		o.depends('enabled', '1');

		o = s.option(form.Value, 'server', _('中心地址'));
		o.default = 'center.123.gd.cn';
		o.rmempty = true;
		o.depends('enabled', '1');

		o = s.option(form.Value, 'port', _('中心 frps 端口'));
		o.datatype = 'port';
		o.default = '18007';
		o.rmempty = true;
		o.depends('enabled', '1');

		o = s.option(form.Value, 'token', _('frps 认证 Token'));
		o.password = true;
		o.rmempty = true;
		o.depends('enabled', '1');

		o = s.option(form.Value, 'remote_port_luci', _('中心映射端口（LuCI）'),
			_('在中心机上为该站独占的 TCP 端口，例如 19001、19002。'));
		o.datatype = 'range(1024,65535)';
		o.rmempty = true;
		o.depends('enabled', '1');

		o = s.option(form.Value, 'remote_port_ssh', _('中心映射端口（SSH，可选）'),
			_('填 0 表示不映射 SSH。'));
		o.datatype = 'range(0,65535)';
		o.default = '0';
		o.rmempty = false;

		o = s.option(form.Value, 'local_luci_port', _('本机 LuCI 端口'));
		o.datatype = 'port';
		o.default = '443';
		o.rmempty = true;
		o.depends('enabled', '1');

		o = s.option(form.DummyValue, '_tls_policy', _('TLS 安全策略'));
		o.depends('enabled', '1');
		o.rawhtml = true;
		o.cfgvalue = function() {
			return E('p', { 'class': 'lede-remote-pane-hint', 'style': 'margin:0' },
				_('连接中心 frps 必须校验证书：请先导入中心 CA，否则无法建立隧道（不允许跳过校验）。'));
		};

		o = s.option(form.Value, 'portal_port', _('中心门户 HTTPS 端口'),
			_('用于从中心下载 CA，默认 18443。'));
		o.datatype = 'port';
		o.default = '18443';
		o.rmempty = true;
		o.depends('enabled', '1');

		o = s.option(form.DummyValue, '_ca_state', _('中心 CA'));
		o.depends('enabled', '1');
		o.cfgvalue = function() {
			if (st.ca_installed)
				return E('span', { 'style': 'color:#16a34a;font-weight:600' }, _('已导入，可连接中心'));
			return E('span', { 'class': 'lede-remote-frpc-state--down' }, _('未导入 — 无法连接，请先点击下方按钮'));
		};

		o = s.option(form.Button, '_import_ca', ' ');
		o.inputtitle = _('从中心下载并导入 CA');
		o.inputstyle = 'apply';
		o.depends('enabled', '1');
		o.onclick = function() {
			return fs.exec('/usr/libexec/lede-center-frpc', ['import-ca']).then(function(res) {
				var out = parseJsonStatus(res, { ok: false, error: _('导入失败') });
				if (out.ok) {
					ui.addNotification(null, E('p', {},
						_('CA 已保存至 ') + (out.path || '/etc/lede-center/frps-ca.crt') +
						_('。若 frpc 已启用将自动重启。')), 'info');
					st.ca_installed = 1;
					return viewRef.mapCenter.render();
				}
				ui.addNotification(null, E('p', {}, out.error || _('导入失败')), 'danger');
			});
		};

		var ts = m.section(form.GridSection, 'tunnel', _('内网 TCP 隧道'),
			_('将门店 LAN 内 TCP 服务映射到中心 frps 端口。保存并应用时会写入 frpc 配置，并在本机防火墙放行「网关 → 内网 IP:端口」（不在本机 WAN 开放中心端口）。从公网访问须在公网入口 LEDE 将 TCP 转发至 192.168.6.251:同端口，或经 VPN/内网直连中心。'));
		ts.addremove = true;
		ts.anonymous = true;
		ts.nodescriptions = true;

		o = ts.option(form.Flag, 'enabled', _('启用'));
		o.default = '1';
		o.rmempty = false;
		o.width = '4em';

		o = ts.option(form.Value, 'remark', _('说明'));
		o.placeholder = _('例如：门店 NVR');
		o.rmempty = true;

		o = ts.option(form.Value, 'name', _('代理名'),
			_('字母数字 _ -，与站点 ID 组合为 frp 代理名；同站不可重复。'));
		o.datatype = 'rangelength(2,16)';
		o.rmempty = false;
		o.width = '8em';

		o = ts.option(form.Value, 'local_ip', _('内网 IP'));
		o.datatype = 'ip4addr';
		o.rmempty = false;
		o.placeholder = '192.168.1.100';

		o = ts.option(form.Value, 'local_port', _('内网端口'));
		o.datatype = 'port';
		o.rmempty = false;

		o = ts.option(form.Value, 'remote_port', _('中心端口'),
			_('在中心机 frps 上独占，请用 19100–19999；勿用 8000/80/443 等（会被中心 Nginx 占用导致 400）。'));
		o.datatype = 'range(19100,19999)';
		o.rmempty = false;

		return m;
	},

	render: function(data) {
		var view = this;
		var stWan = parseJsonStatus(data[2], { enabled: 0, port: 10443 });
		var stCenter = parseJsonStatus(data[3], { enabled: 0, running: 0, config: 0, uci_ok: 0 });

		view._activeTab = readActiveTab();
		persistActiveTab(view._activeTab);

		view.mapRemote = view._buildRemoteMap(stWan);
		view.mapCenter = view._buildCenterMap(stCenter);

		return Promise.all([
			view.mapRemote.render(),
			view.mapCenter.render()
		]).then(function(nodes) {
			var root = E('div', { 'class': 'remote-mosdns-page lede-remote-unified' });
			view._root = root;
			root.appendChild(E('style', {}, `
				.lede-remote-unified { width:100%; min-width:0; }
				.lede-remote-unified > h2 { margin:0 0 1rem; font-size:1.45rem; font-weight:700; line-height:1.2; }
				.lede-remote-unified > .cbi-map-descr { margin:-.35rem 0 1rem; opacity:.72; line-height:1.55; }
				.lede-remote-unified .cbi-tabmenu { margin:0 0 1rem; }
				.lede-remote-unified [data-pane] .cbi-section { min-width:0!important; width:100%!important; margin:0 0 1rem!important; padding:1rem 1.1rem!important; box-sizing:border-box; background:var(--cbi-section-bg,#fff)!important; border:1px solid rgba(0,0,0,.08)!important; border-radius:8px!important; box-shadow:0 2px 6px rgba(0,0,0,.03)!important; }
				.lede-remote-unified [data-pane] .cbi-section > h3 { display:flex; align-items:center; justify-content:space-between; margin:0 0 .85rem!important; padding:0 0 .7rem!important; border-bottom:1px solid rgba(125,125,125,.14); font-size:.98rem!important; font-weight:600!important; line-height:1.3; }
				.lede-remote-unified .lede-remote-pane-hint { margin:0 0 1rem; line-height:1.55; font-size:.92rem; opacity:.78; }
				.lede-remote-tab--wan.cbi-tab-active a { color:#b45309!important; font-weight:700; }
				.lede-remote-tab--center.cbi-tab-active a { color:#1d4ed8!important; font-weight:700; }
				.lede-remote-frpc-state--up { color:#16a34a; font-weight:700; }
				.lede-remote-frpc-state--down { color:#c0392b; font-weight:600; }
				@media (prefers-color-scheme:dark) {
					.lede-remote-unified [data-pane] .cbi-section { background:rgba(255,255,255,.03)!important; border-color:rgba(255,255,255,.08)!important; box-shadow:none!important; }
					.lede-remote-unified [data-pane] .cbi-section > h3 { border-bottom-color:rgba(255,255,255,.08); }
					.lede-remote-tab--wan.cbi-tab-active a { color:#fbbf24!important; }
					.lede-remote-tab--center.cbi-tab-active a { color:#93c5fd!important; }
					.lede-remote-frpc-state--up { color:#4ade80; }
					.lede-remote-frpc-state--down { color:#f87171; }
				}
			`));
			root.appendChild(E('h2', {}, _('远程管理')));
			root.appendChild(E('p', { 'class': 'cbi-map-descr' },
				_('两种方式任选其一：在本机 WAN 开放 HTTPS 管理端口，或通过 frpc 主动连接总部区域接入中心。')));

			view._tabMenu = E('ul', { 'class': 'cbi-tabmenu' }, [
				tabItem(view, 'wan', _('本机外网管理'), view._activeTab === 'wan'),
				tabItem(view, 'center', _('区域接入中心'), view._activeTab === 'center')
			]);
			root.appendChild(view._tabMenu);

			view._panes = E('div', { 'class': 'lede-remote-panes' });

			var paneWan = E('div', { 'data-pane': 'wan' });
			paneWan.appendChild(E('p', { 'class': 'lede-remote-pane-hint' },
				_('在 WAN 侧监听 HTTPS，供外网直接访问本机 LuCI（默认 10443）。与「区域接入中心」不建议同时启用。')));
			paneWan.appendChild(stripMapChrome(nodes[0], false));

			var paneCenter = E('div', { 'data-pane': 'center' });
			paneCenter.appendChild(stripMapChrome(nodes[1], true));

			view._panes.appendChild(paneWan);
			view._panes.appendChild(paneCenter);
			root.appendChild(view._panes);

			var actions = nodes[0].querySelector('.cbi-page-actions');
			if (actions) {
				actions.parentNode.removeChild(actions);
				root.appendChild(actions);
			}

			view._syncTabs();
			return root;
		});
	},

	_runRuntime: function(en, p) {
		return fs.exec('/usr/libexec/lede-wan-https', [en, String(p)]).then(function(res) {
			if (!res || res.code !== 0)
				throw new Error((res && (res.stderr || res.stdout)) || _('应用本机外网管理配置失败'));
			return fs.exec('/usr/libexec/lede-center-frpc', ['apply']);
		}).then(function(res) {
			if (!res || res.code !== 0)
				throw new Error((res && (res.stderr || res.stdout)) || _('应用区域接入配置失败'));
		});
	},

	_saveActiveMaps: function() {
		var view = this;
		var tab = view._activeTab || readActiveTab();
		if (tab === 'center')
			return view.mapCenter.save().then(function() { return view.mapRemote.save(); });
		return view.mapRemote.save();
	},

	handleSave: function() {
		var view = this;
		return view._saveActiveMaps().then(function() {
			return uci.save();
		});
	},

	handleSaveApply: function(ev, mode) {
		var en, p, view = this;
		var tab = view._activeTab || readActiveTab();
		var chain = tab === 'center'
			? view.mapCenter.save().then(function() {
				return view.mapRemote.save(function() {
					en = uci.get('lede-remote', 'main', 'enabled');
					p = uci.get('lede-remote', 'main', 'port') || '10443';
					en = (en === '1' || en === 1 || en === true) ? '1' : '0';
				});
			})
			: view.mapRemote.save(function() {
				en = uci.get('lede-remote', 'main', 'enabled');
				p = uci.get('lede-remote', 'main', 'port') || '10443';
				en = (en === '1' || en === 1 || en === true) ? '1' : '0';
			});
		return chain.then(function() {
			return uci.save();
		}).then(function() {
			return ui.changes.apply(mode == '0' || mode === false);
		}).then(function() {
			return view._runRuntime(en, p);
		}).then(function() {
			return fs.exec('/usr/libexec/lede-center-frpc', ['ensure']);
		}).then(function() {
			if (ui.changes && typeof ui.changes.init === 'function')
				return ui.changes.init();
		}).then(function() {
			persistActiveTab(view._activeTab || readActiveTab());
			window.location.reload();
		});
	}
});
