'use strict';
'require view';
'require form';
'require fs';
'require uci';

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
		var on = st.enabled ? '1' : '0';
		var port = String(st.port || uci.get('lede-remote', 'main', 'port') || '10443');

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
			if (!st.firewall)
				return _('未添加');
			return '%s　%s → %s　%s/%s　%s'.format(
				st.rule || 'Allow-WAN-HTTPS',
				st.src || 'wan',
				_('本机'),
				st.proto || 'tcp',
				port,
				st.target || 'ACCEPT'
			);
		};

		o = s.option(form.DummyValue, '_listen', _('监听'));
		o.cfgvalue = function() {
			if (st.listen)
				return '0.0.0.0:%s'.format(port);
			if (st.nginx)
				return _('配置已生成，等待监听');
			return _('未监听');
		};

		o = s.option(form.Flag, 'enabled', _('允许外网访问管理页'));
		o.rmempty = false;
		o.default = '0';
		o.cfgvalue = function() {
			return on;
		};

		o = s.option(form.Value, 'port', _('外网端口'));
		o.datatype = 'range(1024,65535)';
		o.default = '10443';
		o.rmempty = false;
		o.cfgvalue = function() {
			return port;
		};

		this.map = m;
		return m.render();
	},

	handleSave: function() {
		var self = this;
		return this.map.save().then(function() {
			var en = uci.get('lede-remote', 'main', 'enabled');
			var p = uci.get('lede-remote', 'main', 'port') || '10443';
			en = (en === '1' || en === 1 || en === true) ? '1' : '0';
			return fs.exec('/usr/libexec/lede-wan-https', [en, String(p)]);
		}).then(function() {
			window.location.reload();
		});
	},

	handleSaveApply: function() {
		return this.handleSave();
	}
});
