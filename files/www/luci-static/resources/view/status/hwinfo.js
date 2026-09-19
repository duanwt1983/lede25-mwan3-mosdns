'use strict';
'require view';
'require rpc';

const callHwinfo = rpc.declare({
	object: 'wanmonitor',
	method: 'hwinfo',
	expect: {}
});

function dash(v) {
	if (v == null)
		return '—';
	const s = String(v).trim();
	if (s === '' || s === 'None' || s === 'Unknown' || s === 'Not Specified' ||
		s === 'To Be Filled By O.E.M.' || s === 'To be filled by O.E.M.')
		return '—';
	return s;
}

function kbGiB(s) {
	const n = parseInt(String(s || '').replace(/[^0-9]/g, ''), 10);
	if (!isFinite(n) || n <= 0)
		return '—';
	return (n / 1048576).toFixed(1) + ' GB';
}

function khzGHz(v) {
	const n = Number(v);
	if (!isFinite(n) || n <= 0)
		return '—';
	if (n > 10000)
		return (n / 1e6).toFixed(2) + ' GHz';
	if (n > 100)
		return (n / 1e3).toFixed(0) + ' MHz';
	return n.toFixed(0) + ' MHz';
}

function milliC(v) {
	let n = Number(String(v || '').replace(/[^0-9.-]/g, ''));
	if (!isFinite(n) || n === 0)
		return null;
	if (Math.abs(n) > 200)
		n = n / 1000;
	return n.toFixed(1) + ' ℃';
}

function kv(rows) {
	const tbl = E('table', { 'class': 'table' });
	let n = 0;
	(rows || []).forEach(function(r) {
		if (!r || r[1] == null || r[1] === '' || r[1] === '—')
			return;
		n++;
		tbl.appendChild(E('tr', { 'class': 'tr' }, [
			E('td', { 'class': 'td hw-k' }, r[0]),
			E('td', { 'class': 'td' }, String(r[1]))
		]));
	});
	if (!n)
		tbl.appendChild(E('tr', { 'class': 'tr' }, E('td', { 'class': 'td' }, '暂无')));
	return tbl;
}

function grid(headers, lines) {
	if (!lines.length)
		return E('p', { 'class': 'hw-empty' }, '暂无');
	const tbl = E('table', { 'class': 'table' });
	tbl.appendChild(E('tr', { 'class': 'tr table-titles' },
		headers.map(function(h) { return E('th', { 'class': 'th' }, h); })));
	lines.forEach(function(row) {
		tbl.appendChild(E('tr', { 'class': 'tr' }, row.map(function(c) {
			return E('td', { 'class': 'td' }, c == null || c === '' ? '—' : String(c));
		})));
	});
	return tbl;
}

function card(title, node) {
	return E('div', { 'class': 'hw-card' }, [E('h3', {}, title), node]);
}

function vendorZh(id) {
	const m = {
		GenuineIntel: '英特尔',
		AuthenticAMD: 'AMD',
		Intel: '英特尔'
	};
	return m[id] || dash(id);
}

function mediaZh(rot) {
	if (rot === '0' || rot === 0)
		return '固态硬盘';
	if (rot === '1' || rot === 1)
		return '机械硬盘';
	return '未知介质';
}

function linkZh(st) {
	const m = { up: '已连接', down: '未连接', dormant: '休眠', unknown: '未知' };
	return m[st] || dash(st);
}

function duplexZh(d) {
	if (d === 'full')
		return '全双工';
	if (d === 'half')
		return '半双工';
	return dash(d);
}

function speedZh(s) {
	const n = Number(s);
	if (!isFinite(n) || n <= 0)
		return '—';
	return n + ' Mbps';
}

function sensorNameZh(name) {
	const n = String(name || '');
	if (/coretemp|k10temp|zenpower|cpu/i.test(n))
		return 'CPU 温度';
	if (/acpitz|thermal/i.test(n))
		return '主板热区';
	if (/nvme/i.test(n))
		return 'NVMe 温度';
	if (/iwlwifi|ath|wireless/i.test(n))
		return '无线网卡温度';
	if (/pch|isa/i.test(n))
		return '芯片组';
	return n || '传感器';
}

function smartSummary(smart) {
	if (!smart)
		return '未检测';
	if (!smart.available)
		return '本机无 SMART 工具，无法读健康度（下一版固件会带上）';
	const h = String(smart.health || '');
	if (/PASSED|OK/i.test(h))
		return 'SMART 总体：通过';
	if (/FAILED|FAILING/i.test(h))
		return 'SMART 总体：失败，建议备份换盘';
	if (/STANDBY|sleeping|skipped/i.test(h) || /STANDBY|sleeping/i.test(String(smart.identify || '')))
		return '磁盘休眠中，未唤醒检测';
	return '已读取 SMART，结论不明确';
}

function cpuFreqSummary(cpu) {
	const list = cpu.cpufreq || [];
	let max = 0, min = 0, cur = 0;
	list.forEach(function(r) {
		const a = Number(r.max_khz) || 0;
		const b = Number(r.min_khz) || 0;
		const c = Number(r.cur_khz) || 0;
		if (a > max)
			max = a;
		if (b && (!min || b < min))
			min = b;
		if (c > cur)
			cur = c;
	});
	const mhz = Number(cpu.mhz) || 0;
	return {
		max: max ? khzGHz(max) : (mhz ? mhz.toFixed(0) + ' MHz' : '—'),
		min: min ? khzGHz(min) : '—',
		cur: cur ? khzGHz(cur) : (mhz ? mhz.toFixed(0) + ' MHz' : '—')
	};
}

function parsePciLine(line) {
	line = String(line || '');
	const m = line.match(/^([0-9a-fA-F:.]+)\s+(.+?)\s+\[([0-9a-fA-F]{4})\]:\s+(.+?)\s+\[[0-9a-fA-F]{4}:[0-9a-fA-F]{4}\]/);
	if (m)
		return { slot: m[1], class_name: m[2], class_id: m[3], chip: m[4] };
	return { slot: '', class_name: '', class_id: '', chip: line.replace(/\[[0-9a-fA-F:]+\]/g, '').replace(/\s+/g, ' ').trim() };
}

function chassisZh(t) {
	const m = {
		'1': '其他', '3': '台式机', '4': '薄型台式机', '5': '扁平机箱',
		'6': '迷你塔式', '7': '塔式', '8': '便携', '9': '笔记本', '10': '笔记本',
		'13': '一体机', '16': '午餐盒', '17': '服务器机箱', '23': '迷你主机', '24': '棒式电脑'
	};
	const s = String(t || '').trim();
	if (m[s])
		return m[s];
	const low = s.toLowerCase();
	if (/desktop/.test(low))
		return '台式机';
	if (/tower/.test(low))
		return '塔式';
	if (/server/.test(low))
		return '服务器机箱';
	if (/mini/.test(low))
		return '迷你主机';
	if (/laptop|notebook/.test(low))
		return '笔记本';
	return dash(t);
}

function portZh(p) {
	const s = String(p || '');
	if (/Twisted Pair/i.test(s))
		return '电口 (RJ45)';
	if (/FIBRE|Fiber/i.test(s))
		return '光口';
	if (/Direct Attach|DAC/i.test(s))
		return '高速铜缆';
	if (/None|Unknown/i.test(s))
		return '—';
	return dash(p);
}

function hexId(v) {
	return String(v || '').toLowerCase().replace(/^0x/, '');
}

function knownChip(vendor, device, fallback) {
	const id = hexId(vendor) + ':' + hexId(device);
	const map = {
		'8086:125c': '英特尔 I226 2.5G 电口网卡',
		'8086:125b': '英特尔 I226-LM 2.5G 网卡',
		'8086:15f3': '英特尔 I225-V 2.5G 网卡',
		'8086:15f2': '英特尔 I225-LM 2.5G 网卡',
		'8086:1533': '英特尔 I210 千兆网卡',
		'8086:1539': '英特尔 I211 千兆网卡',
		'8086:10d3': '英特尔 82574L 千兆网卡',
		'8086:10fb': '英特尔 82599ES 10G SFP+',
		'8086:10f8': '英特尔 82599 10G 网卡',
		'8086:1572': '英特尔 X710 10G 网卡',
		'8086:0154': '第三代酷睿内存控制器',
		'8086:0151': '第三代酷睿 PCIe 根端口',
		'8086:0166': '核芯显卡 HD 4000',
		'8086:1e31': '7 系列 USB 3.0 控制器',
		'8086:1e2d': '7 系列 USB 2.0 控制器',
		'8086:1e26': '7 系列 USB 2.0 控制器',
		'8086:1e20': '7 系列高清音频',
		'8086:1e57': 'HM77 芯片组 LPC',
		'8086:1e03': '7 系列 SATA (AHCI)',
		'8086:1e22': '7 系列 SMBus',
		'8086:1e3a': '主板管理引擎 (ME)'
	};
	if (map[id])
		return map[id];
	const name = chipName(fallback);
	if (name === '—' || /^Intel Corporation Device$/i.test(fallback || ''))
		return dash(id === ':' ? '' : id);
	return name;
}

function pciKind(p) {
	const id = String(p.class_id || '').toLowerCase().replace(/^0x/, '');
	const n = String(p.class_name || p.chip || '').toLowerCase();
	const code = id.length >= 4 ? id.slice(-4) : id;
	if (code === '0200' || /ethernet/.test(n))
		return { group: 1, label: '有线网卡' };
	if (code === '0280' || /network controller|wireless|wifi/.test(n))
		return { group: 1, label: '无线网卡' };
	if (code === '0108' || /non-volatile|nvme/.test(n))
		return { group: 2, label: 'NVMe 控制器' };
	if (code === '0106' || /sata/.test(n))
		return { group: 2, label: 'SATA 控制器' };
	if (code === '0107' || /sas/.test(n))
		return { group: 2, label: 'SAS 控制器' };
	if (code === '0104' || /raid/.test(n))
		return { group: 2, label: 'RAID 控制器' };
	if (code === '0101' || /ide/.test(n))
		return { group: 2, label: 'IDE 控制器' };
	if (code === '0100' || /scsi/.test(n))
		return { group: 2, label: 'SCSI 控制器' };
	if (code === '0c03' || /^usb/.test(n))
		return { group: 3, label: 'USB 控制器' };
	if (code === '0c05' || /smbus/.test(n))
		return { group: 4, label: 'SMBus' };
	if (code === '0300' || /vga|display/.test(n))
		return { group: 5, label: '显示' };
	if (code === '0403' || /audio|multimedia/.test(n))
		return { group: 5, label: '音频' };
	if (code === '0780' || /communication/.test(n))
		return { group: 4, label: '管理引擎' };
	if (code === '0600' || /host bridge/.test(n))
		return { group: 4, label: '内存控制器' };
	if (code === '0601' || /isa bridge|lpc/.test(n))
		return { group: 4, label: '芯片组' };
	if (code === '0604' || /pci bridge/.test(n))
		return { group: 9, label: 'PCI 桥' };
	if (code === '0880' || /system peripheral/.test(n))
		return { group: 4, label: '芯片组设备' };
	if (code === '0700' || /serial/.test(n))
		return { group: 6, label: '串口' };
	if (code === '0805' || /sd host/.test(n))
		return { group: 2, label: 'SD 控制器' };
	return { group: 6, label: dash(p.class_name) === '—' ? '其他' : p.class_name };
}

function chipName(s) {
	return dash(String(s || '').replace(/\s*\(rev [^)]+\)/g, '').replace(/\s+/g, ' ').trim());
}

function chipsetFromPci(pci) {
	let lpc = '', host = '';
	(pci || []).forEach(function(p) {
		const id = String(p.class_id || '').toLowerCase();
		if (id === '0601' && !lpc)
			lpc = knownChip(p.vendor_id, p.device_id, p.chip);
		if (id === '0600' && !host)
			host = knownChip(p.vendor_id, p.device_id, p.chip);
	});
	return [lpc, host].filter(function(x) { return x && x !== '—'; }).join(' / ') || '—';
}

function machineCard(m, pci) {
	m = m || {};
	return kv([
		['主板厂商', dash(m.board_vendor) !== '—' ? dash(m.board_vendor) : dash(m.sys_vendor)],
		['主板型号', dash(m.board_name) !== '—' ? dash(m.board_name) : dash(m.product_name)],
		['芯片组', chipsetFromPci(pci)],
		['CPU 接口', dash(m.cpu_socket)],
		['支持内存', dash(m.memory_spec)],
		['主板版本', dash(m.board_version)],
		['主板类型', dash(m.board_type)],
		['主板序列号', dash(m.board_serial)],
		['资产标签', dash(m.board_asset_tag)],
		['整机型号', dash(m.product_name)],
		['产品系列', dash(m.product_family)],
		['产品版本', dash(m.product_version)],
		['SKU', dash(m.product_sku)],
		['BIOS 厂商', dash(m.bios_vendor)],
		['BIOS 版本', dash(m.bios_version)],
		['BIOS 日期', dash(m.bios_date)],
		['BIOS 修订', dash(m.bios_revision || m.bios_release)],
		['BIOS 容量', dash(m.bios_rom_size)]
	]);
}

function psuFilled(p) {
	if (!p)
		return false;
	const keys = ['name', 'manufacturer', 'model', 'serial', 'max_power', 'type', 'status'];
	for (let i = 0; i < keys.length; i++) {
		const v = dash(p[keys[i]]);
		if (v !== '—' && v !== 'Unknown' && !/^sysfs:/.test(v))
			return true;
	}
	return false;
}

function powerCard(list) {
	const rows = (list || []).filter(psuFilled);
	if (!rows.length)
		return E('p', { 'class': 'hw-empty' }, '主板未登记电源规格。外置 ATX 电源一般只能看电源外壳铭牌，DMI 里常常是空的。');
	const wrap = E('div', {});
	rows.forEach(function(p, i) {
		if (rows.length > 1)
			wrap.appendChild(E('h4', {}, '电源 ' + (i + 1)));
		wrap.appendChild(kv([
			['名称', dash(p.name)],
			['厂商', dash(p.manufacturer)],
			['型号', dash(p.model)],
			['额定功率', dash(p.max_power)],
			['类型', dash(p.type)],
			['状态', dash(p.status)],
			['输入切换', dash(p.input)],
			['安装位置', dash(p.location)],
			['序列号', dash(p.serial)],
			['修订', dash(p.revision)],
			['可热插拔', dash(p.hot_replace)]
		]));
	});
	return wrap;
}

function cpuCard(cpu) {
	cpu = cpu || {};
	const f = cpuFreqSummary(cpu);
	return kv([
		['型号', dash(cpu.model)],
		['厂商', vendorZh(cpu.vendor)],
		['逻辑核心', cpu.logical != null ? String(cpu.logical) : '—'],
		['物理核心', dash(cpu.cores)],
		['当前频率', f.cur],
		['最高频率', f.max],
		['最低频率', f.min],
		['缓存', dash(cpu.cache)]
	]);
}

function memCard(mem) {
	mem = mem || {};
	const info = mem.meminfo || {};
	const wrap = E('div', {});
	const dimms = (mem.dimms || []).filter(function(r) {
		const sz = String(r.Size || '');
		return sz && sz !== 'No Module Installed' && sz !== 'Not Installed';
	});
	wrap.appendChild(kv([
		['安装容量', kbGiB(info.MemTotal)],
		['接口类型', dash(mem.kind || (dimms[0] && dimms[0].Type))],
		['当前频率', dash(mem.speed || (dimms[0] && (dimms[0]['Configured Memory Speed'] || dimms[0].Speed)))],
		['封装', dash(mem.form || (dimms[0] && dimms[0]['Form Factor']))],
		['已安装', dimms.length ? String(dimms.length) + ' 条' : '—']
	]));
	if (dimms.length) {
		wrap.appendChild(E('h4', {}, '内存条'));
		wrap.appendChild(grid(
			['位置', '容量', '类型', '频率', '厂商', '型号'],
			dimms.map(function(r) {
				return [
					dash(r.Locator || r['Bank Locator']),
					dash(r.Size),
					dash(r.Type),
					dash(r['Configured Memory Speed'] || r.Speed),
					dash(r.Manufacturer),
					dash(r['Part Number'])
				];
			})
		));
	}
	if (mem.edac && mem.edac.length) {
		wrap.appendChild(E('h4', {}, 'ECC 错误'));
		wrap.appendChild(grid(
			['控制器', '可校正', '不可校正', '容量 MB'],
			mem.edac.map(function(e) {
				return [dash(e.mc_name || e.mc), dash(e.ce_count), dash(e.ue_count), dash(e.size_mb)];
			})
		));
	}
	return wrap;
}

function diskCard(disks) {
	const rows = (disks || []).filter(function(d) {
		return d && d.name && !/^loop|^zram|^ram/.test(d.name);
	});
	if (!rows.length)
		return E('p', { 'class': 'hw-empty' }, '未发现磁盘');
	return grid(
		['设备', '介质', '容量', '型号', '序列号', '健康'],
		rows.map(function(d) {
			return [
				dash(d.node || d.name),
				mediaZh(d.rotational),
				dash(d.size),
				dash((d.model || '') + (d.vendor && String(d.vendor).trim() ? '（' + String(d.vendor).trim() + '）' : '')),
				dash(d.serial),
				smartSummary(d.smart)
			];
		})
	);
}

function nicCard(nics) {
	const rows = (nics || []).filter(function(n) {
		return n && n.name && n.name !== 'lo';
	});
	if (!rows.length)
		return E('p', { 'class': 'hw-empty' }, '未发现物理网卡');
	return grid(
		['网口', '芯片', '总线位置', 'MAC 地址', '端口', '当前链路', '最高速率', '固件'],
		rows.map(function(n) {
			const link = n.operstate === 'up'
				? (speedZh(n.speed) + (duplexZh(n.duplex) !== '—' ? ' ' + duplexZh(n.duplex) : ''))
				: linkZh(n.operstate);
			let port = portZh(n.port);
			if ((port === '—' || port === 'Other') && Number(n.max_mbps) >= 10000)
				port = 'SFP+';
			if (n.port === 'Other' && Number(n.max_mbps) >= 10000)
				port = 'SFP+';
			return [
				dash(n.name),
				knownChip(n.pci_vendor, n.pci_device, n.chip),
				dash(n.pci_slot),
				dash(n.mac),
				port,
				link,
				n.max_mbps ? speedZh(n.max_mbps) : '—',
				dash(n.firmware)
			];
		})
	);
}

function slotRange(slots) {
	const s = (slots || []).slice().sort();
	if (!s.length)
		return '—';
	if (s.length === 1)
		return s[0];
	return s[0] + ' … ' + s[s.length - 1] + '（' + s.length + ' 个）';
}

function pciCard(pci) {
	const items = [];
	(pci || []).forEach(function(p) {
		if (p.line && !p.chip)
			items.push(parsePciLine(p.line));
		else
			items.push({
				slot: p.slot || '',
				class_name: p.class_name || '',
				class_id: p.class_id || (p.class || ''),
				chip: p.chip || '',
				vendor_id: p.vendor_id || p.vendor || '',
				device_id: p.device_id || p.device || ''
			});
	});
	const rows = items.filter(function(p) {
		return pciKind(p).group !== 9;
	});
	const buckets = [];
	const index = {};
	rows.forEach(function(p) {
		const kind = pciKind(p);
		const chip = knownChip(p.vendor_id, p.device_id, p.chip);
		const key = kind.group + '|' + kind.label + '|' + chip;
		if (index[key] == null) {
			index[key] = buckets.length;
			buckets.push({ group: kind.group, label: kind.label, chip: chip, slots: [] });
		}
		buckets[index[key]].slots.push(p.slot);
	});
	buckets.sort(function(a, b) {
		if (a.group !== b.group)
			return a.group - b.group;
		return a.label.localeCompare(b.label, 'zh');
	});
	if (!buckets.length)
		return E('p', { 'class': 'hw-empty' }, '未列出 PCI 设备');
	return grid(
		['类别', '芯片', '槽位'],
		buckets.map(function(b) {
			return [b.label, b.chip, slotRange(b.slots)];
		})
	);
}

function sensorCard(list) {
	const lines = [];
	(list || []).forEach(function(s) {
		const title = sensorNameZh(s.name || s.hwmon);
		const vals = s.values || {};
		Object.keys(vals).forEach(function(k) {
			if (!/_input$/.test(k) && k !== 'temp')
				return;
			let label = '读数';
			if (/^temp/.test(k) || k === 'temp')
				label = '温度';
			else if (/^fan/.test(k))
				label = '风扇';
			else if (/^in/.test(k))
				label = '电压';
			const t = milliC(vals[k]);
			let show = vals[k];
			if (label === '温度' && t)
				show = t;
			else if (label === '风扇' && Number(vals[k]) > 0)
				show = Number(vals[k]) + ' 转/分';
			else if (label === '电压' && Number(vals[k]) > 100)
				show = (Number(vals[k]) / 1000).toFixed(2) + ' V';
			lines.push([title, label, show]);
		});
	});
	if (!lines.length)
		return E('p', { 'class': 'hw-empty' }, '没有温度传感器读数');
	return grid(['来源', '项目', '数值'], lines);
}

return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	load() {
		return callHwinfo().catch(function() { return {}; });
	},

	render(data) {
		const box = E('div', { 'id': 'lede-hwinfo' });

		function fill(d) {
			d = d || {};
			box.innerHTML = '';
			box.appendChild(card('主板', machineCard(d.machine, d.pci)));
			if ((d.power || []).some(psuFilled))
				box.appendChild(card('电源', powerCard(d.power)));
			box.appendChild(card('CPU', cpuCard(d.cpu)));
			box.appendChild(card('内存', memCard(d.memory)));
			box.appendChild(card('磁盘', diskCard(d.disks)));
			box.appendChild(card('物理网卡', nicCard(d.network)));
			box.appendChild(card('板载与扩展设备', pciCard(d.pci)));
			box.appendChild(card('温度', sensorCard(d.sensors)));
		}

		fill(data);

		return E('div', {}, [
			E('style', {}, `
				.hw-card { margin:0 0 16px; padding:14px 16px; border-radius:8px;
					background: var(--background-color-high, #fff);
					border:1px solid var(--border-color-medium, #ddd); }
				.hw-card h3 { margin:0 0 10px; font-size:16px; }
				.hw-card h4 { margin:12px 0 6px; font-size:14px; }
				.hw-k { width:10em; opacity:.72; }
				.hw-meta, .hw-empty { opacity:.78; font-size:13px; }
			`),
			box
		]);
	}
});
