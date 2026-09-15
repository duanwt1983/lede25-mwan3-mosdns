'use strict';

import { readfile, writefile, lsdir, popen, stat } from 'fs';

export function trim(s) {
	if (s == null)
		s = '';
	return replace(`${s}`, /^\s+|\s+$/g, '');
}

export function as_bool(v, def) {
	if (v == null || v == '')
		return def;
	return (v == '1' || v == 1 || v == true || v == 'true' || v == 'on');
}

export function as_list(v) {
	let out = [];
	if (type(v) == 'array') {
		for (let x in v)
			if (x != null && `${x}` != '')
				push(out, trim(x));
	} else if (v != null && `${v}` != '') {
		for (let x in split(`${v}`, /[ \t]+/))
			if (x != '')
				push(out, x);
	}
	return out;
}

export function ip2n(s) {
	let p = split(`${s}`, '.');
	if (length(p) != 4)
		return 0;
	return (+p[0] * 16777216) + (+p[1] * 65536) + (+p[2] * 256) + (+p[3]);
}

export function now_fmt() {
	let p = popen("date '+%Y-%m-%d %H:%M:%S'", 'r');
	if (p) {
		let s = trim(p.read('all'));
		p.close();
		if (s != '')
			return s;
	}
	try {
		let t = localtime(time());
		if (t) {
			let mon = +t.mon;
			if (mon == 0)
				mon = 1;
			return sprintf('%04d-%02d-%02d %02d:%02d:%02d', t.year, mon, t.mday, t.hour, t.min, t.sec);
		}
	} catch (e) {}
	return '';
}

function millic_to_c(raw) {
	let t = +replace(`${raw == null ? '' : raw}`, /[^0-9-]/g, '');
	if (t != t)
		return 0;
	if (t > 200)
		t = int(t / 1000);
	if (t >= 1 && t <= 120)
		return t;
	return 0;
}

// Same sources as the LuCI overview: hwmon first, then thermal zones.
export function max_temp_c() {
	let max = 0;
	let hw = lsdir('/sys/class/hwmon') || [];
	for (let h in hw) {
		let dir = '/sys/class/hwmon/' + h;
		let files = lsdir(dir) || [];
		for (let f in files) {
			if (!match(f, /^temp[0-9]+_input$/))
				continue;
			let t = millic_to_c(readfile(dir + '/' + f));
			if (t > max)
				max = t;
		}
	}
	let zones = lsdir('/sys/class/thermal') || [];
	for (let z in zones) {
		if (!match(z, /^thermal_zone/))
			continue;
		let t = millic_to_c(readfile('/sys/class/thermal/' + z + '/temp'));
		if (t > max)
			max = t;
	}
	return max;
}

export function cpu_pct() {
	let prev = split(trim(readfile('/tmp/wanmon.cpu') || ''), /[ \t]+/);
	let line = '';
	for (let l in split(readfile('/proc/stat') || '', '\n')) {
		if (match(l, /^cpu /)) {
			line = l;
			break;
		}
	}
	let f = split(trim(line), /[ \t]+/);
	// /proc/stat: user nice system idle iowait irq softirq steal guest guest_nice
	// guest/guest_nice are already included in user/nice — do not add them.
	let user = (length(f) > 1) ? +f[1] : 0;
	let nice = (length(f) > 2) ? +f[2] : 0;
	let system = (length(f) > 3) ? +f[3] : 0;
	let idle = (length(f) > 4) ? +f[4] : 0;
	let iowait = (length(f) > 5) ? +f[5] : 0;
	let irq = (length(f) > 6) ? +f[6] : 0;
	let softirq = (length(f) > 7) ? +f[7] : 0;
	let steal = (length(f) > 8) ? +f[8] : 0;
	let idle2 = idle + iowait;
	let tot2 = user + nice + system + idle + iowait + irq + softirq + steal;
	writefile('/tmp/wanmon.cpu', sprintf('%d %d\n', tot2, idle2));
	let tot1 = +prev[0];
	let idle1 = +prev[1];
	let dt = tot2 - tot1;
	let di = idle2 - idle1;
	if (!(tot1 > 0) || dt <= 0)
		return 0;
	if (di < 0)
		di = 0;
	if (di > dt)
		di = dt;
	// ucode integer/integer is truncating; force float or idle/total becomes 0 → 100%.
	let p = int((1 - di / (dt + 0.0)) * 100 + 0.5);
	if (p < 0)
		p = 0;
	if (p > 100)
		p = 100;
	return p;
}

export function mem_percent() {
	let total = 0, avail = 0;
	for (let l in split(readfile('/proc/meminfo') || '', '\n')) {
		let m = match(l, /^MemTotal:\s+([0-9]+)/);
		if (m)
			total = +m[1];
		m = match(l, /^MemAvailable:\s+([0-9]+)/);
		if (m)
			avail = +m[1];
	}
	if (total <= 0)
		return 0;
	return int(((total - avail) * 100 / total) + 0.5);
}

export function load1() {
	return split(trim(readfile('/proc/loadavg') || '0'), /[ \t]+/)[0];
}

export function load15() {
	let p = split(trim(readfile('/proc/loadavg') || '0'), /[ \t]+/);
	return length(p) >= 3 ? p[2] : '0';
}

export function ncpu() {
	let n = 0;
	for (let l in split(readfile('/proc/cpuinfo') || '', '\n'))
		if (match(l, /^processor/))
			n++;
	if (n < 1)
		n = 1;
	return n;
}

function cmd_base(cmd) {
	cmd = trim(cmd);
	cmd = replace(cmd, /^\[/, '');
	cmd = replace(cmd, /\]$/, '');
	let bin = split(cmd, /[ \t]/)[0] || cmd;
	return replace(bin, /^.*\//, '');
}

function cmd_role(name) {
	if (match(name, /mosdns|dnsmasq|chinadns|unbound|named|coredns/))
		return 'DNS';
	if (match(name, /sing-box|xray|v2ray|passwall|ss-redir|sslocal|hysteria|tuic|naive/))
		return '代理';
	if (match(name, /nginx|uhttpd|rpcd/))
		return '网页';
	if (match(name, /ksoftirq|softirq/))
		return '网络软中断';
	if (match(name, /pppd|mwan|udhcpc|pppoe/))
		return '拨号';
	if (match(name, /smbd|nmbd|nfsd|aria2|minidlna/))
		return '文件共享';
	if (match(name, /kworker|kswapd|jbd2|kcompact/))
		return '内核';
	if (match(name, /haproxy/))
		return '反向代理';
	if (match(name, /irqbalance/))
		return '硬件中断';
	return '';
}

function parse_top_procs(text) {
	let procs = [];
	for (let line in split(text, '\n')) {
		line = replace(line, /\r$/, '');
		if (line == '' || match(line, /^(Mem:|CPU:|Load | *PID )/))
			continue;
		/* busybox top -bn1 */
		let m = match(line, /^\s*\d+\s+\d+\s+\S+\s+\S+\s+\d+\s+\d+\.?\d*%\s+(\d+\.?\d*)%\s+(.+)$/);
		if (m) {
			let pct = +m[1];
			let name = cmd_base(m[2]);
			if (name != '' && name != 'top')
				push(procs, { pct, name, role: cmd_role(name) });
			continue;
		}
		/* procps / full top (%CPU often near end) */
		let nums = [];
		let rest = line;
		while (true) {
			let nm = match(rest, /(\d+\.?\d*)%/);
			if (!nm)
				break;
			push(nums, +nm[1]);
			rest = substr(rest, index(rest, nm[0]) + length(nm[0]));
		}
		if (length(nums) >= 1) {
			let pct = nums[length(nums) - 1];
			m = match(line, /(\d+\.?\d*)%\s+(.+)$/);
			if (m) {
				let name = cmd_base(m[2]);
				if (name != '' && name != 'top' && name != 'sirq' && name != 'irq')
					push(procs, { pct, name, role: cmd_role(name) });
			}
		}
	}
	return procs;
}

/* Snapshot of CPU breakdown + processes currently using CPU (busybox top -bn1). */
export function resource_cause() {
	let p = popen('top -bn1 2>/dev/null', 'r');
	if (!p)
		return '';
	let text = replace(p.read('all') || '', /\r/g, '');
	p.close();
	let usr = '', sys = '', io = '', irq = '', sirq = '';
	let procs = parse_top_procs(text);
	for (let line in split(text, '\n')) {
		let m = match(line, /CPU:\s+(\d+)% usr\s+(\d+)% sys\s+(\d+)% nic\s+(\d+)% idle\s+(\d+)% io\s+(\d+)% irq\s+(\d+)% sirq/);
		if (m) {
			usr = m[1];
			sys = m[2];
			io = m[5];
			irq = m[6];
			sirq = m[7];
			break;
		}
	}
	let bits = [];
	let nshow = 0;
	for (let round = 0; round < 6; round++) {
		let best = -1, bi = -1;
		for (let i = 0; i < length(procs); i++) {
			if (procs[i] == null)
				continue;
			if (procs[i].pct > best) {
				best = procs[i].pct;
				bi = i;
			}
		}
		if (bi < 0 || best < 1)
			break;
		let it = procs[bi];
		procs[bi] = null;
		let s = sprintf('%s %d%%', it.name, int(it.pct + 0.5));
		if (it.role != '')
			s += '(' + it.role + ')';
		if (nshow == 0)
			push(bits, '构成：' + s);
		else
			bits[0] += '、' + s;
		nshow++;
	}
	if (nshow == 0) {
		if (usr != '')
			push(bits, sprintf('构成：用户%s%% 内核%s%% 软中断%s%% 硬中断%s%% IO等待%s%%', usr, sys, sirq, irq, io));
		else
			push(bits, '构成：top 未抓到当前高 CPU 进程，可能是刚过去的尖峰或进程在等 IO');
	}
	let out = '';
	for (let i = 0; i < length(bits); i++) {
		if (i > 0)
			out += '。';
		out += bits[i];
	}
	return out;
}

export function disk_of(path) {
	if (path == null || path == '')
		return null;
	let p = popen(sprintf("df -P '%s' 2>/dev/null", replace(`${path}`, /'/g, '')), 'r');
	if (!p)
		return null;
	let text = p.read('all') || '';
	p.close();
	let lines = split(trim(text), '\n');
	if (length(lines) < 2)
		return null;
	let f = split(trim(lines[1]), /[ \t]+/);
	if (length(f) < 6)
		return null;
	return {
		src: f[0],
		total_kb: +f[1],
		used_kb: +f[2],
		pct: +replace(f[4], '%', ''),
		mount: f[5]
	};
}

export function disks_overview() {
	let p = popen('df -P 2>/dev/null', 'r');
	if (!p)
		return [];
	let text = p.read('all') || '';
	p.close();
	let rows = [];
	let i = 0;
	for (let line in split(text, '\n')) {
		i++;
		if (i < 2)
			continue;
		let f = split(trim(line), /[ \t]+/);
		if (length(f) < 6)
			continue;
		let src = f[0], tot = +f[1], used = +f[2], pct = +replace(f[4], '%', ''), mp = f[5];
		if (match(src, /^(tmpfs|devtmpfs|udev)/))
			continue;
		if (mp == '/tmp' || mp == '/dev' || match(mp, /^\/sys/) || match(mp, /^\/proc/))
			continue;
		if (match(src, /^\/dev\//) || mp == '/' || mp == '/overlay' || match(mp, /^\/mnt\//))
			push(rows, { mount: mp, total_kb: tot, used_kb: used, pct });
	}
	return rows;
}

export function dhcp_pools(ctx) {
	let leases = [];
	let raw = readfile('/tmp/dhcp.leases') || '';
	for (let line in split(raw, '\n')) {
		let f = split(trim(line), /[ \t]+/);
		if (length(f) >= 3)
			push(leases, ip2n(f[2]));
	}
	let out = [];
	ctx.foreach('dhcp', 'dhcp', (s) => {
		if (as_bool(s.ignore, false))
			return;
		let start = +s.start;
		let limit = +s.limit;
		if (!(limit > 0))
			return;
		let iface = s.interface || s['.name'];
		let ip = ctx.get('network', iface, 'ipaddr');
		if (ip == null || ip == '')
			return;
		let mask = ctx.get('network', iface, 'netmask') || '255.255.255.0';
		let net = ip2n(ip) & ip2n(mask);
		let first = net + start;
		let last = first + limit - 1;
		let used = 0;
		for (let v in leases)
			if (v >= first && v <= last)
				used++;
		let remain = limit - used;
		if (remain < 0)
			remain = 0;
		push(out, { name: s['.name'], iface, used, limit, remain });
	});
	return out;
}

export function bytes_of(dev) {
	if (dev == null || dev == '')
		return { rx: 0, tx: 0 };
	return {
		rx: +(trim(readfile(`/sys/class/net/${dev}/statistics/rx_bytes`) || '0')),
		tx: +(trim(readfile(`/sys/class/net/${dev}/statistics/tx_bytes`) || '0'))
	};
}

const IFACE_RATE_CACHE = '/tmp/lede-iface-rate-cache.json';

function read_json_file(path) {
	try {
		let h = json(readfile(path) || '{}') || {};
		if (type(h) == 'object')
			return h;
	} catch (e) {}
	return {};
}

/* /sys/class/net byte delta when Bandix returns 0 or is briefly unavailable. */
export function iface_rate_bps(dev) {
	let z = { down_bps: 0, up_bps: 0 };
	if (!dev || match(dev, /[^A-Za-z0-9._-]/))
		return z;
	let now = time();
	let cur = bytes_of(dev);
	let cache = read_json_file(IFACE_RATE_CACHE);
	let prev = cache[dev];
	cache[dev] = { rx: cur.rx, tx: cur.tx, t: now };
	try { writefile(IFACE_RATE_CACHE, sprintf('%J', cache)); } catch (e) {}
	if (!prev || type(prev) != 'object')
		return z;
	let dt = now - +(prev.t || 0);
	if (dt < 0.35 || dt > 45)
		return z;
	let drx = cur.rx - +(prev.rx || 0);
	let dtx = cur.tx - +(prev.tx || 0);
	if (drx < 0)
		drx = 0;
	if (dtx < 0)
		dtx = 0;
	return {
		down_bps: int((drx * 8) / dt),
		up_bps: int((dtx * 8) / dt)
	};
}

export function pick_iface_rates(primary, fallback) {
	let down = +(primary.down_bps || 0);
	let up = +(primary.up_bps || 0);
	if (down <= 0)
		down = +(fallback.down_bps || 0);
	if (up <= 0)
		up = +(fallback.up_bps || 0);
	return { down_bps: down, up_bps: up };
}

export function file_size(path) {
	let st = stat(path);
	if (!st)
		return 0;
	return +st.size;
}

export function data_mounted() {
	return match(readfile('/proc/mounts') || '', / \/data /) != null;
}

export function rate_hist_mem_path() {
	return '/tmp/lede-rate-hist.json';
}

export function rate_hist_disk_path() {
	if (data_mounted())
		return '/data/metrics/lede-rate-hist.json';
	return '/overlay/metrics/lede-rate-hist.json';
}

function read_json_obj(path) {
	try {
		let h = json(readfile(path) || '{}') || {};
		if (type(h) == 'object')
			return h;
	} catch (e) {}
	return {};
}

function hist_has_points(h) {
	return type(h) == 'object' && type(h.t) == 'array' && length(h.t) > 0;
}

export function atomic_write_json(path, obj) {
	if (!path)
		return;
	let dir = replace(path, /\/[^\/]+$/, '');
	if (dir != '' && dir != path)
		system(sprintf("mkdir -p '%s'", dir));
	let tmp = path + '.new';
	writefile(tmp, sprintf('%J', obj));
	system(sprintf("mv -f '%s' '%s'", tmp, path));
}

export function load_rate_hist() {
	let mem = rate_hist_mem_path();
	let h = read_json_obj(mem);
	if (hist_has_points(h))
		return h;
	h = read_json_obj(rate_hist_disk_path());
	if (hist_has_points(h))
		atomic_write_json(mem, h);
	if (type(h) != 'object')
		h = {};
	return h;
}

export function rate_hist_win_path(win) {
	return '/tmp/lede-rate-win-' + win + '.json';
}

export function slice_rate_hist(h, win, max_pts) {
	win = +win;
	if (win < 300)
		win = 300;
	if (win > 86400)
		win = 86400;
	if (!max_pts || max_pts < 60)
		max_pts = 720;
	if (type(h) != 'object')
		h = {};
	let t = type(h.t) == 'array' ? h.t : [];
	let series = type(h.series) == 'object' ? h.series : {};
	let n = length(t);
	let out_t = [];
	let out_s = {};
	if (n > 0) {
		let cut = t[n - 1] - win;
		let start = 0;
		for (let i = 0; i < n; i++) {
			if (t[i] >= cut) {
				start = i;
				break;
			}
		}
		let count = n - start;
		let step = 1;
		if (count > max_pts)
			step = int((count + max_pts - 1) / max_pts);
		if (step < 1)
			step = 1;
		for (let name in series)
			out_s[name] = { rx: [], tx: [], lat: [] };
		let i = start;
		while (i < n) {
			let j = i + step;
			if (j > n)
				j = n;
			let use = j - 1;
			push(out_t, t[use]);
			for (let name in series) {
				let s = series[name];
				let rx = 0, tx = 0, lat = 0;
				if (type(s) == 'object') {
					let ra = type(s.rx) == 'array' ? s.rx : [];
					let ta = type(s.tx) == 'array' ? s.tx : [];
					let la = type(s.lat) == 'array' ? s.lat : [];
					let k = i;
					while (k < j) {
						let rv = k < length(ra) ? +ra[k] : 0;
						let tv = k < length(ta) ? +ta[k] : 0;
						let lv = k < length(la) ? +la[k] : 0;
						if (rv > rx)
							rx = rv;
						if (tv > tx)
							tx = tv;
						if (lv > lat)
							lat = lv;
						k++;
					}
				}
				if (type(out_s[name]) != 'object')
					out_s[name] = { rx: [], tx: [], lat: [] };
				push(out_s[name].rx, rx);
				push(out_s[name].tx, tx);
				push(out_s[name].lat, lat);
			}
			i = j;
		}
	}
	return {
		interval: +(h.interval || 10),
		window: win,
		stored: n,
		last: n ? +t[n - 1] : 0,
		t: out_t,
		series: out_s
	};
}

function series_tip_of(h) {
	let tip = {};
	let series = type(h.series) == 'object' ? h.series : {};
	for (let name in series) {
		let s = series[name];
		if (type(s) != 'object')
			continue;
		let rx = type(s.rx) == 'array' ? s.rx : [];
		let tx = type(s.tx) == 'array' ? s.tx : [];
		tip[name] = {
			rx: length(rx) ? +(rx[length(rx) - 1] || 0) : 0,
			tx: length(tx) ? +(tx[length(tx) - 1] || 0) : 0,
			lat: (type(s.lat) == 'array' && length(s.lat)) ? +(s.lat[length(s.lat) - 1] || 0) : 0
		};
	}
	return tip;
}

function refresh_win_caches(h) {
	let last = 0;
	if (type(h.t) == 'array' && length(h.t) > 0)
		last = +h.t[length(h.t) - 1];
	try {
		writefile('/tmp/lede-rate-head.json', sprintf('%J', {
			last,
			n: type(h.t) == 'array' ? length(h.t) : 0,
			interval: +(h.interval || 10),
			tip: series_tip_of(h)
		}));
	} catch (e) {}
	let wins = [ 300, 900, 1800 ];
	for (let win in wins) {
		try {
			atomic_write_json(rate_hist_win_path(win), slice_rate_hist(h, win, 720));
		} catch (e) {}
	}
}

export function load_rate_win(win) {
	win = +win;
	if (win < 300)
		win = 300;
	if (win > 86400)
		win = 86400;
	let head = read_json_obj('/tmp/lede-rate-head.json');
	let c = read_json_obj(rate_hist_win_path(win));
	if (type(c) == 'object' && c.window == win && type(c.t) == 'array' && length(c.t) > 0 &&
	    (head.last == null || c.last == head.last))
		return c;
	let h = load_rate_hist();
	c = slice_rate_hist(h, win, 720);
	try { atomic_write_json(rate_hist_win_path(win), c); } catch (e) {}
	return c;
}

export function rate_hist_meta() {
	let head = read_json_obj('/tmp/lede-rate-head.json');
	if (head.last != null && `${head.last}` != '') {
		return {
			interval: +(head.interval || 10),
			n: +(head.n || 0),
			last: +head.last,
			series_tip: type(head.tip) == 'object' ? head.tip : {}
		};
	}
	let h = load_rate_hist();
	let t = type(h.t) == 'array' ? h.t : [];
	let n = length(t);
	return {
		interval: +(h.interval || 10),
		n: n,
		last: n ? +t[n - 1] : 0,
		series_tip: series_tip_of(h)
	};
}

export function save_rate_windows(h) {
	try { refresh_win_caches(h); } catch (e) {}
}

export function save_rate_hist(h, now) {
	if (type(h) != 'object')
		return;
	now = +now;
	let every = data_mounted() ? 60 : 120;
	let due = now <= 0 || now - +(h.disk_t || 0) >= every;
	if (due)
		h.disk_t = now;
	atomic_write_json(rate_hist_mem_path(), h);
	if (due)
		atomic_write_json(rate_hist_disk_path(), h);
}
