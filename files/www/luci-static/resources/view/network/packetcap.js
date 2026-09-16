'use strict';
'require view';
'require fs';
'require ui';
'require uci';
'require poll';

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	state: {},
	polling: false,

	parseStatus(r) {
		const raw = String((r && r.stdout) || '').trim();
		const i = raw.indexOf('{');
		const j = raw.lastIndexOf('}');
		if (i < 0 || j <= i)
			return null;
		try {
			return JSON.parse(raw.slice(i, j + 1));
		} catch (e) {
			return null;
		}
	},

	load() {
		return Promise.all([
			uci.load('packet_cap').catch(() => null),
			fs.exec('/usr/libexec/packet-cap', ['status']).then(r => this.parseStatus(r) || {}),
			fs.exec('/usr/libexec/packet-cap', ['ifaces']).then(r =>
				(r.stdout || '').trim().split(/\n/).filter(Boolean)
			).catch(() => [])
		]);
	},

	saveCapDir(dir, notify) {
		dir = String(dir || '').trim() || '/overlay/pcap';
		if (!dir.startsWith('/'))
			dir = '/' + dir;
		if (!uci.get('packet_cap', 'settings'))
			uci.add('packet_cap', 'settings', 'settings');
		uci.set('packet_cap', 'settings', 'cap_dir', dir);
		return uci.save().then(() => {
			if (notify)
				ui.addNotification(null, E('p', {}, _('存放路径已保存')), 'info');
		}).catch(() => Promise.resolve());
	},

	runAnalyze(mode) {
		return fs.exec('/usr/libexec/packet-cap', ['analyze-start', mode || 'overview']).then(r => {
			const st = this.parseStatus(r);
			if (st)
				this.state = st;
			return this.state;
		});
	},

	ensurePolling() {
		if (this.polling)
			return;
		this._pollFn = this._pollFn || L.bind(this.refreshStatus, this);
		this.polling = true;
		poll.add(this._pollFn, 2);
	},

	stopPolling() {
		if (!this.polling || !this._pollFn)
			return;
		poll.remove(this._pollFn);
		this.polling = false;
	},

	refreshStatus() {
		return fs.exec('/usr/libexec/packet-cap', ['status']).then(r => {
			const st = this.parseStatus(r);
			if (st)
				this.state = st;
			this.paintStatus();
			const a = this.state && this.state.analysis || {};
			const key = String(this.state.current_file || '') + ':' + String(a.finished || 0);
			const loadResult = a.state === 'done' && a.report_ready && this._resultLoadedFor !== key
				? this.loadAnalysisResult() : null;
			if (!this.state.active && a.state !== 'running')
				this.stopPolling();
			if (loadResult)
				return loadResult;
			return this.state;
		}).catch(e => {
			this.paintAnalysisError(e.message || String(e));
		});
	},

	paintStatus() {
		const st = this.state || {};
		const badge = document.getElementById('pcap-status-badge');
		const meta = document.getElementById('pcap-status-meta');
		const btnStart = document.getElementById('pcap-btn-start');
		const btnStop = document.getElementById('pcap-btn-stop');
		if (badge) {
			badge.textContent = st.active ? _('抓包中…') : _('空闲');
			badge.className = 'pcap-badge ' + (st.active ? 'on' : 'off');
		}
		if (meta) {
			const kb = st.size ? (Number(st.size) / 1024).toFixed(1) + ' KB' : '0';
			meta.textContent = st.current_file
				? (_('当前文件：') + st.current_name + ' · ' + kb)
				: _('尚未抓包');
		}
		if (btnStart) btnStart.disabled = !!st.active ||
			!!(st.analysis && st.analysis.state === 'running');
		if (btnStop) btnStop.disabled = !st.active;
		const dl = document.getElementById('pcap-dl');
		if (dl) {
			if (st.current_file)
				dl.href = '/cgi-bin/cgi-download?' + encodeURIComponent(st.current_file);
			else
				dl.removeAttribute('href');
		}
		this.paintAnalysisStatus();
	},

	analyzeCurrent(mode, outBox) {
		if (outBox)
			outBox.replaceChildren(E('p', { 'class': 'pcap-result-placeholder' }, _('后台分析任务正在启动…')));
		return this.runAnalyze(mode).then(() => {
			this._resultLoadedFor = null;
			this.paintAnalysisStatus();
			this.ensurePolling();
		}).catch(e => {
			this.paintAnalysisError(e.message || String(e));
		});
	},

	phaseLabel(phase) {
		return ({
			idle: _('等待分析'),
			queued: _('任务已排队'),
			preparing: _('准备分析环境'),
			tcp_scan: _('扫描 TCP 流、方向与异常'),
			dns_scan: _('整理 DNS 与站点信息'),
			finalizing: _('生成分析报告'),
			complete: _('分析完成'),
			cancelled: _('分析已取消'),
			interrupted: _('分析进程意外中断'),
			failed: _('分析失败')
		})[phase] || phase || _('等待分析');
	},

	paintAnalysisStatus() {
		const a = this.state && this.state.analysis || {};
		const wrap = document.getElementById('pcap-analysis-status');
		const badge = document.getElementById('pcap-analysis-badge');
		const fill = document.getElementById('pcap-analysis-progress-fill');
		const text = document.getElementById('pcap-analysis-progress-text');
		const btnAnalyze = document.getElementById('pcap-btn-analyze');
		const btnCancel = document.getElementById('pcap-btn-analysis-cancel');
		const running = a.state === 'running';
		const pct = Math.max(0, Math.min(100, Number(a.progress) || 0));
		if (wrap)
			wrap.style.display = '';
		if (badge) {
			badge.textContent = running ? _('后台分析中') :
				a.state === 'done' ? _('已完成') :
				a.state === 'failed' ? _('失败') :
				a.state === 'cancelled' ? _('已取消') : _('未分析');
			badge.className = 'pcap-badge ' + (running ? 'on' : a.state === 'failed' ? 'err' : 'off');
		}
		if (fill)
			fill.style.width = pct + '%';
		if (text)
			text.textContent = this.phaseLabel(a.phase) + (running ? ' · ' + pct + '%' : '');
		if (btnAnalyze)
			btnAnalyze.disabled = running || !!(this.state && this.state.active) || !this.state.current_file;
		if (btnCancel)
			btnCancel.disabled = !running;
		if (a.error)
			this.paintAnalysisError(a.error);
	},

	paintAnalysisError(message) {
		if (!this._outBox)
			return;
		this._outBox.replaceChildren(E('div', { 'class': 'alert-message warning' }, String(message || _('分析失败'))));
	},

	parseAnalysisResult(raw) {
		const out = {
			meta: {}, file: {}, dirs: {}, flows: [], minutes: [], events: [], dns: [], notices: [], raw: []
		};
		String(raw || '').split(/\r?\n/).forEach(line => {
			if (!line)
				return;
			const p = line.split('\t');
			switch (p[0]) {
			case 'FILE':
				out.file = { name: p[1], size: +p[2] || 0, iface: p[3] || '', mode: p[4] || '' };
				break;
			case 'META':
				out.meta[p[1]] = p[2];
				break;
			case 'DIR':
				out.dirs[p[1]] = { packets: +p[2] || 0, bytes: +p[3] || 0, retrans: +p[4] || 0, dupack: +p[5] || 0, rst: +p[6] || 0 };
				break;
			case 'FLOW':
				out.flows.push({
					stream: p[1], peer: p[2], port: p[3], start: +p[4] || 0, end: +p[5] || 0,
					duration: +p[6] || 0, cPackets: +p[7] || 0, cBytes: +p[8] || 0,
					sPackets: +p[9] || 0, sBytes: +p[10] || 0, cRetrans: +p[11] || 0,
					sRetrans: +p[12] || 0, cDup: +p[13] || 0, sDup: +p[14] || 0,
					rst: +p[15] || 0, fin: +p[16] || 0, maxGap: +p[17] || 0,
					rtt: +p[18] || 0, sni: p[19] || ''
				});
				break;
			case 'MINUTE':
				out.minutes.push({ minute: +p[1] || 0, cPackets: +p[2] || 0, cBytes: +p[3] || 0, sPackets: +p[4] || 0, sBytes: +p[5] || 0, retrans: +p[6] || 0, dupack: +p[7] || 0 });
				break;
			case 'EVENT':
				out.events.push({ time: +p[1] || 0, stream: p[2], src: p[3], dst: p[4], kind: p[5], detail: p.slice(6).join(' ') });
				break;
			case 'DNS':
				out.dns.push({ time: +p[1] || 0, src: p[2], dst: p[3], type: p[4], response: p[5], name: p[6], answer: p[7], delay: +p[8] || 0 });
				break;
			case 'NOTICE':
				out.notices.push({ level: p[1], title: p[2], detail: p.slice(3).join(' ') });
				break;
			case 'RAW':
				out.raw.push(p.slice(1).join(' '));
				break;
			}
		});
		return out;
	},

	formatBytes(n) {
		n = Number(n) || 0;
		if (n >= 1073741824) return (n / 1073741824).toFixed(2) + ' GiB';
		if (n >= 1048576) return (n / 1048576).toFixed(2) + ' MiB';
		if (n >= 1024) return (n / 1024).toFixed(1) + ' KiB';
		return n + ' B';
	},

	formatDuration(sec) {
		sec = Number(sec) || 0;
		if (sec >= 60)
			return Math.floor(sec / 60) + _(' 分 ') + (sec % 60).toFixed(1) + _(' 秒');
		return sec.toFixed(3) + _(' 秒');
	},

	makeResultTable(headers, rows, classes) {
		return E('div', { 'class': 'pcap-table-wrap' }, [
			E('table', { 'class': 'table pcap-result-table ' + (classes || '') }, [
				E('thead', {}, [E('tr', {}, headers.map(h => E('th', {}, h)))]),
				E('tbody', {}, rows.map(r => E('tr', {}, r.map(c => E('td', {}, c)))))
			])
		]);
	},

	renderAnalysisResult(result) {
		const meta = result.meta || {};
		const c2s = result.dirs.C2S || {};
		const s2c = result.dirs.S2C || {};
		const raw = +meta.tcp_records || 0;
		const unique = +meta.unique_tcp || 0;
		const duplicates = +meta.duplicates || 0;
		const dupPct = raw ? duplicates * 100 / raw : 0;
		const cRetPct = c2s.packets ? c2s.retrans * 100 / c2s.packets : 0;
		const sRetPct = s2c.packets ? s2c.retrans * 100 / s2c.packets : 0;
		const flows = result.flows.slice().sort((a, b) =>
			(b.cBytes + b.sBytes) - (a.cBytes + a.sBytes));
		const topFlows = flows.slice(0, 30);
		const totalBytes = (+c2s.bytes || 0) + (+s2c.bytes || 0);
		const topShare = topFlows[0] && totalBytes ? (topFlows[0].cBytes + topFlows[0].sBytes) * 100 / totalBytes : 0;
		const maxMinute = result.minutes.reduce((max, m) =>
			Math.max(max, m.cBytes, m.sBytes), 1);
		const findings = [];

		if (dupPct >= 10)
			findings.push(['warning', _('抓包存在重复副本'), _('已识别并排除 %s 条（%s%%）；常见于 any 同时记录物理接口与软件桥。').format(duplicates, dupPct.toFixed(1))]);
		else
			findings.push(['success', _('抓包重复较少'), _('重复副本 %s 条（%s%%）。').format(duplicates, dupPct.toFixed(1))]);
		if (sRetPct >= 2)
			findings.push(['danger', _('服务器到客户端方向丢包明显'), _('重传 %s 条，占该方向包数 %s%%。').format(s2c.retrans || 0, sRetPct.toFixed(2))]);
		else if (sRetPct >= 0.5)
			findings.push(['warning', _('服务器到客户端存在轻度重传'), _('重传 %s 条，占该方向包数 %s%%。').format(s2c.retrans || 0, sRetPct.toFixed(2))]);
		else
			findings.push(['success', _('服务器到客户端总体稳定'), _('重传率 %s%%。').format(sRetPct.toFixed(2))]);
		if ((+meta.zero_window || 0) || (+meta.window_full || 0))
			findings.push(['danger', _('发现接收端背压'), _('Zero Window %s，Window Full %s。').format(meta.zero_window || 0, meta.window_full || 0)]);
		else
			findings.push(['success', _('未发现接收窗口阻塞'), _('Zero Window 与 Window Full 均为 0。')]);
		if (topFlows[0] && topShare >= 70)
			findings.push(['info', _('流量高度集中'), _('%s 占总 TCP 负载 %s%%。').format(topFlows[0].sni || (topFlows[0].peer + ':' + topFlows[0].port), topShare.toFixed(1))]);

		const summary = E('div', { 'class': 'pcap-summary-grid' }, [
			E('div', { 'class': 'pcap-stat' }, [E('strong', {}, this.formatDuration(+meta.duration || 0)), E('span', {}, _('分析时长'))]),
			E('div', { 'class': 'pcap-stat' }, [E('strong', {}, String(raw)), E('span', {}, _('原始 TCP 记录'))]),
			E('div', { 'class': 'pcap-stat warn' }, [E('strong', {}, duplicates + ' / ' + dupPct.toFixed(1) + '%'), E('span', {}, _('已排除重复副本'))]),
			E('div', { 'class': 'pcap-stat' }, [E('strong', {}, String(unique)), E('span', {}, _('去重后 TCP 包'))])
		]);

		const direction = E('div', { 'class': 'pcap-direction-grid' }, [
			E('div', { 'class': 'pcap-direction-box' }, [
				E('strong', {}, (meta.client || _('客户端')) + ' → ' + _('服务器')),
				E('span', {}, this.formatBytes(c2s.bytes) + ' · ' + (c2s.packets || 0) + _(' 包')),
				E('small', {}, _('重传 %s（%s%%），重复 ACK %s').format(c2s.retrans || 0, cRetPct.toFixed(2), c2s.dupack || 0))
			]),
			E('div', { 'class': 'pcap-flow-arrow' }, '⇄'),
			E('div', { 'class': 'pcap-direction-box' }, [
				E('strong', {}, _('服务器') + ' → ' + (meta.client || _('客户端'))),
				E('span', {}, this.formatBytes(s2c.bytes) + ' · ' + (s2c.packets || 0) + _(' 包')),
				E('small', {}, _('重传 %s（%s%%），重复 ACK %s').format(s2c.retrans || 0, sRetPct.toFixed(2), s2c.dupack || 0))
			])
		]);

		const findingNodes = findings.map(f => E('div', { 'class': 'pcap-finding ' + f[0] }, [
			E('strong', {}, f[1]), E('span', {}, f[2])
		]));

		const flowRows = topFlows.map(f => [
			f.stream,
			f.sni || (f.peer + ':' + f.port),
			this.formatDuration(f.duration),
			this.formatBytes(f.cBytes),
			this.formatBytes(f.sBytes),
			String(f.cRetrans + f.sRetrans),
			f.rtt ? f.rtt.toFixed(1) + ' ms' : '—',
			f.maxGap ? f.maxGap.toFixed(2) + ' s' : '—',
			f.rst ? _('RST %s').format(f.rst) : f.fin ? _('正常关闭') : _('未见关闭')
		]);

		const minuteRows = result.minutes.map(m => E('div', { 'class': 'pcap-minute-row' }, [
			E('span', { 'class': 'pcap-minute-label' }, _('第 %s 分钟').format(m.minute)),
			E('div', { 'class': 'pcap-minute-bars' }, [
				E('div', { 'class': 'pcap-minute-bar down', 'style': 'width:' + (m.sBytes * 100 / maxMinute).toFixed(2) + '%' }),
				E('div', { 'class': 'pcap-minute-bar up', 'style': 'width:' + (m.cBytes * 100 / maxMinute).toFixed(2) + '%' })
			]),
			E('span', { 'class': 'pcap-minute-value' }, _('下 ') + this.formatBytes(m.sBytes) + _(' / 上 ') + this.formatBytes(m.cBytes) + _(' / 重传 ') + m.retrans)
		]));

		const eventNames = {
			SYN: _('客户端发起连接'), SYN_ACK: _('对端接受连接'), TLS_SNI: _('TLS 访问站点'),
			FIN: _('正常关闭'), RST: _('连接重置'), RETRANS: _('TCP 重传')
		};
		const eventRows = result.events.slice(0, 160).map(e => [
			e.time.toFixed(3) + ' s', e.stream, e.src + ' → ' + e.dst,
			eventNames[e.kind] || e.kind, e.detail || '—'
		]);
		const dnsRows = result.dns.slice(0, 80).map(d => [
			d.time.toFixed(3) + ' s', d.src + ' → ' + d.dst, d.name,
			d.response === '1' || /true/i.test(d.response) ? (d.answer || _('无地址记录')) : _('查询'),
			d.delay ? (d.delay * 1000).toFixed(2) + ' ms' : '—'
		]);

		const modules = [
			E('section', { 'class': 'pcap-result-module' }, [
				E('h4', {}, _('分析摘要')), summary,
				E('p', { 'class': 'hint' }, _('文件：%s · 接口：%s · 客户端：%s').format(result.file.name || '—', result.file.iface || '—', meta.client || _('自动识别失败')))
			]),
			E('section', { 'class': 'pcap-result-module' }, [E('h4', {}, _('数据流动方向')), direction]),
			E('section', { 'class': 'pcap-result-module' }, [E('h4', {}, _('自动发现的问题')), E('div', { 'class': 'pcap-findings' }, findingNodes)]),
			E('section', { 'class': 'pcap-result-module' }, [
				E('h4', {}, _('主要 TCP 数据流')),
				this.makeResultTable(
					[_('流'), _('站点 / 对端'), _('持续'), _('客户端→服务器'), _('服务器→客户端'), _('重传'), _('WAN ACK RTT'), _('最大间隔'), _('结束')],
					flowRows, 'pcap-flow-table')
			]),
			E('section', { 'class': 'pcap-result-module' }, [
				E('h4', {}, _('每分钟流量与异常')),
				E('div', { 'class': 'pcap-minute-legend' }, [
					E('span', { 'class': 'down' }, _('服务器→客户端')),
					E('span', { 'class': 'up' }, _('客户端→服务器'))
				]),
				E('div', { 'class': 'pcap-minute-chart' }, minuteRows)
			]),
			eventRows.length ? E('section', { 'class': 'pcap-result-module' }, [
				E('h4', {}, _('按数据流方向排列的关键事件')),
				this.makeResultTable([_('相对时间'), _('流'), _('方向'), _('动作'), _('详情')], eventRows, 'pcap-event-table')
			]) : '',
			dnsRows.length ? E('section', { 'class': 'pcap-result-module' }, [
				E('h4', {}, _('DNS 查询与应答')),
				this.makeResultTable([_('相对时间'), _('方向'), _('域名'), _('结果'), _('响应耗时')], dnsRows)
			]) : '',
			result.raw.length ? E('section', { 'class': 'pcap-result-module' }, [
				E('h4', {}, _('原始数据包摘要')),
				E('pre', { 'class': 'pcap-raw-output' }, result.raw.join('\n'))
			]) : ''
		].filter(Boolean);
		result.notices.forEach(n => modules.splice(3, 0,
			E('div', { 'class': 'alert-message ' + n.level }, [
				E('strong', {}, n.title), ' ', n.detail
			])
		));
		return E('div', { 'class': 'pcap-analysis-modules' }, modules);
	},

	loadAnalysisResult() {
		if (!this._outBox)
			return Promise.resolve();
		return fs.exec('/usr/libexec/packet-cap', ['analyze-result']).then(r => {
			const raw = ((r.stdout || '') + (r.stderr || '')).trim();
			const result = this.parseAnalysisResult(raw);
			if (!result.file.name && !Object.keys(result.meta).length)
				throw new Error(raw || _('分析结果格式无效'));
			const a = this.state && this.state.analysis || {};
			this._resultLoadedFor = String(this.state.current_file || '') + ':' + String(a.finished || 0);
			this._outBox.replaceChildren(this.renderAnalysisResult(result));
		}).catch(e => this.paintAnalysisError(e.message || String(e)));
	},

	render(data) {
		const self = this;
		const capDir = uci.get('packet_cap', 'settings', 'cap_dir') || '/overlay/pcap';
		const ifaces = data[2] || [];
		this.state = data[1] || {};

		const dirInput = E('input', {
			'class': 'cbi-input-text',
			'style': 'min-width:280px',
			'value': capDir,
			'placeholder': '/overlay/pcap'
		});

		const ifaceSel = E('select', { 'class': 'cbi-input-select', 'id': 'pcap-iface', 'style': 'width:110px' });
		ifaces.forEach(n => ifaceSel.appendChild(E('option', { 'value': n }, n)));
		ifaceSel.appendChild(E('option', { 'value': 'any' }, 'any'));

		const filterSel = E('select', { 'class': 'cbi-input-select', 'id': 'pcap-filter', 'style': 'width:150px' }, [
			E('option', { 'value': '' }, _('全部流量')),
			E('option', { 'value': 'tcp' }, _('仅 TCP')),
			E('option', { 'value': 'udp' }, _('仅 UDP')),
			E('option', { 'value': 'icmp' }, _('仅 ICMP')),
			E('option', { 'value': 'arp' }, _('仅 ARP')),
			E('option', { 'value': 'port 53' }, _('DNS（53）')),
			E('option', { 'value': 'tcp port 80' }, _('HTTP（80）')),
			E('option', { 'value': 'tcp port 443' }, _('HTTPS（443）')),
			E('option', { 'value': 'tcp port 80 or tcp port 443' }, _('网页（80 或 443）')),
			E('option', { 'value': 'udp port 67 or udp port 68' }, _('DHCP')),
			E('option', { 'value': 'tcp port 22' }, _('SSH（22）')),
			E('option', { 'value': 'udp port 123' }, _('NTP（123）'))
		]);

		const srcInput = E('input', {
			'class': 'cbi-input-text',
			'style': 'width:118px',
			'placeholder': _('可选')
		});
		const dstInput = E('input', {
			'class': 'cbi-input-text',
			'style': 'width:118px',
			'placeholder': _('可选')
		});

		const stopSel = E('select', { 'class': 'cbi-input-select', 'id': 'pcap-stop', 'style': 'width:108px' }, [
			E('option', { 'value': 'manual', 'selected': 'selected' }, _('手动停止')),
			E('option', { 'value': 'T' }, _('按时长')),
			E('option', { 'value': 'P' }, _('按包数'))
		]);

		const limitInput = E('input', {
			'class': 'cbi-input-text',
			'type': 'number',
			'min': '1',
			'value': '30',
			'style': 'width:80px'
		});
		const limitWrap = E('span', { 'id': 'pcap-limit-wrap', 'style': 'display:none' }, [
			limitInput, ' ', E('span', { 'id': 'pcap-limit-unit' }, _('秒'))
		]);

		stopSel.addEventListener('change', function() {
			const v = stopSel.value;
			limitWrap.style.display = v === 'manual' ? 'none' : '';
			document.getElementById('pcap-limit-unit').textContent =
				v === 'P' ? _('包') : _('秒');
		});

		const validHost = function(v, label) {
			v = String(v || '').trim();
			if (!v)
				return '';
			if (!/^[A-Za-z0-9.:-]+$/.test(v))
				throw new Error(_('%s 只能包含字母、数字、点、冒号和短横线').format(label));
			return v;
		};

		const buildFilter = function() {
			const parts = [];
			const proto = String(filterSel.value || '').trim();
			const src = validHost(srcInput.value, _('源 IP'));
			const dst = validHost(dstInput.value, _('目的 IP'));
			if (proto)
				parts.push('(' + proto + ')');
			if (src)
				parts.push('src host ' + src);
			if (dst)
				parts.push('dst host ' + dst);
			return parts.join(' and ');
		};

		const outBox = E('div', {
			'id': 'pcap-analyze-out',
			'class': 'pcap-analysis-output'
		}, [
			E('p', { 'class': 'pcap-result-placeholder' },
				_('停止抓包后会在路由器后台分析。离开本页不会中断任务，重新进入可继续查看进度和结果。'))
		]);
		this._outBox = outBox;

		const btnStart = E('button', {
			'id': 'pcap-btn-start',
			'type': 'button',
			'class': 'btn cbi-button cbi-button-action',
			'click': ui.createHandlerFn(this, function(ev) {
				ev.preventDefault();
				let filter, limit, unit;
				try {
					filter = buildFilter();
				} catch (e) {
					ui.addNotification(null, E('p', {}, e.message || String(e)), 'error');
					return Promise.resolve();
				}
				if (stopSel.value === 'manual') {
					limit = '0';
					unit = 'T';
				} else {
					limit = String(limitInput.value || '0');
					unit = stopSel.value;
					if (!limit || Number(limit) <= 0) {
						ui.addNotification(null, E('p', {}, _('请填写停止数量')), 'error');
						return Promise.resolve();
					}
				}
				return self.saveCapDir(dirInput.value, false).then(() =>
					fs.exec('/usr/libexec/packet-cap', [
						'start',
						ifaceSel.value,
						filter || '',
						limit,
						unit,
						String(srcInput.value || '').trim()
					])
				).then(r => {
					const st = self.parseStatus(r);
					if (st) self.state = st;
					self.paintStatus();
					outBox.textContent = _('抓包已开始…');
					self.ensurePolling();
				}).catch(e => ui.addNotification(null, E('p', {}, e.message || String(e)), 'error'));
			})
		}, _('开始抓包'));

		const btnStop = E('button', {
			'id': 'pcap-btn-stop',
			'type': 'button',
			'class': 'btn cbi-button cbi-button-negative',
			'click': ui.createHandlerFn(this, function(ev) {
				ev.preventDefault();
				return fs.exec('/usr/libexec/packet-cap', ['stop']).then(r => {
					const st = self.parseStatus(r);
					if (st) self.state = st;
					else self.state = Object.assign({}, self.state, { active: 0 });
					self._resultLoadedFor = null;
					self.paintStatus();
					self.ensurePolling();
				}).catch(e => {
					ui.addNotification(null, E('p', {}, e.message || String(e)), 'error');
				});
			})
		}, _('停止并分析'));

		const dlLink = E('a', {
			'id': 'pcap-dl',
			'class': 'btn cbi-button',
			'target': '_blank',
			'rel': 'noreferrer'
		}, _('下载当前 pcap'));

		const btnAnalyze = E('button', {
			'id': 'pcap-btn-analyze',
			'type': 'button',
			'class': 'btn cbi-button cbi-button-action',
			'click': ui.createHandlerFn(this, () => this.analyzeCurrent('overview', outBox))
		}, _('开始 / 重新后台分析'));

		const btnCancelAnalysis = E('button', {
			'id': 'pcap-btn-analysis-cancel',
			'type': 'button',
			'class': 'btn cbi-button cbi-button-negative',
			'click': ui.createHandlerFn(this, () =>
				fs.exec('/usr/libexec/packet-cap', ['analyze-cancel']).then(r => {
					const st = this.parseStatus(r);
					if (st) this.state = st;
					this.paintAnalysisStatus();
				}).catch(e => this.paintAnalysisError(e.message || String(e)))
			)
		}, _('取消分析'));

		this.paintStatus();

		if (this.state.active || (this.state.analysis && this.state.analysis.state === 'running'))
			this.ensurePolling();
		window.setTimeout(() => {
			this.paintStatus();
			if (this.state.analysis && this.state.analysis.state === 'done' && this.state.analysis.report_ready)
				this.loadAnalysisResult();
		}, 0);

		return E('div', { 'class': 'cbi-map pcap-page' }, [
			E('style', {}, `
				.pcap-page { min-width:0; width:100%; box-sizing:border-box; }
				.pcap-page > h2 { margin:0 0 1rem; font-size:1.45rem; font-weight:700; line-height:1.2; }
				.pcap-page > p { margin:-.35rem 0 1.25rem; opacity:.72; line-height:1.55; }
				.pcap-card-stack { display:grid; grid-template-columns:minmax(0,1fr); gap:1rem; margin:0 0 1.25rem; }
				.pcap-card { min-width:0!important; margin:0!important; padding:1rem 1.1rem!important; box-sizing:border-box; background:var(--cbi-section-bg,#fff)!important; border:1px solid rgba(0,0,0,.08)!important; border-radius:8px!important; box-shadow:0 2px 6px rgba(0,0,0,.03)!important; }
				.pcap-card > h3 { display:flex; align-items:center; justify-content:space-between; margin:0 0 .85rem!important; padding:0 0 .7rem!important; border-bottom:1px solid rgba(125,125,125,.14); font-size:.98rem!important; font-weight:600!important; line-height:1.3; }
				.pcap-badge { display:inline-block; padding:2px 10px; border-radius:999px; font-size:12px; margin-left:8px; }
				.pcap-badge.on { background:#fdecea; color:#c0392b; }
				.pcap-badge.off { background:#e8f8ef; color:#1e8449; }
				.pcap-badge.err { background:#fdecea; color:#922b21; }
				.pcap-row { display:flex; flex-wrap:wrap; gap:10px; align-items:center; margin:8px 0; }
				.pcap-filters { display:flex; flex-wrap:wrap; gap:8px 12px; align-items:center; margin:8px 0; max-width:100%; }
				.pcap-field { display:flex; flex:0 1 auto; align-items:center; gap:6px; white-space:nowrap; min-width:0; }
				.pcap-field label { margin:0; }
				.pcap-field select, .pcap-field input { min-width:0; max-width:100%; }
				.pcap-analysis-status { margin:.25rem 0 1rem; }
				.pcap-analysis-status-line { display:flex; flex-wrap:wrap; align-items:center; gap:10px; margin-bottom:8px; }
				.pcap-progress { width:100%; height:8px; overflow:hidden; border-radius:999px; background:rgba(127,127,127,.18); }
				.pcap-progress > i { display:block; width:0; height:100%; background:var(--primary-color,#1677ff); transition:width .25s ease; }
				.pcap-analysis-output { min-width:0; width:100%; box-sizing:border-box; overflow-wrap:anywhere; }
				.pcap-result-placeholder { margin:12px 0; opacity:.7; }
				.pcap-analysis-modules { display:grid; grid-template-columns:minmax(0,1fr); gap:1rem; margin-top:1rem; }
				.pcap-result-module { min-width:0; width:100%; box-sizing:border-box; padding:1rem; border:1px solid rgba(127,127,127,.2); border-radius:8px; }
				.pcap-result-module > h4 { margin:0 0 .85rem; padding:0 0 .65rem; border-bottom:1px solid rgba(127,127,127,.16); font-size:.96rem; }
				.pcap-summary-grid { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:10px; }
				.pcap-stat { min-width:0; padding:12px; border-radius:7px; background:rgba(127,127,127,.08); }
				.pcap-stat strong,.pcap-stat span { display:block; }
				.pcap-stat strong { font-size:1.2rem; line-height:1.3; }
				.pcap-stat span { margin-top:4px; opacity:.68; font-size:.78rem; }
				.pcap-stat.warn strong { color:#b9770e; }
				.pcap-direction-grid { display:grid; grid-template-columns:minmax(0,1fr) 42px minmax(0,1fr); gap:12px; align-items:center; }
				.pcap-direction-box { padding:14px; border-radius:7px; background:rgba(127,127,127,.08); }
				.pcap-direction-box strong,.pcap-direction-box span,.pcap-direction-box small { display:block; }
				.pcap-direction-box span { margin-top:8px; font-size:1.05rem; }
				.pcap-direction-box small { margin-top:5px; opacity:.7; }
				.pcap-flow-arrow { text-align:center; font-size:1.35rem; opacity:.6; }
				.pcap-findings { display:grid; grid-template-columns:minmax(0,1fr); gap:8px; }
				.pcap-finding { padding:10px 12px; border-left:3px solid rgba(127,127,127,.4); background:rgba(127,127,127,.06); }
				.pcap-finding strong,.pcap-finding span { display:block; }
				.pcap-finding span { margin-top:3px; opacity:.75; font-size:.82rem; }
				.pcap-finding.success { border-left-color:#239b56; }
				.pcap-finding.warning { border-left-color:#d68910; }
				.pcap-finding.danger { border-left-color:#c0392b; }
				.pcap-finding.info { border-left-color:#2874a6; }
				.pcap-table-wrap { max-width:100%; overflow:auto; }
				.pcap-result-table { width:100%; min-width:760px; }
				.pcap-result-table th,.pcap-result-table td { white-space:nowrap; font-size:.78rem; }
				.pcap-result-table td:nth-child(2) { max-width:320px; overflow:hidden; text-overflow:ellipsis; }
				.pcap-minute-legend { display:flex; gap:18px; margin-bottom:10px; font-size:.78rem; opacity:.75; }
				.pcap-minute-legend span:before { content:''; display:inline-block; width:10px; height:10px; margin-right:5px; border-radius:2px; }
				.pcap-minute-legend .down:before,.pcap-minute-bar.down { background:#2874a6; }
				.pcap-minute-legend .up:before,.pcap-minute-bar.up { background:#239b56; }
				.pcap-minute-chart { display:grid; grid-template-columns:minmax(0,1fr); gap:5px; max-height:420px; overflow:auto; }
				.pcap-minute-row { display:grid; grid-template-columns:82px minmax(120px,1fr) minmax(210px,auto); gap:10px; align-items:center; font-size:.76rem; }
				.pcap-minute-bars { min-width:0; }
				.pcap-minute-bar { height:6px; min-width:1px; margin:2px 0; border-radius:2px; }
				.pcap-minute-value { text-align:right; white-space:nowrap; opacity:.75; }
				.pcap-raw-output { max-height:420px; overflow:auto; white-space:pre-wrap; font-size:12px; }
				@media (prefers-color-scheme:dark) {
					.pcap-card { background:rgba(255,255,255,.03)!important; border-color:rgba(255,255,255,.08)!important; box-shadow:none!important; }
					.pcap-card > h3 { border-bottom-color:rgba(255,255,255,.08); }
				}
				@media (max-width:720px) {
					.pcap-field { flex:1 1 210px; }
					.pcap-field select, .pcap-field input { flex:1 1 auto; width:auto!important; }
					.pcap-field:last-child { flex-basis:100%; }
					.pcap-summary-grid { grid-template-columns:repeat(2,minmax(0,1fr)); }
					.pcap-direction-grid { grid-template-columns:minmax(0,1fr); }
					.pcap-flow-arrow { transform:rotate(90deg); }
					.pcap-minute-row { grid-template-columns:72px minmax(90px,1fr); }
					.pcap-minute-value { grid-column:1/-1; text-align:left; padding-left:82px; }
				}
			`),
			E('h2', {}, _('抓包分析')),
			E('p', {}, _('同一页完成抓包与分析。停止后自动分析本次文件，无需再选手动文件。')),
			E('div', { 'class': 'pcap-card-stack' }, [
				E('div', { 'class': 'cbi-section pcap-card' }, [
					E('h3', {}, _('存放路径')),
					E('div', { 'class': 'pcap-row' }, [
						dirInput,
						E('button', {
							'type': 'button',
							'class': 'btn cbi-button',
							'click': ui.createHandlerFn(this, () => this.saveCapDir(dirInput.value, true))
						}, _('保存路径'))
					]),
					E('p', { 'class': 'hint' }, _('建议使用 /overlay/pcap 或 /data/pcap 等 root 专用目录；不要直接使用可被其他用户写入的 /tmp。'))
				]),
				E('div', { 'class': 'cbi-section pcap-card' }, [
					E('h3', {}, [
						_('抓包'),
						E('span', { 'id': 'pcap-status-badge', 'class': 'pcap-badge off' }, _('空闲'))
					]),
					E('div', { 'id': 'pcap-status-meta', 'class': 'hint' }),
					E('div', { 'class': 'pcap-filters' }, [
						E('span', { 'class': 'pcap-field' }, [E('label', {}, _('接口')), ifaceSel]),
						E('span', { 'class': 'pcap-field' }, [E('label', {}, _('协议')), filterSel]),
						E('span', { 'class': 'pcap-field' }, [E('label', {}, _('源 IP')), srcInput]),
						E('span', { 'class': 'pcap-field' }, [E('label', {}, _('目的 IP')), dstInput]),
						E('span', { 'class': 'pcap-field' }, [E('label', {}, _('停止')), stopSel, limitWrap]),
						E('span', { 'class': 'pcap-field' }, [btnStart, btnStop, dlLink])
					]),
				]),
				E('div', { 'class': 'cbi-section pcap-card' }, [
					E('h3', {}, [
						_('后台分析（当前抓包）'),
						E('span', { 'id': 'pcap-analysis-badge', 'class': 'pcap-badge off' }, _('未分析'))
					]),
					E('div', { 'id': 'pcap-analysis-status', 'class': 'pcap-analysis-status' }, [
						E('div', { 'class': 'pcap-analysis-status-line' }, [
							E('span', { 'id': 'pcap-analysis-progress-text' }, _('等待分析')),
							btnAnalyze,
							btnCancelAnalysis
						]),
						E('div', { 'class': 'pcap-progress' }, [
							E('i', { 'id': 'pcap-analysis-progress-fill' })
						])
					]),
					E('div', { 'class': 'pcap-row' }, [
						E('span', { 'class': 'hint' }, _('分析任务运行在路由器后台。切换 LuCI 页面、关闭浏览器或重新登录均不会中断；结果保存在 pcap 文件旁。'))
					]),
					outBox
				])
			])
		]);
	}
});
