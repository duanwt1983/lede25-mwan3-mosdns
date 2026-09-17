'use strict';
'require view';
'require form';
'require uci';
'require fs';
'require ui';
'require rpc';

const callStartUpdate = rpc.declare({
	object: 'luci.ispip',
	method: 'start_update',
	expect: { '': {} }
});

const callGetUpdateLog = rpc.declare({
	object: 'luci.ispip',
	method: 'get_update_log',
	expect: { '': {} }
});

function countCidr(text) {
	let n = 0;
	String(text || '').split(/\r?\n/).forEach(function(line) {
		if (/^([0-9]{1,3}\.){3}[0-9]{1,3}(\/[0-9]{1,2})?$/.test(line.trim()))
			n++;
	});
	return n;
}

function countHint(n) {
	if (n > 0)
		return _('当前地址库 %d 条').format(n);
	return _('当前地址库 0 条，点「检查并更新」下载');
}

return view.extend({
	handleUpdate() {
		const statusMsg = E('p', { 'class': 'spinning' }, _('请稍候，这可能需要几分钟…'));
		const logTextarea = E('textarea', {
			'class': 'cbi-input-textarea',
			'readonly': 'readonly',
			'style': 'width: 100%; height: 300px; font-family: monospace; font-size: 12px; margin-top: 10px;',
			'placeholder': _('正在启动更新…')
		});
		const closeButton = E('button', {
			'class': 'btn',
			'style': 'display: none;',
			'click': function() {
				ui.hideModal();
				location.reload();
			}
		}, _('关闭'));

		ui.showModal(_('正在更新运营商地址库…'), [
			statusMsg,
			logTextarea,
			E('div', { 'class': 'right' }, [closeButton])
		]);

		const applyLog = function(log) {
			log = String(log || '');
			if (!log)
				return true;
			logTextarea.value = log;
			logTextarea.scrollTop = logTextarea.scrollHeight;
			if (log.match(/UPDATE_FINISHED/) || /^OK\b/m.test(log) || log.indexOf('更新成功') >= 0) {
				statusMsg.textContent = _('更新成功');
				statusMsg.classList.remove('spinning');
				statusMsg.style.color = '#19be6b';
				statusMsg.style.fontWeight = 'bold';
				closeButton.style.display = 'inline';
				return false;
			}
			if (log.match(/UPDATE_EXITED/) || log.indexOf('更新失败') >= 0 || /^FAIL\b/m.test(log)) {
				statusMsg.textContent = _('更新失败');
				statusMsg.classList.remove('spinning');
				statusMsg.style.color = '#ed4014';
				statusMsg.style.fontWeight = 'bold';
				closeButton.style.display = 'inline';
				return false;
			}
			if (log.match(/Another update is already in progress/)) {
				statusMsg.textContent = _('另一次更新正在进行中。');
				statusMsg.classList.remove('spinning');
				statusMsg.style.color = '#ff9900';
				closeButton.style.display = 'inline';
				return false;
			}
			if (log.match(/UPDATE_STARTED/) || log.match(/merged /))
				statusMsg.textContent = _('正在更新，请稍候…');
			return true;
		};

		const pollLog = function() {
			return callGetUpdateLog().then(function(res) {
				if (res && res.log)
					return applyLog(res.log);
				return true;
			});
		};

		return callStartUpdate().then(function(res) {
			if (res && res.success) {
				const interval = window.setInterval(function() {
					pollLog().then(function(continuePolling) {
						if (!continuePolling)
							window.clearInterval(interval);
					}).catch(function(e) {
						statusMsg.textContent = _('读取日志失败：%s').format(e.message || String(e));
						statusMsg.classList.remove('spinning');
						statusMsg.style.color = '#ed4014';
						closeButton.style.display = 'inline';
						window.clearInterval(interval);
					});
				}, 1000);
				pollLog();
			} else if (res && res.error && res.error.match(/Another update is already in progress/)) {
				statusMsg.textContent = _('另一次更新正在进行中。');
				statusMsg.style.color = '#ff9900';
				callGetUpdateLog().then(function(logRes) {
					if (logRes && logRes.log)
						logTextarea.value = logRes.log;
				});
				statusMsg.classList.remove('spinning');
				closeButton.style.display = 'inline';
			} else {
				statusMsg.textContent = (res && res.error) || _('无法启动更新。');
				statusMsg.style.color = '#ed4014';
				statusMsg.classList.remove('spinning');
				closeButton.style.display = 'inline';
			}
		}).catch(function(e) {
			statusMsg.textContent = _('更新失败：%s').format(e.message || String(e));
			statusMsg.classList.remove('spinning');
			statusMsg.style.color = '#ed4014';
			closeButton.style.display = 'inline';
		});
	},

	load() {
		return Promise.all([
			uci.load('isp-ip'),
			fs.read('/etc/mwan3/isp/chinanet.cidr').catch(() => ''),
			fs.read('/etc/mwan3/isp/unicom.cidr').catch(() => ''),
			fs.read('/etc/mwan3/isp/cmcc.cidr').catch(() => ''),
			fs.read('/etc/mwan3/isp/other.cidr').catch(() => '')
		]);
	},

	render(data) {
		const self = this;
		const nCt = countCidr(data && data[1]);
		const nCu = countCidr(data && data[2]);
		const nCm = countCidr(data && data[3]);
		const nOt = countCidr(data && data[4]);

		const m = new form.Map('isp-ip', _('运营商地址库'),
			_('从国内源下载电信/联通/移动/其它 IPv4 段，写入 /etc/mwan3/isp/*.cidr，给「IP 集」里的 isp_chinanet 等使用。不会自动改分流规则。更新计划与 MosDNS「更新数据库」页相同。'));

		const s = m.section(form.NamedSection, 'main', 'update');
		s.addremove = false;
		s.anonymous = true;

		let o = s.option(form.Flag, 'auto', _('启用自动更新数据库'));
		o.rmempty = false;
		o.default = '0';

		o = s.option(form.ListValue, 'week', _('更新周期'));
		o.value('*', _('每天'));
		o.value('1', _('每周一'));
		o.value('2', _('每周二'));
		o.value('3', _('每周三'));
		o.value('4', _('每周四'));
		o.value('5', _('每周五'));
		o.value('6', _('每周六'));
		o.value('0', _('每周日'));
		o.default = '3';

		o = s.option(form.ListValue, 'hour', _('更新时间'));
		for (let t = 0; t < 24; t++)
			o.value(String(t), t + ':00');
		o.default = '3';

		o = s.option(form.Value, 'github_proxy', _('GitHub 代理'),
			_('通过代理更新 GitHub 链接，留空则不走代理。clang.cn、yfgao 等国内源仍直连。'));
		o.value('', _('不使用代理（直连）'));
		o.value('https://gh-proxy.com', 'https://gh-proxy.com');
		o.value('https://ghproxy.net', 'https://ghproxy.net');
		o.value('https://mirror.ghproxy.com', 'https://mirror.ghproxy.com');
		o.rmempty = true;
		o.placeholder = 'https://gh-proxy.com';

		o = s.option(form.DynamicList, 'url_chinanet', _('电信更新链接'), countHint(nCt));
		o.value('https://ispip.clang.cn/chinatelecom.txt', 'clang.cn 电信');
		o.value('https://china-operator-ip.yfgao.com/chinanet.txt', 'yfgao 电信');
		o.placeholder = 'https://';

		o = s.option(form.DynamicList, 'url_unicom', _('联通更新链接'), countHint(nCu));
		o.value('https://ispip.clang.cn/unicom_cnc.txt', 'clang.cn 联通');
		o.value('https://china-operator-ip.yfgao.com/unicom.txt', 'yfgao 联通');
		o.placeholder = 'https://';

		o = s.option(form.DynamicList, 'url_cmcc', _('移动更新链接'), countHint(nCm));
		o.value('https://ispip.clang.cn/cmcc.txt', 'clang.cn 移动');
		o.value('https://china-operator-ip.yfgao.com/cmcc.txt', 'yfgao 移动');
		o.placeholder = 'https://';

		o = s.option(form.DynamicList, 'url_other', _('其它更新链接'), countHint(nOt));
		o.value('https://ispip.clang.cn/othernet.txt', 'clang.cn 其它');
		o.value('https://ispip.clang.cn/cernet.txt', 'clang.cn 教育网');
		o.value('https://ispip.clang.cn/chinabtn.txt', 'clang.cn 广电');
		o.value('https://ispip.clang.cn/gwbn.txt', 'clang.cn 长城');
		o.value('https://china-operator-ip.yfgao.com/cernet.txt', 'yfgao 教育网');
		o.value('https://china-operator-ip.yfgao.com/cstnet.txt', 'yfgao 科技网');
		o.value('https://china-operator-ip.yfgao.com/drpeng.txt', 'yfgao 鹏博士');
		o.placeholder = 'https://';

		o = s.option(form.Button, '_update', null, _('检查并更新运营商地址库。'));
		o.title = _('地址库更新');
		o.inputtitle = _('检查并更新');
		o.inputstyle = 'action';
		o.onclick = function(ev) {
			if (ev) {
				ev.preventDefault();
				ev.stopPropagation();
			}
			/* Save form to UCI without ui.changes.apply() — that triggers LuCI reload countdown. */
			return m.save().then(function() {
				return uci.save();
			}).then(function() {
				if (ui.changes && typeof ui.changes.displayChangeIndicator === 'function')
					ui.changes.displayChangeIndicator(false);
				return self.handleUpdate();
			});
		};

		return m.render();
	},

	handleSaveApply(ev, mode) {
		return this.super('handleSaveApply', [ev, mode]).then(function() {
			return fs.exec('/bin/sh', ['/usr/libexec/isp-ip-update', 'sync-cron']);
		});
	}
});
