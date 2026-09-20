'use strict';
'require view';
'require rpc';
'require ui';
'require uci';
'require fs';

var callReboot = rpc.declare({
	object: 'system',
	method: 'reboot',
	expect: { result: 0 }
});

return view.extend({
	load: function() {
		return uci.changes();
	},

	render: function(changes) {
		var body = E([
			E('h2', _('重启 / 关机')),
			E('p', {}, _('重新启动操作系统，或安全关闭这台 x86 设备。'))
		]);

		for (var config in (changes || {})) {
			body.appendChild(E('p', { 'class': 'alert-message warning' },
				_('警告：未保存的配置会在重启或关机时丢失！')));
			break;
		}

		body.appendChild(E('hr'));
		body.appendChild(E('div', { 'style': 'display:flex;justify-content:flex-end;gap:.75rem;flex-wrap:wrap' }, [
			E('button', {
				'class': 'cbi-button cbi-button-action important',
				'click': ui.createHandlerFn(this, 'handleReboot')
			}, _('执行重启')),
			E('button', {
				'class': 'cbi-button cbi-button-negative important',
				'click': ui.createHandlerFn(this, 'handlePoweroff')
			}, _('安全关机'))
		]));

		return body;
	},

	handleReboot: function() {
		ui.showModal(_('确认重启'), [
			E('p', {}, _('重启会中断网络和所有正在运行的服务。确定要重新启动这台设备吗？')),
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'btn',
					'click': ui.hideModal
				}, _('取消')),
				' ',
				E('button', {
					'class': 'btn cbi-button-action important',
					'click': ui.createHandlerFn(this, 'performReboot')
				}, _('确认重启'))
			])
		]);
	},

	performReboot: function() {
		return callReboot().then(function(res) {
			if (res != 0) {
				ui.addNotification(null, E('p', _('重启命令执行失败，错误码：%d').format(res)));
				L.raise('Error', 'Reboot failed');
			}

			ui.showModal(_('正在重启…'), [
				E('p', { 'class': 'spinning' }, _('正在等待设备重新上线…'))
			]);

			window.setTimeout(function() {
				ui.showModal(_('正在重启…'), [
					E('p', { 'class': 'spinning alert-message warning' },
						_('设备暂时无法连接，仍在等待重新上线…'))
				]);
			}, 150000);

			ui.awaitReconnect();
		}).catch(function(e) {
			ui.addNotification(null, E('p', e.message));
		});
	},

	handlePoweroff: function() {
		ui.showModal(_('确认关机'), [
			E('p', {}, _('关机会中断网络和所有正在运行的服务。确定要安全关闭这台设备吗？')),
			E('div', { 'class': 'right' }, [
				E('button', {
					'class': 'btn',
					'click': ui.hideModal
				}, _('取消')),
				' ',
				E('button', {
					'class': 'btn cbi-button-negative important',
					'click': ui.createHandlerFn(this, 'performPoweroff')
				}, _('确认关机'))
			])
		]);
	},

	performPoweroff: function() {
		ui.showModal(_('正在关机…'), [
			E('p', { 'class': 'spinning' }, _('正在停止服务并卸载文件系统，请勿直接断电。'))
		]);

		return fs.exec('/usr/libexec/lede-poweroff', []).then(function(res) {
			if (!res || res.code !== 0)
				throw new Error((res && (res.stderr || res.stdout)) || _('关机命令执行失败'));

			window.setTimeout(function() {
				ui.showModal(_('设备已关机'), [
					E('p', { 'class': 'alert-message success' },
						_('设备应已安全关闭。如主板没有自动断电，请在确认磁盘灯停止闪烁后关闭电源。'))
				]);
			}, 15000);
		}).catch(function(e) {
			ui.hideModal();
			ui.addNotification(null, E('p', e.message));
		});
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
