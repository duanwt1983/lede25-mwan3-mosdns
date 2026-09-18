'use strict';

import { readfile, writefile, lsdir, popen, stat } from 'fs';
import { cursor } from 'uci';
import { trim, now_fmt } from '/usr/share/ucode/lede-metrics.uc';
import { shutdown_mark_path, logread_cmd } from '/usr/share/ucode/lede-log.uc';

function join_sp(arr) {
	let s = '';
	for (let i = 0; i < length(arr); i++) {
		if (i > 0)
			s += '；';
		s += arr[i];
	}
	return s;
}

function cmd_out(cmd, maxb) {
	let p = popen(cmd, 'r');
	if (!p)
		return '';
	let t = replace(p.read('all') || '', /\r/g, '');
	p.close();
	maxb = +maxb;
	if (maxb > 0 && length(t) > maxb)
		t = substr(t, length(t) - maxb);
	return t;
}

function is_boot_noise(line) {
	if (match(line, /ACPI: LAPIC_NMI/))
		return true;
	if (match(line, /VF BAR .*failed to assign/))
		return true;
	if (match(line, /failed to assign/))
		return true;
	if (match(line, /rdinit=\/init failed/))
		return true;
	if (match(line, /ignoring$/))
		return true;
	if (match(line, /Known but unused|PCI: Using CONFIG|ENERGY_PERF_BIAS/))
		return true;
	return false;
}

function is_serious_kmsg(line) {
	if (is_boot_noise(line))
		return false;
	return match(line, /Kernel panic|Oops:|BUG: |general protection fault|Machine Check|mce:|Hardware Error|I\/O error|EXT4-fs error|XFS \(.*\): error|Remounting filesystem read-only|Out of memory|oom-kill|hung_task|Blocked for more than|Watchdog detected|soft lockup|hard LOCKUP|thermal trip|critical temperature|AER:.*Uncorrected|NVMe.*timeout|unrecovered read error|ata[0-9].*FAILED/i) ? true : false;
}

function strip_kstamp(line) {
	return trim(replace(line, /^\[[\s0-9.]+\]\s*/, ''));
}

export function format_kmsg(line) {
	let raw = trim(line);
	let body = strip_kstamp(raw);
	let m;

	m = match(body, /^traps:\s+(\S+)\[(\d+)\]\s+general protection fault/);
	if (m) {
		let name = m[1];
		let pid = m[2];
		let libm = match(body, / in ([A-Za-z0-9._+-]+\.so)/);
		if (!libm)
			libm = match(body, / in ([A-Za-z0-9._+-]+)/);
		let lib = libm ? libm[1] : '';
		let logish = match(name, /^(logread|logd|syslogd|klogd)$/) ? true : false;
		let libtxt = lib != '' ? sprintf('，出错位置在 %s', lib) : '';
		return {
			title: logish ? '读日志进程崩溃' : '用户进程崩溃',
			level: '中等',
			cat: '内核',
			detail: sprintf('程序 %s（进程号 %s）触发内存保护错误后退出%s。这是用户态崩溃，不是内核死机，也不等于内存条或硬盘坏了；转发和拨号一般不受影响。同一程序反复出现，多半是该程序自己的缺陷或并发读日志。', name, pid, libtxt),
			raw
		};
	}

	m = match(body, /(\S+)\[(\d+)\]:\s+segfault at/);
	if (!m)
		m = match(body, /^(\S+)\[(\d+)\]\s+segfault/);
	if (m)
		return {
			title: '用户进程崩溃',
			level: '中等',
			cat: '内核',
			detail: sprintf('程序 %s（进程号 %s）段错误退出。一般是该程序的问题，不是整机内核崩溃。', m[1], m[2]),
			raw
		};

	if (match(body, /Kernel panic/i))
		return { title: '内核崩溃', level: '严重', cat: '内核', detail: '内核自己停机了，设备会重启。原文：' + body, raw };
	if (match(body, /Oops:/))
		return { title: '内核 Oops', level: '严重', cat: '内核', detail: '内核执行出错。原文：' + body, raw };
	if (match(body, /BUG: /))
		return { title: '内核 BUG', level: '严重', cat: '内核', detail: body, raw };
	if (match(body, /soft lockup|hard LOCKUP|hung_task|Blocked for more than|Watchdog detected/i))
		return { title: '内核卡住', level: '严重', cat: '内核', detail: '某个任务长时间无响应。原文：' + body, raw };
	if (match(body, /Machine Check|mce:|Hardware Error|AER:.*Uncorrected/i))
		return { title: '硬件报错', level: '严重', cat: '硬件', detail: body, raw };
	if (match(body, /thermal trip|critical temperature/i))
		return { title: '温度保护', level: '严重', cat: '硬件', detail: body, raw };

	m = match(body, /Out of memory: Kill process (\d+) \(([^\)]+)\)/);
	if (m)
		return {
			title: '内存不够杀进程',
			level: '中等',
			cat: '内核',
			detail: sprintf('系统内存耗尽，内核杀掉了 %s（进程号 %s）。该查谁占内存。', m[2], m[1]),
			raw
		};
	if (match(body, /oom-kill|Out of memory/i))
		return { title: '内存不够', level: '中等', cat: '内核', detail: body, raw };

	if (match(body, /nf_conntrack: table full/i))
		return { title: '连接跟踪表满', level: '中等', cat: '内核', detail: '同时连接太多，可能影响转发。' + (length(body) > 80 ? '' : ' ' + body), raw };

	if (match(body, /I\/O error|EXT4-fs error|XFS \(.*\): error|unrecovered read error|Buffer I\/O error|Remounting filesystem read-only/i))
		return { title: '磁盘读写出错', level: '严重', cat: '硬件', detail: body, raw };
	if (match(body, /ata[0-9].*FAILED|NVMe.*timeout/i))
		return { title: '磁盘控制器异常', level: '严重', cat: '硬件', detail: body, raw };

	if (match(body, /F2FS-fs.*Magic Mismatch|Unknown parameter 'discard'/))
		return {
			title: '挂载探测提示',
			level: '一般',
			cat: '内核',
			detail: 'block 挂载时尝试识别文件系统产生的提示；/data 已是 ext4 时可忽略，不是磁盘损坏。',
			raw
		};
	if (match(body, /exFAT-fs|ntfs3\(|failed to recognize|Primary boot signature is not NTFS|try to read out of volume/))
		return { title: '磁盘分区无法识别', level: '一般', cat: '内核', detail: '这块分区不是当前内核识别的文件系统（或分区表对不上），不是整机崩溃。' + body, raw };
	if (m)
		return { title: 'USB 设备拔出', level: '一般', cat: '内核', detail: body, raw };
	if (match(body, /new (high-speed|SuperSpeed|full-speed) USB|USB device found/i))
		return { title: 'USB 设备接入', level: '一般', cat: '内核', detail: body, raw };

	m = match(body, /([A-Za-z0-9_]+): link (is )?(up|down)/i);
	if (m)
		return {
			title: m[3] == 'up' || m[3] == 'Up' ? '网线连通' : '网线断开',
			level: '一般',
			cat: '网络',
			detail: sprintf('网卡 %s 链路 %s。', m[1], (m[3] == 'up' || m[3] == 'Up') ? '恢复' : '断开'),
			raw
		};

	let short = body;
	if (length(short) > 180)
		short = substr(short, 0, 180) + '…';
	return { title: '内核', level: '一般', cat: '内核', detail: short, raw };
}

function hits_from(text, maxn) {
	let out = [];
	for (let line in split(text, '\n')) {
		line = trim(line);
		if (line == '')
			continue;
		if (!is_serious_kmsg(line))
			continue;
		let f = format_kmsg(line);
		let bit = f.title + '：' + f.detail;
		if (length(bit) > 240)
			bit = substr(bit, 0, 240) + '…';
		push(out, bit);
		if (length(out) >= maxn)
			break;
	}
	return out;
}

export function mem_cause() {
	let p = popen('top -bn1 2>/dev/null', 'r');
	if (!p)
		return '';
	let text = replace(p.read('all') || '', /\r/g, '');
	p.close();
	let procs = [];
	for (let line in split(text, '\n')) {
		let m = match(line, /([0-9.]+)%[ \t]+([0-9.]+)%[ \t]+(.*)/);
		if (!m)
			continue;
		let mem = +m[1];
		let name = trim(m[3]);
		name = replace(name, /^.*\//, '');
		name = split(name, /[ \t]/)[0] || name;
		if (name == '' || name == 'top')
			continue;
		push(procs, { mem, name });
	}
	let bits = [];
	for (let round = 0; round < 5; round++) {
		let best = -1, bi = -1;
		for (let i = 0; i < length(procs); i++) {
			if (procs[i] == null)
				continue;
			if (procs[i].mem > best) {
				best = procs[i].mem;
				bi = i;
			}
		}
		if (bi < 0 || best < 1)
			break;
		push(bits, sprintf('%s 约占内存%d%%', procs[bi].name, int(best + 0.5)));
		procs[bi] = null;
	}
	if (length(bits) == 0)
		return '未能从进程列表判断谁占内存';
	return '占用内存较多：' + join_sp(bits);
}

export function disk_cause(path) {
	path = path || '/overlay';
	let p = popen(sprintf("du -d1 -k '%s' 2>/dev/null | sort -n", replace(path, /'/g, '')), 'r');
	if (!p)
		return '';
	let text = p.read('all') || '';
	p.close();
	let rows = [];
	for (let line in split(text, '\n')) {
		let m = match(trim(line), /^([0-9]+)[ \t]+(.*)$/);
		if (!m)
			continue;
		push(rows, { kb: +m[1], p: m[2] });
	}
	let n = length(rows);
	if (n < 1)
		return '';
	let bits = [];
	let i = n - 1;
	let shown = 0;
	while (i >= 0 && shown < 4) {
		if (rows[i].p != path)
			push(bits, sprintf('%s %dMB', rows[i].p, int(rows[i].kb / 1024)));
		shown++;
		i--;
	}
	if (length(bits) == 0)
		return '';
	return '目录占用：' + join_sp(bits);
}

export function temp_cause() {
	let bits = [];
	let zones = lsdir('/sys/class/thermal') || [];
	for (let z in zones) {
		if (!match(z, /^thermal_zone/))
			continue;
		let t = +trim(readfile('/sys/class/thermal/' + z + '/temp') || '0');
		if (t > 200)
			t = int(t / 1000);
		if (t < 1)
			continue;
		let ty = trim(readfile('/sys/class/thermal/' + z + '/type') || z);
		push(bits, sprintf('%s %d℃', ty, t));
	}
	let hw = lsdir('/sys/class/hwmon') || [];
	for (let h in hw) {
		let dir = '/sys/class/hwmon/' + h;
		let name = trim(readfile(dir + '/name') || h);
		let files = lsdir(dir) || [];
		for (let f in files) {
			if (!match(f, /^temp[0-9]+_input$/))
				continue;
			let t = +trim(readfile(dir + '/' + f) || '0');
			if (t > 200)
				t = int(t / 1000);
			if (t >= 1)
				push(bits, sprintf('%s %d℃', name, t));
		}
	}
	if (length(bits) == 0)
		return '无可用温度传感器';
	return '传感器：' + join_sp(bits);
}

export function wan_cause(iface) {
	let bits = [];
	let ctx = cursor();
	try { ctx.load('network'); } catch (e) {}
	let dev = ctx.get('network', iface, 'device') || ctx.get('network', iface, 'ifname') || '';
	let proto = ctx.get('network', iface, 'proto') || '';
	if (proto != '')
		push(bits, '协议 ' + proto);
	if (dev == '' || dev == '@' + iface) {
		let p = popen(sprintf("ubus call network.interface.%s status 2>/dev/null", iface), 'r');
		let js = p ? (p.read('all') || '') : '';
		if (p)
			p.close();
		let m = match(js, /"l3_device":\s*"([^"]+)"/);
		if (m)
			dev = m[1];
		m = match(js, /"device":\s*"([^"]+)"/);
		if ((dev == '' || dev == null) && m)
			dev = m[1];
		if (match(js, /"up":\s*false/))
			push(bits, '逻辑接口 down（未连接/无地址）');
		else if (match(js, /"up":\s*true/))
			push(bits, '逻辑接口 up');
	}
	if (dev != '') {
		let car = trim(readfile('/sys/class/net/' + dev + '/carrier') || '');
		let op = trim(readfile('/sys/class/net/' + dev + '/operstate') || '');
		if (car == '0')
			push(bits, sprintf('物理网卡 %s 无载波（网线或对端光猫断）', dev));
		else if (car == '1' && (op == 'up' || op == 'unknown' || op == ''))
			push(bits, sprintf('物理网卡 %s 链路正常（%s），外网不通多为拨号/认证/对端故障', dev, op != '' ? op : 'up'));
		else if (car == '1')
			push(bits, sprintf('物理网卡 %s 载波在但 operstate=%s', dev, op));
		else if (op == 'down')
			push(bits, sprintf('物理网卡 %s 链路 down', dev));
	}
	let log = cmd_out(logread_cmd('-l 80'), 20000);
	let keys = [];
	if (iface != '')
		push(keys, iface);
	if (dev != '')
		push(keys, dev);
	push(keys, 'pppd');
	push(keys, 'pppoe');
	push(keys, 'mwan3');
	let found = [];
	for (let line in split(log, '\n')) {
		let hit = false;
		for (let k in keys)
			if (k != '' && index(line, k) >= 0)
				hit = true;
		if (!hit)
			continue;
		if (match(line, /Timeout|terminated|hangup|auth.*fail|CHAP|PAP|LCP|not connected|link is down|Unable|error|offline|lost tracking/i)) {
			line = trim(line);
			if (length(line) > 180)
				line = substr(line, 0, 180) + '…';
			push(found, line);
			if (length(found) >= 3)
				break;
		}
	}
	if (length(found) > 0)
		push(bits, '近期日志：' + join_sp(found));
	if (length(bits) == 0)
		return '未从网卡载波和近期日志里定位到更具体原因，请看系统/内核日志';
	return join_sp(bits);
}

const LOGREAD_CRASH_TS = '/tmp/lede-logread-crash-alert.ts';

export function kernel_new_faults() {
	let text = cmd_out('dmesg 2>/dev/null', 80000);
	let cur = sprintf('%d:%d', length(text), (length(text) > 80) ? ord(substr(text, length(text) - 20, 1)) : 0);
	let prev = trim(readfile('/tmp/lede-kmsg.cursor') || '');
	writefile('/tmp/lede-kmsg.cursor', cur + '\n');
	if (prev == cur)
		return null;
	let chunk = text;
	if (prev != '' && length(text) > 400)
		chunk = substr(text, length(text) > 12000 ? length(text) - 12000 : 0);
	let bits = [];
	let worst = '中等';
	let title = '';
	let titles = {};
	let ntitle = 0;
	for (let line in split(chunk, '\n')) {
		line = trim(line);
		if (line == '' || !is_serious_kmsg(line))
			continue;
		let f = format_kmsg(line);
		if (f.level == '严重')
			worst = '严重';
		if (titles[f.title] == null) {
			titles[f.title] = true;
			ntitle++;
			if (title == '')
				title = f.title;
		}
		let bit = f.title + '：' + f.detail;
		push(bits, bit);
		if (length(bits) >= 6)
			break;
	}
	if (length(bits) == 0)
		return null;
	if (title == '读日志进程崩溃' || match(title, /logread/i)) {
		let last = +(trim(readfile(LOGREAD_CRASH_TS) || '0'));
		if (last > 0 && time() - last < 3600)
			return null;
		writefile(LOGREAD_CRASH_TS, sprintf('%d\n', time()));
	}
	if (ntitle != 1)
		title = '内核异常';
	return {
		level: worst,
		title,
		detail: join_sp(bits)
	};
}

export function pstore_bits() {
	let dir = '/sys/fs/pstore';
	let names = lsdir(dir) || [];
	let bits = [];
	for (let n in names) {
		if (n == '.' || n == '..')
			continue;
		let body = trim(readfile(dir + '/' + n) || '');
		if (body == '')
			continue;
		if (length(body) > 400)
			body = substr(body, 0, 400) + '…';
		body = replace(body, /\n/g, ' / ');
		push(bits, n + '：' + body);
		if (length(bits) >= 2)
			break;
	}
	return join_sp(bits);
}

export function reboot_report() {
	let mark = readfile(shutdown_mark_path()) || '';
	let reason = '';
	let mark_time = '';
	for (let line in split(mark, '\n')) {
		let m = match(line, /^reason=(.*)$/);
		if (m)
			reason = trim(m[1]);
		m = match(line, /^time=(.*)$/);
		if (m)
			mark_time = trim(m[1]);
	}
	let kmsg = cmd_out('dmesg 2>/dev/null', 60000);
	let pstore = pstore_bits();
	let kfaults = hits_from(kmsg, 8);
	let kind = '';
	let title = '设备重启';
	let detail = '';
	let blob = join_sp(kfaults) + ' ' + pstore;
	let op = '';
	for (let line in split(mark, '\n')) {
		let m = match(line, /^operator=(.*)$/);
		if (m)
			op = trim(m[1]);
	}

	if (match(reason, /^user-/) || (mark != '' && reason != '')) {
		kind = 'user';
		title = match(reason, /^user-/) ? '用户主动重启' : '有序重启';
		detail = '判定：关机标记写于重启之前，属于有人点了重启、执行了 reboot，或关机脚本已跑完。记录：' + reason;
		if (op != '')
			detail += ' 操作端：' + op;
		if (mark_time != '')
			detail += ' 时间 ' + mark_time + '。';
		if (pstore != '' || length(kfaults) > 0)
			detail += ' 另：内核里还有历史故障线索，供对照，不作为本次主因。';
		if (pstore != '')
			detail += ' pstore：' + pstore;
		if (length(kfaults) > 0)
			detail += ' 内核：' + join_sp(kfaults);
	} else if (pstore != '' || match(blob, /Kernel panic|Oops:|BUG: |soft lockup|hard LOCKUP|hung_task|Watchdog detected/i)) {
		if (match(blob, /Machine Check|mce:|Hardware Error|I\/O error|thermal trip|AER:.*Uncorrected|unrecovered read error/i)) {
			kind = 'hardware';
			title = '硬件故障重启';
			detail = '判定：内核留下了硬件错误线索（内存/CPU 机器检查、磁盘I/O、过热或 PCIe 不可纠正错误），随后发生复位。x86 没有单独的复位原因寄存器，这是根据日志推断。';
		} else {
			kind = 'software';
			title = '软件故障重启';
			detail = '判定：内核崩溃、死锁或看门狗咬死，更像软件/驱动卡死。x86 上这是推断，不是芯片给出的复位码。';
		}
		if (pstore != '')
			detail += ' pstore：' + pstore;
		if (length(kfaults) > 0)
			detail += ' 内核线索：' + join_sp(kfaults);
	} else {
		kind = 'power';
		title = '疑似断电重启';
		detail = '判定：没有正常关机标记。x86 没有“复位原因寄存器”时，停电、拔电、按电源键硬复位都会是这一类。';
		if (length(kfaults) > 0)
			detail += ' 开机内核另有：' + join_sp(kfaults);
		else
			detail += ' 开机内核未见 panic/机器检查，更偏向供电中断。';
	}

	let up = split(trim(readfile('/proc/uptime') || '0'), '.')[0];
	detail += sprintf(' 本次已运行 %s 秒。检查时间 %s。', up, now_fmt());
	return { kind, title, detail, level: (kind == 'user') ? '一般' : '严重' };
}

export function dhcp_cause(pool) {
	return sprintf('池 %s 已用 %d/%d。根因是租约占满：加大 start/limit，或清掉不用的租约（状态 → DHCP）。',
		pool.name, pool.used, pool.limit);
}
