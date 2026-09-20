'use strict';
'require view';
'require form';
'require fs';
'require uci';
'require ui';

function parseStatus(res) {
	var text = String((res && (res.stdout || res.stderr)) || '').trim();
	var i = text.indexOf('{');
	if (i >= 0)
		text = text.slice(i);
	try {
		return JSON.parse(text);
	}
	catch (e) {
		return { enabled: 0, port: 10443, firewall: 0, nginx: 0, listen: 0, rule: 'Allow-WAN-HTTPS' };
	}
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('lede-remote'),
			fs.exec('/usr/libexec/lede-wan-https', ['status'])
		]);
	},

	render: function(data) {
		var st = parseStatus(data[1]);

		var m = new form.Map('lede-remote', _('远程管理'));
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

		o = s.option(form.Value, 'login_ban_n', _('登录尝试封禁阈值'),
			_('无法记录密码内容；仅统计短时间内重复提交登录请求。'));
		o.datatype = 'range(3,100)';
		o.default = '8';
		o.rmempty = false;
		o.depends('auto_ban', '1');

		o = s.option(form.Value, 'ban_minutes', _('临时封禁时长（分钟）'));
		o.datatype = 'range(1,1440)';
		o.default = '30';
		o.rmempty = false;
		o.depends('auto_ban', '1');

		this.map = m;
		return m.render().then(function(node) {
			node.classList.add('remote-mosdns-page');
			node.insertBefore(E('style', {}, `
				.remote-mosdns-page { width:100%; min-width:0; }
				.remote-mosdns-page > h2 { margin:0 0 1rem; font-size:1.45rem; font-weight:700; line-height:1.2; }
				.remote-mosdns-page > .cbi-map-descr { margin:-.35rem 0 1.25rem; opacity:.72; line-height:1.55; }
				.remote-mosdns-page > .cbi-section { min-width:0!important; width:100%!important; margin:0 0 1rem!important; padding:1rem 1.1rem!important; box-sizing:border-box; background:var(--cbi-section-bg,#fff)!important; border:1px solid rgba(0,0,0,.08)!important; border-radius:8px!important; box-shadow:0 2px 6px rgba(0,0,0,.03)!important; }
				.remote-mosdns-page > .cbi-section > h3 { display:flex; align-items:center; justify-content:space-between; margin:0 0 .85rem!important; padding:0 0 .7rem!important; border-bottom:1px solid rgba(125,125,125,.14); font-size:.98rem!important; font-weight:600!important; line-height:1.3; }
				@media (prefers-color-scheme:dark) {
					.remote-mosdns-page > .cbi-section { background:rgba(255,255,255,.03)!important; border-color:rgba(255,255,255,.08)!important; box-shadow:none!important; }
					.remote-mosdns-page > .cbi-section > h3 { border-bottom-color:rgba(255,255,255,.08); }
				}
			`), node.firstChild);
			return node;
		});
	},

	saveRemote: function() {
		var en, p;
		return this.map.save(function() {
			en = uci.get('lede-remote', 'main', 'enabled');
			p = uci.get('lede-remote', 'main', 'port') || '10443';
			en = (en === '1' || en === 1 || en === true) ? '1' : '0';
		}).then(function() {
			return fs.exec('/usr/libexec/lede-wan-https', [en, String(p)]);
		}).then(function(res) {
			if (!res || res.code !== 0)
				throw new Error((res && (res.stderr || res.stdout)) || _('应用远程管理配置失败'));
			return ui.changes.init();
		});
	},

	handleSave: function() {
		return this.saveRemote();
	},

	handleSaveApply: function(ev, mode) {
		return this.saveRemote().then(function() {
			return ui.changes.apply(mode);
		});
	}
});
