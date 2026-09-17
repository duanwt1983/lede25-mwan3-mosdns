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

	handleSave: function() {
		return this.map.save().then(function() {
			return uci.save();
		}).then(function() {
			var en = uci.get('lede-remote', 'main', 'enabled');
			var p = uci.get('lede-remote', 'main', 'port') || '10443';
			en = (en === '1' || en === 1 || en === true) ? '1' : '0';
			return fs.exec('/usr/libexec/lede-wan-https', [en, String(p)]);
		}).then(function() {
			if (ui.changes && typeof ui.changes.displayChangeIndicator === 'function')
				ui.changes.displayChangeIndicator(false);
			window.location.reload();
		});
	},

	handleSaveApply: function() {
		return this.handleSave();
	}
});
