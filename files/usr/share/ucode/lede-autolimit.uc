'use strict';

import { cursor } from 'uci';
import { readfile, writefile, popen, stat } from 'fs';
import { bandix_port, bandix_load } from '/usr/share/ucode/lede-bandix.uc';

const TRACK_PATH = '/tmp/lede-autolimit-track.json';
const ACTIVE_TMP = '/tmp/lede-autolimit-active.json';
const HISTORY_TMP = '/tmp/lede-autolimit-history.json';

function lc(s) {
	s = `${s}`;
	let out = '';
	for (let i = 0; i < length(s); i++) {
		let c = substr(s, i, 1);
		let o = ord(c);
		if (o >= 65 && o <= 90)
			out += sprintf('%c', o + 32);
		else
			out += c;
	}
	return out;
}

function norm_mac(mac) {
	return replace(lc(trim(`${mac}`)), /[^a-f0-9]/g, '');
}

function trim(s) {
	s = `${s}`;
	let a = 0;
	let b = length(s);
	while (a < b && (substr(s, a, 1) == ' ' || substr(s, a, 1) == '\t'))
		a++;
	while (b > a) {
		let c = substr(s, b - 1, 1);
		if (c == ' ' || c == '\t')
			b--;
		else
			break;
	}
	return substr(s, a, b - a);
}

function metrics_dir() {
	if (stat('/data/.lede-data') != null) {
		if (stat('/data/metrics') == null)
			system('mkdir -p /data/metrics >/dev/null 2>&1');
		return '/data/metrics';
	}
	return '/tmp';
}

function active_path() {
	return metrics_dir() + '/lede-autolimit-active.json';
}

function history_path() {
	let dir = metrics_dir();
	if (dir == '/tmp')
		return HISTORY_TMP;
	return dir + '/lede-autolimit-history.json';
}

function read_json(path, fb) {
	try {
		let raw = readfile(path);
		if (raw == null || raw == '')
			return fb;
		let j = json(raw);
		if (j == null)
			return fb;
		return j;
	} catch (e) {
		return fb;
	}
}

function write_json(path, obj) {
	try {
		writefile(path, sprintf('%J\n', obj));
		return true;
	} catch (e) {
		return false;
	}
}

function bandix_base() {
	return sprintf('http://127.0.0.1:%d', bandix_port());
}

function bandix_curl(method, url, body) {
	let tmp = '/tmp/lede-autolimit-req.json';
	if (body != null) {
		if (type(body) == 'string')
			writefile(tmp, body);
		else
			writefile(tmp, sprintf('%J', body));
		let cmd = sprintf(
			'curl -sf --connect-timeout 2 --max-time 15 -X %s -H "Content-Type: application/json" -d @%s %s 2>/dev/null',
			method, tmp, url
		);
		let p = popen(cmd, 'r');
		if (!p)
			return null;
		let raw = p.read('all') || '';
		p.close();
		return raw;
	}
	let cmd = sprintf('curl -sf --connect-timeout 2 --max-time 15 -X %s %s 2>/dev/null', method, url);
	let p = popen(cmd, 'r');
	if (!p)
		return null;
	let raw = p.read('all') || '';
	p.close();
	return raw;
}

function bandix_ok(raw) {
	if (raw == null || raw == '')
		return false;
	try {
		let j = json(raw);
		if (!j)
			return false;
		if (j.ok === false)
			return false;
		if (j.ok === true)
			return true;
		if (j.status == 'success')
			return true;
		return true;
	} catch (e) {
		return false;
	}
}

function bandix_parse(raw) {
	if (raw == null || raw == '')
		return null;
	try {
		return json(raw);
	} catch (e) {
		return null;
	}
}

function load_whitelist(ctx) {
	let set = {};
	if (!ctx)
		return set;
	ctx.foreach('lede-autolimit', 'whitelist', function(s) {
		let mac = norm_mac(s.mac || '');
		if (mac != '')
			set[mac] = trim(s.name || '') || '白名单';
	});
	return set;
}

export function autolimit_load_config() {
	let ctx = cursor();
	let cfg = {
		enabled: false,
		down_threshold_kbps: 50000,
		up_threshold_kbps: 15000,
		down_sustain_minutes: 30,
		up_sustain_minutes: 20,
		limit_down_kbps: 10000,
		limit_up_kbps: 1000,
		limit_minutes: 30,
		penalty_window_minutes: 30,
		penalty_limit_minutes: 120,
		interval_sec: 60,
		iface: 'br-lan',
		whitelist: {}
	};
	try {
		ctx.load('lede-autolimit');
	} catch (e) {
		return cfg;
	}
	let en = ctx.get('lede-autolimit', 'main', 'enabled');
	cfg.enabled = (en == '1' || en == 'true');
	cfg.down_threshold_kbps = +(ctx.get('lede-autolimit', 'main', 'down_threshold_kbps') || cfg.down_threshold_kbps);
	cfg.up_threshold_kbps = +(ctx.get('lede-autolimit', 'main', 'up_threshold_kbps') || cfg.up_threshold_kbps);
	cfg.down_sustain_minutes = +(ctx.get('lede-autolimit', 'main', 'down_sustain_minutes') ||
		ctx.get('lede-autolimit', 'main', 'sustain_minutes') || cfg.down_sustain_minutes);
	cfg.up_sustain_minutes = +(ctx.get('lede-autolimit', 'main', 'up_sustain_minutes') ||
		ctx.get('lede-autolimit', 'main', 'sustain_minutes') || cfg.up_sustain_minutes);
	cfg.limit_down_kbps = +(ctx.get('lede-autolimit', 'main', 'limit_down_kbps') || cfg.limit_down_kbps);
	cfg.limit_up_kbps = +(ctx.get('lede-autolimit', 'main', 'limit_up_kbps') || cfg.limit_up_kbps);
	cfg.limit_minutes = +(ctx.get('lede-autolimit', 'main', 'limit_minutes') || cfg.limit_minutes);
	cfg.penalty_window_minutes = +(ctx.get('lede-autolimit', 'main', 'penalty_window_minutes') || cfg.penalty_window_minutes);
	cfg.penalty_limit_minutes = +(ctx.get('lede-autolimit', 'main', 'penalty_limit_minutes') || cfg.penalty_limit_minutes);
	cfg.interval_sec = +(ctx.get('lede-autolimit', 'main', 'interval_sec') || cfg.interval_sec);
	cfg.iface = trim(ctx.get('lede-autolimit', 'main', 'iface') || cfg.iface);
	cfg.whitelist = load_whitelist(ctx);

	if (cfg.down_threshold_kbps < 0) cfg.down_threshold_kbps = 0;
	if (cfg.up_threshold_kbps < 0) cfg.up_threshold_kbps = 0;
	if (cfg.down_sustain_minutes < 1) cfg.down_sustain_minutes = 1;
	if (cfg.up_sustain_minutes < 1) cfg.up_sustain_minutes = 1;
	if (cfg.limit_down_kbps < 0) cfg.limit_down_kbps = 0;
	if (cfg.limit_up_kbps < 0) cfg.limit_up_kbps = 0;
	if (cfg.limit_minutes < 1) cfg.limit_minutes = 1;
	if (cfg.penalty_window_minutes < 1) cfg.penalty_window_minutes = 1;
	if (cfg.penalty_limit_minutes < 1) cfg.penalty_limit_minutes = 1;
	if (cfg.interval_sec < 10) cfg.interval_sec = 10;
	if (cfg.iface == '')
		cfg.iface = 'br-lan';
	return cfg;
}

function load_active() {
	return read_json(active_path(), { clients: [] });
}

function save_active(st) {
	if (type(st) != 'object' || type(st.clients) != 'array')
		st = { clients: [] };
	write_json(active_path(), st);
	write_json(ACTIVE_TMP, st);
}

function load_track() {
	return read_json(TRACK_PATH, { macs: {} });
}

function save_track(st) {
	if (type(st) != 'object' || type(st.macs) != 'object')
		st = { macs: {} };
	write_json(TRACK_PATH, st);
}

function load_history() {
	return read_json(history_path(), { macs: {} });
}

function save_history(st) {
	if (type(st) != 'object' || type(st.macs) != 'object')
		st = { macs: {} };
	write_json(history_path(), st);
	write_json(HISTORY_TMP, st);
}

function record_release(mac, now) {
	let mk = norm_mac(mac);
	if (mk == '')
		return;
	let hist = load_history();
	if (type(hist.macs) != 'object')
		hist.macs = {};
	hist.macs[mk] = { released_at: now };
	save_history(hist);
}

function is_whitelisted(cfg, mac) {
	let mk = norm_mac(mac);
	return mk != '' && cfg.whitelist && cfg.whitelist[mk] != null;
}

function active_by_mac(st, mac) {
	let key = norm_mac(mac);
	for (let i = 0; i < length(st.clients); i++) {
		let c = st.clients[i];
		if (norm_mac(c.mac) == key)
			return c;
	}
	return null;
}

function client_rates(dev) {
	let m = dev.metrics || {};
	let down_bps = +(m.down_v4_bps || 0) + +(m.down_v6_bps || 0);
	let up_bps = +(m.up_v4_bps || 0) + +(m.up_v6_bps || 0);
	return {
		down_kbps: int(down_bps / 1000),
		up_kbps: int(up_bps / 1000)
	};
}

function device_label(dev) {
	let h = trim(dev.hostname || '');
	if (h != '' && h != '-')
		return h;
	if (type(dev.ipv4) == 'array') {
		for (let ip in dev.ipv4) {
			if (ip)
				return ip;
		}
	}
	return dev.mac || '';
}

function device_ip(dev) {
	if (type(dev.ipv4) == 'array') {
		for (let ip in dev.ipv4) {
			if (ip)
				return ip;
		}
	}
	return '';
}

function device_iface(dev) {
	return trim(dev.logical_iface || dev.iface || dev.ifname || '');
}

function bandix_list_schedules() {
	let raw = bandix_curl('GET', bandix_base() + '/api/rate_limit/schedules', null);
	let j = bandix_parse(raw);
	if (!j)
		return [];
	let data = j.data;
	if (type(data) == 'array')
		return data;
	if (type(data) == 'object' && type(data.schedules) == 'array')
		return data.schedules;
	if (type(data) == 'object' && type(data.items) == 'array')
		return data.items;
	return [];
}

function schedule_id_from_response(j) {
	if (!j || type(j) != 'object')
		return '';
	if (j.data != null) {
		if (type(j.data) == 'object' && j.data.id != null)
			return `${j.data.id}`;
		if (type(j.data) == 'string' || type(j.data) == 'number')
			return `${j.data}`;
	}
	if (j.id != null)
		return `${j.id}`;
	return '';
}

function bandix_create_auto_schedule(iface, mac, down_kbps, up_kbps) {
	let payload = {
		iface: iface,
		mac: mac,
		time_slot: {
			start: '00:00',
			end: '23:59',
			days: [ 1, 2, 3, 4, 5, 6, 7 ]
		},
		down_v4_kbps: +(down_kbps || 0),
		down_v6_kbps: 0,
		up_v4_kbps: +(up_kbps || 0),
		up_v6_kbps: 0
	};
	let raw = bandix_curl('POST', bandix_base() + '/api/rate_limit/schedules', payload);
	let j = bandix_parse(raw);
	if (!bandix_ok(raw)) {
		let err = 'create failed';
		if (j && j.error)
			err = j.error;
		return { ok: false, error: err, id: '' };
	}
	let sid = schedule_id_from_response(j);
	if (sid == '') {
		let list = bandix_list_schedules();
		let mk = norm_mac(mac);
		for (let i = length(list) - 1; i >= 0; i--) {
			let r = list[i];
			if (norm_mac(r.mac) == mk && trim(r.iface || '') == trim(iface || '')) {
				sid = `${r.id || ''}`;
				if (sid != '')
					break;
			}
		}
	}
	if (sid == '')
		return { ok: false, error: 'no schedule id', id: '' };
	return { ok: true, id: sid };
}

export function bandix_delete_schedule(id) {
	if (id == null || `${id}` == '')
		return false;
	let url = bandix_base() + '/api/rate_limit/schedules/' + replace(`${id}`, /\+/g, '%2B');
	let raw = bandix_curl('DELETE', url, null);
	if (bandix_ok(raw))
		return true;
	let j = bandix_parse(raw);
	if (j && j.error != null) {
		let err = lc(`${j.error}`);
		if (match(err, /not found/) != null || match(err, /unknown/) != null)
			return true;
	}
	return raw == null || raw == '';
}

function bandix_clear_schedules_for_mac(mac, iface) {
	let mk = norm_mac(mac);
	if (mk == '')
		return false;
	let want_iface = trim(iface || '');
	let cleared = false;
	let list = bandix_list_schedules();
	for (let i = length(list) - 1; i >= 0; i--) {
		let r = list[i];
		if (norm_mac(r.mac) != mk)
			continue;
		if (want_iface != '' && trim(r.iface || '') != '' && trim(r.iface) != want_iface)
			continue;
		let sid = `${r.id || ''}`;
		if (sid != '' && bandix_delete_schedule(sid))
			cleared = true;
	}
	return cleared;
}

function remove_active_index(st, idx) {
	let out = [];
	for (let i = 0; i < length(st.clients); i++) {
		if (i != idx)
			push(out, st.clients[i]);
	}
	st.clients = out;
}

export function autolimit_release_mac(mac) {
	let key = norm_mac(mac);
	if (key == '')
		return { ok: false, error: 'invalid mac' };

	let cfg = autolimit_load_config();
	let st = load_active();
	let found = null;
	let idx = -1;
	for (let i = 0; i < length(st.clients); i++) {
		if (norm_mac(st.clients[i].mac) == key) {
			found = st.clients[i];
			idx = i;
			break;
		}
	}

	let iface = cfg.iface;
	if (found && trim(found.iface || '') != '')
		iface = found.iface;

	let cleared = bandix_clear_schedules_for_mac(mac, iface);
	if (found) {
		if (found.schedule_id)
			bandix_delete_schedule(found.schedule_id);
		remove_active_index(st, idx);
		save_active(st);
	}

	if (!found && !cleared)
		return { ok: false, error: 'not found' };

	let tr = load_track();
	if (type(tr.macs) == 'object' && tr.macs[key] != null) {
		delete tr.macs[key];
		save_track(tr);
	}
	return { ok: true, cleared: cleared };
}

function expire_active_clients(st, now) {
	let i = 0;
	while (i < length(st.clients)) {
		let c = st.clients[i];
		let exp = +(c.expires || 0);
		if (exp > 0 && now >= exp) {
			if (c.schedule_id)
				bandix_delete_schedule(c.schedule_id);
			record_release(c.mac, now);
			remove_active_index(st, i);
			continue;
		}
		i++;
	}
}

function lan_devices(cfg) {
	let bj = bandix_load(true);
	if (!bj || !bj.data || type(bj.data.devices) != 'array')
		return { ok: false, devices: [] };
	let want = trim(cfg.iface || 'br-lan');
	let out = [];
	for (let dev in bj.data.devices) {
		if (type(dev) != 'object')
			continue;
		if (dev.online != true)
			continue;
		let iface = device_iface(dev);
		if (want != '' && iface != '' && iface != want)
			continue;
		let mac = trim(dev.mac || '');
		if (mac == '')
			continue;
		push(out, dev);
	}
	return { ok: true, devices: out };
}

function limit_duration_minutes(cfg, mac, now) {
	let mk = norm_mac(mac);
	let hist = load_history();
	let rel = 0;
	if (hist.macs && hist.macs[mk])
		rel = +(hist.macs[mk].released_at || 0);
	if (rel > 0 && cfg.penalty_window_minutes > 0 &&
	    now - rel <= cfg.penalty_window_minutes * 60)
		return { minutes: cfg.penalty_limit_minutes, penalty: true };
	return { minutes: cfg.limit_minutes, penalty: false };
}

function build_reason(down_hit, up_hit, penalty) {
	let reason = '';
	if (down_hit)
		reason = '下行超阈';
	if (up_hit) {
		if (reason != '')
			reason = reason + '+上行超阈';
		else
			reason = '上行超阈';
	}
	if (reason == '')
		reason = '超阈';
	if (penalty)
		reason += '·加罚';
	return reason;
}

export function autolimit_tick() {
	let cfg = autolimit_load_config();
	let now = time();
	let active = load_active();
	expire_active_clients(active, now);

	if (!cfg.enabled) {
		let i = 0;
		while (i < length(active.clients)) {
			let c = active.clients[i];
			if (c.schedule_id)
				bandix_delete_schedule(c.schedule_id);
			remove_active_index(active, i);
		}
		save_track({ macs: {} });
		save_active(active);
		return { ok: true, enabled: false };
	}

	let sched_raw = bandix_curl('GET', bandix_base() + '/api/rate_limit/schedules', null);
	if (sched_raw != null && sched_raw != '') {
		let live = bandix_list_schedules();
		let ids = {};
		for (let r in live) {
			let sid = `${r.id || ''}`;
			if (sid != '')
				ids[sid] = true;
		}
		let i = 0;
		while (i < length(active.clients)) {
			let sid = `${active.clients[i].schedule_id || ''}`;
			if (sid != '' && !ids[sid]) {
				remove_active_index(active, i);
				continue;
			}
			i++;
		}
	}

	let snap = lan_devices(cfg);
	if (!snap.ok) {
		save_active(active);
		return { ok: false, error: 'bandix unavailable' };
	}

	let down_sustain_sec = cfg.down_sustain_minutes * 60;
	let up_sustain_sec = cfg.up_sustain_minutes * 60;
	let monitor_down = cfg.down_threshold_kbps > 0;
	let monitor_up = cfg.up_threshold_kbps > 0;
	let can_limit_down = cfg.limit_down_kbps > 0;
	let can_limit_up = cfg.limit_up_kbps > 0;

	let track = load_track();
	let changed_track = false;
	let changed_active = false;

	for (let dev in snap.devices) {
		let mac = trim(dev.mac || '');
		let mk = norm_mac(mac);
		if (mk == '')
			continue;
		if (is_whitelisted(cfg, mac))
			continue;
		if (active_by_mac(active, mac))
			continue;

		let rates = client_rates(dev);
		let t = track.macs[mk];
		if (type(t) != 'object')
			t = { down_since: 0, up_since: 0 };
		if (monitor_down && rates.down_kbps >= cfg.down_threshold_kbps) {
			if (!(t.down_since > 0))
				t.down_since = now;
		} else {
			t.down_since = 0;
		}

		if (monitor_up && rates.up_kbps >= cfg.up_threshold_kbps) {
			if (!(t.up_since > 0))
				t.up_since = now;
		} else {
			t.up_since = 0;
		}

		track.macs[mk] = t;
		changed_track = true;

		let down_hit = monitor_down && can_limit_down &&
			t.down_since > 0 && now - t.down_since >= down_sustain_sec;
		let up_hit = monitor_up && can_limit_up &&
			t.up_since > 0 && now - t.up_since >= up_sustain_sec;
		if (!down_hit && !up_hit)
			continue;

		let apply_down = 0;
		let apply_up = 0;
		if (down_hit)
			apply_down = cfg.limit_down_kbps;
		if (up_hit)
			apply_up = cfg.limit_up_kbps;
		let dur = limit_duration_minutes(cfg, mac, now);
		let iface = device_iface(dev) || cfg.iface;
		let created = bandix_create_auto_schedule(iface, mac, apply_down, apply_up);
		if (!created.ok)
			continue;

		let pen = 0;
		if (dur.penalty)
			pen = 1;
		push(active.clients, {
			mac: mac,
			iface: iface,
			ip: device_ip(dev),
			hostname: device_label(dev),
			schedule_id: created.id,
			started: now,
			expires: now + dur.minutes * 60,
			limit_down_kbps: apply_down,
			limit_up_kbps: apply_up,
			trigger_down_kbps: rates.down_kbps,
			trigger_up_kbps: rates.up_kbps,
			reason: build_reason(down_hit, up_hit, dur.penalty),
			penalty: pen
		});
		delete track.macs[mk];
		changed_active = true;
	}

	if (changed_track)
		save_track(track);
	if (changed_active || length(active.clients) > 0)
		save_active(active);

	return { ok: true, enabled: true, active: length(active.clients) };
}

function whitelist_list(cfg) {
	let out = [];
	if (!cfg.whitelist)
		return out;
	for (let mk in cfg.whitelist)
		push(out, { mac: mk, name: cfg.whitelist[mk] });
	return out;
}

export function autolimit_status() {
	let cfg = autolimit_load_config();
	let now = time();
	let active = load_active();
	expire_active_clients(active, now);
	save_active(active);

	let rate_map = {};
	let snap = lan_devices(cfg);
	if (snap.ok) {
		for (let dev in snap.devices) {
			let mk = norm_mac(dev.mac);
			rate_map[mk] = client_rates(dev);
		}
	}

	let rows = [];
	for (let c in active.clients) {
		let mk = norm_mac(c.mac);
		let rt = rate_map[mk] || { down_kbps: 0, up_kbps: 0 };
		let exp = +(c.expires || 0);
		let remain = 0;
		if (exp > now)
			remain = exp - now;
		push(rows, {
			mac: c.mac || '',
			iface: c.iface || '',
			ip: c.ip || '',
			hostname: c.hostname || '',
			limit_down_kbps: +(c.limit_down_kbps || 0),
			limit_up_kbps: +(c.limit_up_kbps || 0),
			current_down_kbps: rt.down_kbps,
			current_up_kbps: rt.up_kbps,
			started: +(c.started || 0),
			expires: exp,
			remain_sec: remain,
			reason: c.reason || '',
			penalty: c.penalty == 1
		});
	}

	let track_n = 0;
	for (let tk in (load_track().macs || {}))
		track_n++;

	let wl = whitelist_list(cfg);
	return {
		ok: true,
		bandix_ok: snap.ok,
		enabled: cfg.enabled,
		config: cfg,
		whitelist: wl,
		active: rows,
		track_n: track_n
	};
}
