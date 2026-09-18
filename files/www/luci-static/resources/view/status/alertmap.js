'use strict';
'require baseclass';
'require form';
'require fs';
'require ui';
'require uci';
return baseclass.extend({
	wanNames: [],

	makeMap(wanNames, svc) {
	this.wanNames = wanNames || [];
	this.svc = svc || {};
	const m = new form.Map('wanalert', _('系统报警'),
		_('钉钉自定义机器人通知 WAN 异常和本机资源阈值。安全设置须与机器人页面一致：自定义关键词，或加签。采样数据同时写入日志文件。Webhook 不要泄露。'));

	function flagCbiBox(opt, section_id, option_index, labelClass, labelExtra) {
		const config_name = opt.uciconfig ?? opt.section.uciconfig ?? opt.map.config;
		const w = opt.renderWidget(section_id, option_index, opt.cfgvalue(section_id));
		const lab = E('label', Object.assign({
			'class': labelClass,
			'data-opt': opt.option
		}, labelExtra || {}), [
			w,
			E('span', {}, opt.title)
		]);
		return E('div', {
			'class': 'cbi-value',
			'id': 'cbi-%s-%s-%s'.format(config_name, section_id, opt.option),
			'data-index': option_index,
			'data-field': opt.cbid(section_id),
			'data-name': opt.option
		}, [ lab ]);
	}

	const CompactFlag = form.Flag.extend({
		render: function(option_index, section_id) {
			return flagCbiBox(this, section_id, option_index, 'lede-ding-cell');
		}
	});

	const InlineFlag = form.Flag.extend({
		render: function(option_index, section_id) {
			return flagCbiBox(this, section_id, option_index, 'lede-fix-cell');
		}
	});

	let s = m.section(form.NamedSection, 'main', 'wanalert', _('钉钉机器人'));
	s.addremove = false;

	let o = s.option(form.Flag, 'enabled', _('启用钉钉推送'));
	o.default = o.disabled;
	o.rmempty = false;

	o = s.option(form.Value, 'dingtalk_webhook', _('Webhook'),
		_('群设置 → 智能群助手 → 自定义机器人。形如 https://oapi.dingtalk.com/robot/send?access_token=…'));
	o.placeholder = 'https://oapi.dingtalk.com/robot/send?access_token=';
	o.rmempty = false;

	o = s.option(form.ListValue, 'security', _('安全设置（与钉钉机器人一致）'));
	o.value('keyword', _('自定义关键词'));
	o.value('sign', _('加签'));
	o.default = 'keyword';
	o.rmempty = false;

	o = s.option(form.Value, 'keyword', _('自定义关键词'),
		_('消息正文必须包含此词，否则钉钉会拒绝。默认「线路」。'));
	o.default = '线路';
	o.rmempty = false;
	o.depends('security', 'keyword');

	o = s.option(form.Value, 'dingtalk_secret', _('加签密钥'),
		_('机器人安全设置里 SEC 开头的字符串。'));
	o.password = true;
	o.rmempty = false;
	o.depends('security', 'sign');

	o = s.option(form.Value, 'at_mobile', _('提醒手机号'),
		_('群内成员的钉钉绑定手机号，多个用空格分隔。可留空。'));
	o.optional = true;
	o.rmempty = false;

	o = s.option(form.Value, 'extra_text', _('附加说明'),
		_('钉钉正文第一行：自定义关键词 --- 附加说明。后面仍是时间、报警内容。可留空，此时第一行只有关键词。'));
	o.optional = true;
	o.rmempty = false;

	o = s.option(form.Value, 'cooldown', _('同一事件冷却（秒）'),
		_('只限制钉钉，不限制写入日志。钉钉每机器人每分钟最多约 20 条。'));
	o.datatype = 'uinteger';
	o.default = '120';

	o = s.option(form.Button, '_test', _('发送测试消息'));
	o.inputtitle = _('发送测试');
	o.inputstyle = 'apply';
	o.onclick = function() {
		return m.save().then(function() {
			return uci.save();
		}).then(function() {
			return fs.exec('/usr/sbin/wan-alert', ['test', 'manual']);
		}).then(function(res) {
			const out = ((res && (res.stdout || res.stderr)) || '').trim();
			if (res && res.code)
				ui.addNotification(null, E('p', _('发送失败') + (out ? ': ' + out : _('。请填写 Webhook 后点保存，再测一次。'))), 'error');
			else
				ui.addNotification(null, E('p', _('已请求发送。请到钉钉群确认。') + (out ? ' ' + out : '')), 'info');
		}).catch(e => {
			ui.addNotification(null, E('p', _('发送失败: %s').format(e.message)), 'error');
		});
	};

	s = m.section(form.NamedSection, 'main', 'wanalert', _('推送到钉钉'));
	s.addremove = false;
	s.description = _('下列事件都会写入报警日志。打开开关才向钉钉推送。');

	o = s.option(CompactFlag, 'alert_down', _('WAN 掉线'));
	o.default = o.enabled;
	o = s.option(CompactFlag, 'alert_up', _('WAN 恢复'));
	o.default = o.enabled;
	o = s.option(CompactFlag, 'alert_all_down', _('全部 WAN 同时掉线'));
	o.default = o.enabled;
	o = s.option(CompactFlag, 'alert_track', _('mwan3 探测失败（口还在）'));
	o.default = o.disabled;
	o = s.option(CompactFlag, 'alert_link_speed', _('网口协商降速'));
	o.default = o.disabled;
	o = s.option(CompactFlag, 'alert_ppp_fail', _('PPPoE 认证失败'));
	o.default = o.disabled;
	o = s.option(CompactFlag, 'alert_wan_bw', _('WAN 带宽接近配置上限'));
	o.default = o.disabled;
	o = s.option(CompactFlag, 'alert_cpu', _('CPU 过高'));
	o.default = o.enabled;
	o = s.option(CompactFlag, 'alert_load', _('系统负载过高'));
	o.default = o.enabled;
	o = s.option(CompactFlag, 'alert_mem', _('内存不足'));
	o.default = o.enabled;
	o = s.option(CompactFlag, 'alert_disk', _('磁盘空间不足'));
	o.default = o.enabled;
	o = s.option(CompactFlag, 'alert_temp', _('温度过高'));
	o.default = o.enabled;
	o = s.option(CompactFlag, 'alert_conntrack', _('连接跟踪占用高'));
	o.default = o.enabled;
	o = s.option(CompactFlag, 'alert_dhcp', _('DHCP 池不足 / 池空'));
	o.default = o.enabled;
	o = s.option(CompactFlag, 'alert_new_mac', _('新设备入网'));
	o.default = o.disabled;
	o = s.option(CompactFlag, 'alert_arp', _('ARP 欺骗 / 地址冲突'));
	o.default = o.enabled;
	o = s.option(CompactFlag, 'alert_burst_down', _('客户端下行突发持续'));
	o.default = o.disabled;
	o = s.option(CompactFlag, 'alert_burst_up', _('客户端上行突发持续'));
	o.default = o.disabled;
	o = s.option(CompactFlag, 'alert_login_fail', _('登录失败过多'));
	o.default = o.disabled;
	o = s.option(CompactFlag, 'alert_isp', _('ISP 地址库更新失败'));
	o.default = o.disabled;
	o = s.option(CompactFlag, 'alert_overlay', _('Overlay 无法写入'));
	o.default = o.enabled;
	o = s.option(CompactFlag, 'alert_smart', _('磁盘 SMART 异常'));
	o.default = o.disabled;
	o = s.option(CompactFlag, 'alert_dns', _('MosDNS 上游探测失败'));
	o.default = o.disabled;
	o = s.option(CompactFlag, 'alert_hw', _('内核/硬件异常与异常重启'));
	o.default = o.enabled;

	s = m.section(form.NamedSection, 'main', 'wanalert', _('自动维护'));
	s.addremove = false;

	o = s.option(form.Flag, 'autofix', _('启用自动维护'));
	o.default = o.disabled;
	o.rmempty = false;
	o.description = _('启用后：断线告警只写日志，钉钉由自动维护推送网卡重启结果。关闭时：断线告警直接发钉钉。');
	o.render = function(option_index, section_id) {
		return flagCbiBox(this, section_id, option_index, 'lede-fix-master', {
			'title': _('打开后才执行下面的自动处理')
		});
	};

	o = s.option(InlineFlag, 'autofix_wan', _('WAN 掉线且网线仍在 → 重拨该口'));
	o.default = o.enabled;

	(this.wanNames || []).forEach(function(name) {
		const f = s.option(InlineFlag, 'wfix_' + name, name);
		f.default = f.enabled;
	});

	o = s.option(form.Value, 'autofix_cooldown', _('同一处理间隔（秒）'));
	o.datatype = 'uinteger';
	o.default = '600';

	s = m.section(form.NamedSection, 'main', 'wanalert', _('日志文件'));
	s.addremove = false;

	o = s.option(form.Flag, 'log_enabled', _('写入日志'));
	o.default = o.enabled;
	o.rmempty = false;

	o = s.option(form.Value, 'log_path', _('日志路径'),
		_('填文件或目录的绝对路径。目录会自动创建；只填目录时自动补默认文件名。目录写不了时退到 /tmp（重启会丢）。路径以「日志中心」和本页配置为准，不要依赖固件写死的位置。'));
	o.placeholder = _('绝对路径');
	o.rmempty = false;

	o = s.option(form.Value, 'log_max_kb', _('单段大小（KB）'),
		_('写满后归档为 文件名.时间戳 长期保留。磁盘占用达到报警阈值时才从最旧归档覆盖删除。'));
	o.datatype = 'uinteger';
	o.default = '512';

	o = s.option(form.Flag, 'log_sample', _('定期记录当前数值'),
		_('未超阈值也会按检查间隔写一行 CPU/内存/负载/磁盘/温度/DHCP。默认关闭，不写进报警日志。'));
	o.default = '0';

	o = s.option(form.Value, 'check_interval', _('全面检查间隔（秒）'),
		_('CPU/磁盘/WAN 等按此间隔。客户端突发约每 10 秒采样一次。最短 30 秒。'));
	o.datatype = 'uinteger';
	o.default = '60';

	s = m.section(form.NamedSection, 'main', 'wanalert', _('检测阈值'));
	s.addremove = false;
	s.description = _('达到阈值并连续保持设定分钟数后才触发；低于阈值会清零并重新计时。是否钉钉由上面的开关决定。');

	o = s.option(form.Value, 'dhcp_remain', _('DHCP 剩余地址少于（个）'));
	o.datatype = 'uinteger';
	o.default = '8';

	o = s.option(form.Value, 'cpu_percent', _('CPU 使用率（%）'));
	o.datatype = 'range(1,100)';
	o.default = '90';
	o = s.option(form.Value, 'cpu_hold_min', _('持续时间（分钟）'));
	o.datatype = 'uinteger';
	o.default = '5';

	o = s.option(form.Value, 'load_warn', _('15 分钟负载'),
		_('与 /proc/loadavg 第三个数字比较。x86 多核能适当调高。'));
	o.default = '2.00';
	o = s.option(form.Value, 'load_hold_min', _('持续时间（分钟）'));
	o.datatype = 'uinteger';
	o.default = '5';

	o = s.option(form.Value, 'mem_percent', _('内存使用率（%）'),
		_('按 MemAvailable 计算。'));
	o.datatype = 'range(1,100)';
	o.default = '90';
	o = s.option(form.Value, 'mem_hold_min', _('持续时间（分钟）'));
	o.datatype = 'uinteger';
	o.default = '5';

	o = s.option(form.Value, 'disk_percent', _('磁盘已用（%）'));
	o.datatype = 'range(1,100)';
	o.default = '90';

	o = s.option(form.DynamicList, 'disk_path', _('磁盘检查路径'),
		_('对每个路径所在文件系统检查一次。默认 / 与 /overlay。'));
	o.default = '/';
	o.rmempty = false;

	o = s.option(form.Value, 'temp_c', _('温度（℃）'));
	o.datatype = 'uinteger';
	o.default = '80';
	o = s.option(form.Value, 'temp_hold_min', _('持续时间（分钟）'));
	o.datatype = 'uinteger';
	o.default = '5';

	o = s.option(form.Value, 'conn_percent', _('连接跟踪占用（%）'));
	o.datatype = 'range(1,100)';
	o.default = '80';

	o = s.option(form.Value, 'wan_bw_percent', _('WAN 带宽占用配置上限的（%）'),
		_('需在接口上填写 lede_bw_down / lede_bw_up（Mbit/s）。未填则不检测该方向。'));
	o.datatype = 'range(1,100)';
	o.default = '90';
	o = s.option(form.Value, 'wan_bw_hold_min', _('持续时间（分钟）'),
		_('每个 WAN 的上行、下行分别计时；低于阈值后重新计时。'));
	o.datatype = 'uinteger';
	o.default = '5';

	o = s.option(form.Value, 'login_fail_n', _('10 分钟内登录失败次数'));
	o.datatype = 'uinteger';
	o.default = '5';

	o = s.option(form.Value, 'dns_fail_n', _('MosDNS 上游连续失败次数'),
		_('仅 MosDNS 已启用时检测。向 127.0.0.1 的 MosDNS 端口查国内/国外测试域名。连续这么多次无应答才记一次。国外失败时再按 WAN 分端口查。'));
	o.datatype = 'uinteger';
	o.default = '2';

	s = m.section(form.NamedSection, 'main', 'wanalert', _('客户端突发'));
	s.addremove = false;
	s.description = _('按连接跟踪字节差估算 LAN 客户端速率，日志含 MAC 与 IP。超过阈值即记一条；持续达到设定秒数才视为可推送的告警。上下行分开。限速惩罚未启用。');

	o = s.option(form.Value, 'burst_down_mbps', _('下行超过（Mbit/s）'));
	o.datatype = 'ufloat';
	o.default = '50';

	o = s.option(form.Value, 'burst_up_mbps', _('上行超过（Mbit/s）'));
	o.datatype = 'ufloat';
	o.default = '20';

	o = s.option(form.Value, 'burst_hold_sec', _('持续（秒）后才告警'));
	o.datatype = 'uinteger';
	o.default = '60';

	return m;
	}
});
