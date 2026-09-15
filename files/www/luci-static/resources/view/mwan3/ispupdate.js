'use strict';
'require view';
'require form';
'require uci';
'require fs';
'require ui';

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
	return _('当前地址库 0 条，点「立即更新地址库」下载');
}

return view.extend({
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
		const nCt = countCidr(data && data[1]);
		const nCu = countCidr(data && data[2]);
		const nCm = countCidr(data && data[3]);
		const nOt = countCidr(data && data[4]);

		const m = new form.Map('isp-ip', _('运营商地址库'),
			_('从国内源下载电信/联通/移动/其它 IPv4 段，写入 /etc/mwan3/isp/*.cidr，给「IP 集」里的 isp_chinanet 等使用。不会自动改分流规则。可像 MosDNS 国内 DNS 一样增加或删除更新链接。'));

		const s = m.section(form.NamedSection, 'main', 'update');
		s.addremove = false;
		s.anonymous = true;

		let o = s.option(form.Flag, 'auto', _('启用自动更新'));
		o.rmempty = false;
		o.default = '0';

		o = s.option(form.ListValue, 'week', _('更新周期'));
		o.value('*', _('每天'));
		o.value('1', _('星期一'));
		o.value('2', _('星期二'));
		o.value('3', _('星期三'));
		o.value('4', _('星期四'));
		o.value('5', _('星期五'));
		o.value('6', _('星期六'));
		o.value('0', _('星期日'));
		o.default = '*';
		o.depends('auto', '1');

		o = s.option(form.ListValue, 'hour', _('更新时间'));
		for (let i = 0; i < 24; i++)
			o.value(String(i), '%02d:00'.format(i));
		o.default = '4';
		o.depends('auto', '1');

		o = s.option(form.Value, 'github_proxy', _('GitHub 代理'),
			_('仅用于 GitHub / raw.githubusercontent.com 链接。clang.cn、yfgao 等国内源仍直连。留空则不走代理。保存后再点更新，或直接点「立即更新地址库」也会先保存。'));
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

		o = s.option(form.Button, '_update', _('立即更新地址库'));
		o.inputtitle = _('立即更新地址库');
		o.inputstyle = 'apply';
		o.onclick = function() {
			return m.save().then(function() {
				return uci.save();
			}).then(function() {
			return fs.exec('/bin/sh', ['/usr/libexec/isp-ip-update']).then(function(res) {
				return fs.read('/var/run/isp-ip-update.status').catch(function() {
					return '';
				}).then(function(st) {
					const status = String(st || '').trim();
					const out = String((res && (res.stdout || res.stderr)) || '').trim();
					const code = (res && res.code != null) ? Number(res.code) : NaN;
					const ok = out.indexOf('更新失败') < 0 &&
						(out.indexOf('更新成功') === 0 || /^OK\b/.test(status)) &&
						(isNaN(code) || code === 0);
					const msg = out || status || (ok ? _('更新成功') : _('更新失败'));
					ui.addNotification(null, E('pre', { 'style': 'white-space:pre-wrap' }, msg),
						ok ? 'info' : 'error');
					if (ok)
						window.setTimeout(function() { location.reload(); }, 600);
				});
			}).catch(function(e) {
				ui.addNotification(null, E('p', {}, e.message || String(e)), 'error');
			});
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
