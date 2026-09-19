'use strict';

import { open, readfile, writefile, stat, lsdir, popen } from 'fs';
import { cursor } from 'uci';
import { now_fmt, file_size, disk_of } from '/usr/share/ucode/lede-metrics.uc';

const LOGREAD_LOCK = '/tmp/lede-logread.lock';

function trim(s) {
	return replace(`${s}`, /^\s+|\s+$/g, '');
}

export function logread_cmd(args) {
	args = trim(args || '-l 400');
	if (system('command -v flock >/dev/null') == 0)
		return sprintf("flock -s -w 5 '%s' logread %s 2>/dev/null", LOGREAD_LOCK, args);
	return sprintf('logread %s 2>/dev/null', args);
}

function join(sep, arr) {
	let s = '';
	for (let i = 0; i < length(arr); i++) {
		if (i > 0)
			s += sep;
		s += arr[i];
	}
	return s;
}

function slice(arr, from) {
	let out = [];
	for (let i = from; i < length(arr); i++)
		push(out, arr[i]);
	return out;
}

export function ensure_dir(path) {
	let dir = replace(`${path}`, /\/[^\/]+$/, '');
	if (dir == '' || dir == path)
		dir = '/';
	system(sprintf("mkdir -p '%s' 2>/dev/null", dir));
	return dir;
}

export function looks_like_dir(path) {
	path = `${path || ''}`;
	if (path == '' || match(path, /\/$/))
		return true;
	let base = replace(replace(path, /\/+$/, ''), /.*\//, '');
	if (base == '' || base == '.' || base == '..')
		return true;
	if (!match(base, /\./))
		return true;
	let st = stat(path);
	if (st && st.type == 'directory')
		return true;
	return false;
}

export function normalize_log_path(path, default_name) {
	path = replace(`${path || ''}`, /^\s+|\s+$/g, '');
	if (path == '' || !match(path, /^\//))
		return '';
	default_name = default_name || 'app.log';
	if (looks_like_dir(path)) {
		path = replace(path, /\/+$/, '');
		if (path == '')
			path = '/';
		path = path + '/' + default_name;
	}
	return path;
}

export function ensure_log_file(path, default_name) {
	path = normalize_log_path(path, default_name);
	if (path == '')
		return '';
	ensure_dir(path);
	return path;
}

function log_stamp() {
	let p = popen("date '+%Y%m%d-%H%M%S'", 'r');
	let s = p ? replace(p.read('all') || '', /\s/g, '') : '';
	if (p)
		p.close();
	return s != '' ? s : sprintf('%d', time());
}

export function parent_dir(path) {
	let dir = replace(`${path}`, /\/[^\/]+$/, '');
	if (dir == '' || dir == path)
		return '/';
	return dir;
}

export function basename_of(path) {
	return replace(`${path}`, /.*\//, '');
}

function log_uci() {
	let ctx = cursor();
	try { ctx.load('lede-log'); } catch (e) {}
	try { ctx.load('wanalert'); } catch (e) {}
	try { ctx.load('mosdns'); } catch (e) {}
	try { ctx.load('system'); } catch (e) {}
	return ctx;
}

function data_mounted() {
	let m = readfile('/proc/mounts') || '';
	return match(m, / \/data /) != null;
}

function rewrite_if_no_data(path) {
	path = `${path || ''}`;
	if (index(path, '/data/') != 0 && path != '/data')
		return path;
	if (data_mounted())
		return path;
	return replace(path, /^\/data/, '/overlay');
}

export function configured_path(kind) {
	let ctx = log_uci();
	let p = '';
	if (kind == 'alert') {
		p = ctx.get('lede-log', 'alert', 'path') || '';
		if (p == '')
			p = ctx.get('wanalert', 'main', 'log_path') || '';
		return rewrite_if_no_data(normalize_log_path(p, 'sys-alert.log'));
	}
	if (kind == 'syslog') {
		p = ctx.get('lede-log', 'syslog', 'path') || '';
		if (p == '') {
			ctx.foreach('system', 'system', (s) => {
				if (p == '' && s.log_file)
					p = s.log_file;
			});
		}
		return rewrite_if_no_data(normalize_log_path(p, 'system.log'));
	}
	if (kind == 'kernel')
		return rewrite_if_no_data(normalize_log_path(ctx.get('lede-log', 'kernel', 'path') || '', 'kernel.log'));
	if (kind == 'mosdns') {
		p = ctx.get('lede-log', 'mosdns', 'path') || '';
		if (p == '')
			p = ctx.get('mosdns', 'config', 'log_file') || '';
		return rewrite_if_no_data(normalize_log_path(p, 'mosdns.log'));
	}
	return '';
}

export function configured_dir(kind) {
	let p = configured_path(kind);
	if (p == '') {
		p = configured_path('alert');
		if (p == '')
			p = configured_path('syslog');
	}
	if (p == '')
		return '';
	return parent_dir(p);
}

export function sidecar_path(kind, name) {
	let dir = configured_dir(kind);
	if (dir == '' || name == '')
		return '';
	return dir + '/' + name;
}

export function shutdown_mark_path() {
	return sidecar_path('alert', '.shutdown-mark');
}

export function capture_local_events() {
	let prev;
	let cur;
	let leases = readfile('/tmp/dhcp.leases') || '';
	prev = readfile('/tmp/lede-dhcp.snap');
	if (prev == null) {
		for (let line in split(leases, '\n')) {
			let p = split(trim(line), ' ');
			if (length(p) < 3)
				continue;
			let hn = (length(p) >= 4 && p[3] != '*') ? ('（' + p[3] + '）') : '';
			system(sprintf("logger -t lede-dhcp '在租 %s → %s%s'", p[1], p[2], hn));
		}
		writefile('/tmp/lede-dhcp.snap', leases);
	} else if (leases != prev) {
		let oldmap = {};
		for (let line in split(prev, '\n')) {
			let p = split(trim(line), ' ');
			if (length(p) >= 3)
				oldmap[p[2] + ' ' + p[1]] = true;
		}
		for (let line in split(leases, '\n')) {
			let p = split(trim(line), ' ');
			if (length(p) < 3)
				continue;
			let key = p[2] + ' ' + p[1];
			if (oldmap[key])
				continue;
			let hn = (length(p) >= 4 && p[3] != '*') ? ('（' + p[3] + '）') : '';
			system(sprintf("logger -t lede-dhcp '分配了地址 %s → %s%s'", p[1], p[2], hn));
		}
		writefile('/tmp/lede-dhcp.snap', leases);
	}

	let raw = '';
	let pb = popen('ubus call session list 2>/dev/null', 'r');
	if (pb) {
		raw = pb.read('all') || '';
		pb.close();
	}
	let ids = [];
	let names = {};
	if (raw != '') {
		let obj = null;
		try { obj = json(raw); } catch (e) { obj = null; }
		if (type(obj) == 'object') {
			if (type(obj.ubus_rpc_session) == 'string') {
				let sid = obj.ubus_rpc_session;
				if (sid != '' && sid != '00000000000000000000000000000000') {
					push(ids, sid);
					names[sid] = (type(obj.data) == 'object' && obj.data.username) ? obj.data.username : '';
				}
			} else {
				for (let sid in obj) {
					if (sid == '00000000000000000000000000000000')
						continue;
					let s = obj[sid];
					if (type(s) != 'object')
						continue;
					push(ids, sid);
					let user = '';
					if (type(s.data) == 'object' && s.data.username)
						user = s.data.username;
					names[sid] = user;
				}
			}
		}
	}
	cur = join('\n', ids);
	prev = readfile('/tmp/lede-sess.snap');
	if (prev == null)
		writefile('/tmp/lede-sess.snap', cur);
	else if (cur != prev) {
		let old = {};
		for (let line in split(prev, '\n')) {
			line = trim(line);
			if (line != '')
				old[line] = true;
		}
		for (let sid in ids) {
			if (old[sid])
				continue;
			let user = names[sid] || '';
			let who = user != '' ? ('用户 ' + user) : '已建立管理会话';
			system(sprintf("logger -t lede-login 'LuCI 登录 %s'", who));
		}
		writefile('/tmp/lede-sess.snap', cur);
	}
}

export function archive_if_needed(path, chunk_kb, keep_open) {
	chunk_kb = +chunk_kb;
	if (!(chunk_kb > 0))
		chunk_kb = 2048;
	if (chunk_kb < 64)
		chunk_kb = 64;
	if (file_size(path) <= chunk_kb * 1024)
		return false;
	let dest = path + '.' + log_stamp();
	if (keep_open)
		system(sprintf("cp -f '%s' '%s' 2>/dev/null; : > '%s'", path, dest, path));
	else
		system(sprintf("mv -f '%s' '%s' 2>/dev/null", path, dest));
	return true;
}

/* Back-compat name: now archives a timestamped file instead of a single .old. */
export function rotate_if_needed(path, max_kb) {
	return archive_if_needed(path, max_kb, true);
}

export function list_archives(path) {
	path = `${path || ''}`;
	let dir = parent_dir(path);
	let base = basename_of(path);
	let names = [];
	try {
		names = lsdir(dir) || [];
	} catch (e) {
		names = [];
	}
	let files = [];
	for (let n in names) {
		if (n == '.' || n == '..')
			continue;
		if (n != base && index(n, base + '.') != 0)
			continue;
		let full = dir + '/' + n;
		let st = stat(full);
		if (!st)
			continue;
		push(files, { path: full, name: n, live: n == base, mtime: +st.mtime, size: +st.size });
	}
	/* oldest first */
	for (let i = 0; i < length(files); i++) {
		for (let j = i + 1; j < length(files); j++) {
			if ((files[j].mtime < files[i].mtime) ||
			    (files[j].mtime == files[i].mtime && files[j].name < files[i].name)) {
				let t = files[i];
				files[i] = files[j];
				files[j] = t;
			}
		}
	}
	return files;
}

export function prune_old_logs(path, pct_limit) {
	pct_limit = +pct_limit;
	if (!(pct_limit > 50))
		pct_limit = 90;
	path = ensure_log_file(path, 'app.log');
	if (path == '')
		return 0;
	let n = 0;
	for (let round = 0; round < 40; round++) {
		let d = disk_of(path);
		if (!d || !(d.pct >= pct_limit))
			break;
		let files = list_archives(path);
		let victim = null;
		for (let f in files) {
			if (f.live)
				continue;
			victim = f;
			break;
		}
		if (victim == null)
			break;
		system(sprintf("rm -f '%s' 2>/dev/null", victim.path));
		n++;
	}
	return n;
}

function persist_new_lines(cmd, dest, cursor_path) {
	dest = ensure_log_file(dest, 'app.log');
	if (dest == '')
		return;
	let p = popen(cmd, 'r');
	if (!p)
		return;
	let text = replace(p.read('all') || '', /\r/g, '');
	p.close();
	if (text == '')
		return;
	let lines = split(text, '\n');
	let last = trim(readfile(cursor_path) || '');
	let started = (last == '');
	let fh = open(dest, 'a');
	if (!fh)
		return;
	let wrote = 0;
	let newest = last;
	for (let line in lines) {
		let s = replace(line, /\n$/, '');
		if (!started) {
			if (s == last)
				started = true;
			continue;
		}
		if (s == '')
			continue;
		if (match(s, /\]:[ \t]+USER \S+ pid [0-9]+ cmd /))
			continue;
		fh.write(s + '\n');
		newest = s;
		wrote++;
	}
	if (!started) {
		fh.write(sprintf('---- %s buffer-reset ----\n', now_fmt()));
		for (let line in lines) {
			let s = replace(line, /\n$/, '');
			if (s == '')
				continue;
			if (match(s, /\]:[ \t]+USER \S+ pid [0-9]+ cmd /))
				continue;
			fh.write(s + '\n');
			newest = s;
			wrote++;
		}
	}
	fh.close();
	if (newest != '')
		writefile(cursor_path, newest);
	return wrote;
}

export function persist_system_logs() {
	try { capture_local_events(); } catch (e) {}
	let ctx = log_uci();
	let chunk_sys = ctx.get('lede-log', 'syslog', 'max_kb') || 2048;
	let chunk_k = ctx.get('lede-log', 'kernel', 'max_kb') || 2048;
	let pct = ctx.get('wanalert', 'main', 'disk_percent') || 90;
	if (ctx.get('lede-log', 'syslog', 'enabled') != '0') {
		let sp = configured_path('syslog');
		if (sp != '') {
			sp = ensure_log_file(sp, 'system.log');
			let curp = sidecar_path('syslog', '.cursor-syslog');
			if (curp != '')
				persist_new_lines(logread_cmd('-l 400'), sp, curp);
			archive_if_needed(sp, chunk_sys, false);
			prune_old_logs(sp, pct);
		}
	}
	if (ctx.get('lede-log', 'kernel', 'enabled') != '0') {
		let kp = configured_path('kernel');
		if (kp != '') {
			kp = ensure_log_file(kp, 'kernel.log');
			let curp = sidecar_path('kernel', '.cursor-kmsg');
			if (curp != '')
				persist_new_lines('dmesg 2>/dev/null', kp, curp);
			archive_if_needed(kp, chunk_k, false);
			prune_old_logs(kp, pct);
		}
	}
}

/* line: TIME|LEVEL|CAT|TITLE|DETAIL */
export function append_event(path, max_kb, level, cat, title, detail) {
	level = level || '一般';
	if (level == '信息')
		return path;
	path = ensure_log_file(path, 'sys-alert.log');
	if (path == '')
		return null;
	archive_if_needed(path, max_kb, false);
	let fh = open(path, 'a');
	if (!fh) {
		let fallback = '/tmp/' + replace(path, /.*\//, '');
		if (fallback == path)
			fallback = '/tmp/lede-event.log';
		ensure_dir(fallback);
		fh = open(fallback, 'a');
		path = fallback;
	}
	if (!fh)
		return null;
	cat = cat || '系统';
	title = replace(`${title || ''}`, /\|/g, '/');
	detail = replace(`${detail || ''}`, /\|/g, '/');
	fh.write(sprintf('%s|%s|%s|%s|%s\n', now_fmt(), level, cat, title, detail));
	fh.close();
	return path;
}

export function parse_line(line) {
	line = replace(`${line}`, /\r$/, '');
	if (line == '')
		return null;
	let p = split(line, '|');
	if (length(p) >= 5) {
		return {
			time: p[0],
			level: p[1],
			cat: p[2],
			title: p[3],
			detail: join('|', slice(p, 4))
		};
	}
	/* legacy: "TIME KIND msg..." */
	let m = match(line, /^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\s+(\S+)\s+(.*)$/);
	if (m) {
		let kind = m[2];
		let level = '一般';
		let cat = '系统';
		if (kind == 'ALERT') { level = '中等'; cat = '系统'; }
		else if (kind == 'WAN') { level = match(m[3], /恢复/) ? '一般' : '中等'; cat = '网络'; }
		else if (kind == 'TEST') { level = '一般'; cat = '系统'; }
		else if (kind == 'INFO') { level = '一般'; cat = '系统'; }
		return { time: m[1], level, cat, title: kind, detail: m[3] };
	}
	return { time: '', level: '一般', cat: '系统', title: '原始', detail: line };
}

export function read_tail(path, max_lines) {
	max_lines = +max_lines;
	if (!(max_lines > 0))
		max_lines = 200;
	if (max_lines > 2000)
		max_lines = 2000;
	if (path == null || path == '' || !match(path, /^\//))
		return [];
	let text = readfile(path);
	if (text == null || text == '')
		return [];
	let lines = split(text, '\n');
	let out = [];
	let start = length(lines) - max_lines;
	if (start < 0)
		start = 0;
	for (let i = start; i < length(lines); i++) {
		let row = parse_line(lines[i]);
		if (row)
			push(out, row);
	}
	return out;
}
