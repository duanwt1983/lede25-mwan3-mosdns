'use strict';
'require view';
'require fs';
'require uci';
'require form';
'require tools.widgets as widgets';

return view.extend({
	load: function() {
		return uci.load('samba4').then(function() {
			return Promise.all([
				L.resolveDefault(fs.stat('/sbin/block'), null),
				L.resolveDefault(fs.stat('/etc/config/fstab'), null),
				L.resolveDefault(fs.stat('/usr/sbin/nmbd'), {}),
				L.resolveDefault(fs.stat('/usr/sbin/samba'), {}),
				L.resolveDefault(fs.stat('/usr/sbin/winbindd'), {}),
				L.resolveDefault(fs.exec('/usr/sbin/smbd', ['-V']), null),
				L.resolveDefault(fs.read('/etc/samba/smb.conf.template'), '')
			]);
		});
	},

	render: function(stats) {
		var m, s, o, v, tmpl0;
		v = '';
		tmpl0 = (stats[6] || '').replace(/\r\n/g, '\n');

		m = new form.Map('samba4', _('Network Shares'));
		if (stats[5] && stats[5].code === 0)
			v = stats[5].stdout.trim();

		s = m.section(form.TypedSection, 'samba', 'Samba ' + v);
		s.anonymous = true;
		s.tab('general', _('General Settings'));
		s.tab('template', _('Edit Template'), _('Edit the template that is used for generating the samba configuration.'));

		o = s.taboption('general', form.Flag, 'enabled', _('启用 Samba 服务'),
			_('保存并应用后启动或停止 smbd。'));
		o.rmempty = false;

		o = s.taboption('general', form.Flag, 'autoshare', _('自动磁盘共享'),
			_('需同时开启 Samba 服务；关闭后不会自动创建 /data 等共享。'));
		o.rmempty = false;

		o = s.taboption('general', widgets.NetworkSelect, 'interface', _('Interface'),
			_('Listen only on the given interface or, if unspecified, on lan'));
		o.multiple = true;
		o.cfgvalue = function(section_id) {
			return L.toArray(uci.get('samba4', section_id, 'interface'));
		};
		o.write = function(section_id, formvalue) {
			var cfgvalue = this.cfgvalue(section_id);
			var oldNetworks = L.toArray(cfgvalue);
			var newNetworks = L.toArray(formvalue);
			oldNetworks.sort();
			newNetworks.sort();
			if (oldNetworks.join(' ') === newNetworks.join(' '))
				return;
			return uci.set('samba4', section_id, 'interface', newNetworks.join(' '));
		};

		o = s.taboption('general', form.Value, 'workgroup', _('Workgroup'));
		o.placeholder = 'WORKGROUP';
		o = s.taboption('general', form.Value, 'description', _('Description'));
		o.placeholder = 'Samba4 on OpenWrt';

		s.taboption('general', form.Flag, 'enable_extra_tuning', _('Enable extra Tuning'),
			_('Enable some community driven tuning parameters, that may improve write speeds and better operation via WiFi. \
Not recommend if multiple clients write to the same files, at the same time!'));
		s.taboption('general', form.Flag, 'disable_async_io', _('Force synchronous  I/O'),
			_('On lower-end devices may increase speeds, by forcing synchronous I/O instead of the default asynchronous.'));
		s.taboption('general', form.Flag, 'macos', _('Enable macOS compatible shares'),
			_('Enables Apple\'s AAPL extension globally and adds macOS compatibility options to all shares.'));
		s.taboption('general', form.Flag, 'allow_legacy_protocols', _('Allow legacy (insecure) protocols/authentication.'),
			_('Allow legacy smb(v1)/Lanman connections, needed for older devices without smb(v2.1/3) support.'));

		if (stats[2].type === 'file')
			s.taboption('general', form.Flag, 'disable_netbios', _('Disable Netbios'));
		if (stats[3].type === 'file')
			s.taboption('general', form.Flag, 'disable_ad_dc', _('Disable Active Directory Domain Controller'));
		if (stats[4].type === 'file')
			s.taboption('general', form.Flag, 'disable_winbind', _('Disable Winbind'));

		o = s.taboption('template', form.TextValue, '_tmpl', null,
			_("This is the content of the file '/etc/samba/smb.conf.template' from which your samba configuration will be generated. \
Values enclosed by pipe symbols ('|') should not be changed. They get their values from the 'General Settings' tab."));
		o.rows = 20;
		o.optional = true;
		o.cfgvalue = function() {
			return tmpl0;
		};
		o.write = function(section_id, formvalue) {
			var body = String(formvalue || '').trim().replace(/\r\n/g, '\n');
			if (body === tmpl0.replace(/\n$/, '') || body + '\n' === tmpl0)
				return;
			tmpl0 = body + '\n';
			return fs.write('/etc/samba/smb.conf.template', tmpl0);
		};

		s = m.section(form.TableSection, 'sambashare', _('Shared Directories'),
			_('Please add directories to share. Each directory refers to a folder on a mounted device.'));
		s.anonymous = true;
		s.addremove = true;
		s.option(form.Value, 'name', _('Name'));
		o = s.option(form.Value, 'path', _('Path'));
		if (stats[0] && stats[1])
			o.titleref = L.url('admin', 'system', 'mounts');
		o = s.option(form.Flag, 'browseable', _('Browse-able'));
		o.enabled = 'yes';
		o.disabled = 'no';
		o.default = 'yes';
		o = s.option(form.Flag, 'read_only', _('Read-only'));
		o.enabled = 'yes';
		o.disabled = 'no';
		o.default = 'no';
		o.rmempty = false;
		s.option(form.Flag, 'force_root', _('Force Root'));
		o = s.option(form.Value, 'users', _('Allowed users'));
		o.rmempty = true;
		o = s.option(form.Flag, 'guest_ok', _('Allow guests'));
		o.enabled = 'yes';
		o.disabled = 'no';
		o.default = 'yes';
		o.rmempty = false;
		o = s.option(form.Flag, 'guest_only', _('Guests only'));
		o.enabled = 'yes';
		o.disabled = 'no';
		o.default = 'no';
		o = s.option(form.Flag, 'inherit_owner', _('Inherit owner'));
		o.enabled = 'yes';
		o.disabled = 'no';
		o.default = 'no';
		o = s.option(form.Value, 'create_mask', _('Create mask'));
		o.maxlength = 4;
		o.default = '0666';
		o.placeholder = '0666';
		o.rmempty = false;
		o = s.option(form.Value, 'dir_mask', _('Directory mask'));
		o.maxlength = 4;
		o.default = '0777';
		o.placeholder = '0777';
		o.rmempty = false;
		o = s.option(form.Value, 'vfs_objects', _('Vfs objects'));
		o.rmempty = true;
		s.option(form.Flag, 'timemachine', _('Apple Time-machine share'));
		o = s.option(form.Value, 'timemachine_maxsize', _('Time-machine size in GB'));
		o.rmempty = true;

		m.save = function() {
			return form.Map.prototype.save.apply(m, arguments).then(function() {
				var secs = uci.sections('samba4', 'samba') || [];
				var sid = secs.length ? secs[0]['.name'] : null;
				var en = sid ? uci.get('samba4', sid, 'enabled') : '0';
				var chain;
				if (en === '1') {
					chain = fs.exec('/etc/init.d/samba4', ['enable']).then(function() {
						return fs.exec('/etc/init.d/samba4', ['restart']);
					});
				} else {
					chain = fs.exec('/etc/init.d/samba4', ['stop']).then(function() {
						return fs.exec('/etc/init.d/samba4', ['disable']);
					});
				}
				return chain.then(function() {
					return fs.exec('/usr/libexec/lede-samba-sync');
				});
			});
		};

		return m.render();
	}
});
