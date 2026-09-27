#!/usr/bin/env ucode
'use strict';

import * as rtnl from "rtnl";
import * as uci from "uci";
import * as ubus from "ubus";
import { log_open, log_msg } from 'mwan3.common';

const RTM_GETROUTE = rtnl.const.RTM_GETROUTE;
const RTM_NEWROUTE = rtnl.const.RTM_NEWROUTE;
const NLM_F_DUMP = rtnl.const.NLM_F_DUMP;
const NLM_F_CREATE = rtnl.const.NLM_F_CREATE;
const NLM_F_REPLACE = rtnl.const.NLM_F_REPLACE;
const RT_TABLE_MAIN = rtnl.const.RT_TABLE_MAIN;
const AF_INET = rtnl.const.AF_INET;
const AF_INET6 = rtnl.const.AF_INET6;

const ROUTE_FIELDS = ["dst", "gateway", "oif", "prefsrc", "priority",
                      "scope", "type", "tos", "metrics", "onlink"];

function is_default_route(route) {
	return (route.dst == null ||
	        route.dst == "0.0.0.0/0" ||
	        route.dst == "::/0");
}

function is_zero_nexthop(gw, family) {
	if (gw == null || gw == "")
		return true;
	if (family == AF_INET)
		return (gw == "0.0.0.0");
	return (gw == "::");
}

function build_route_for_table(route, tid, src_routing) {
	let r = { family: route.family, table: tid };
	for (let f in ROUTE_FIELDS)
		if (route[f] != null)
			r[f] = route[f];
	if (r.tos == 0) delete r.tos;
	if (src_routing && route.src != null)
		r.src = route.src;
	return r;
}

function is_default_target(target, family) {
	if (target == null)
		return false;
	if (family == AF_INET)
		return (target == "0.0.0.0" || target == "0.0.0.0/0");
	return (target == "::" || target == "::/0");
}

// netifd still reports each WAN's own default even when main only keeps
// the lowest-metric one. Dual PPPoE with the same peer is the usual case:
// both interfaces have a kernel link route to 100.x, but only wan1's
// default is in main, so a copy-from-main never installs table N's default.
function iface_default_nexthop(intf, family) {
	if (intf.route) {
		for (let rt in intf.route) {
			if (!is_default_target(rt.target, family))
				continue;
			if (is_zero_nexthop(rt.nexthop, family))
				return { onlink: true };
			return { gateway: rt.nexthop };
		}
	}

	if (family == AF_INET && intf["ipv4-address"]) {
		for (let a in intf["ipv4-address"])
			if (a.ptpaddress)
				return { gateway: a.ptpaddress };
	}

	return null;
}

// Same nexthop on another mwan3 l3 device. Unique public gateways
// must not be forced onlink. Mixed: only the WANs that share a GW
// get onlink; the odd one out stays a normal via.
function gateway_shared_other_dev(dump_interfaces, gw, my_dev, family, table_map) {
	if (gw == null || gw == "" || my_dev == null)
		return false;
	for (let intf in dump_interfaces) {
		if (intf.l3_device == null || intf.l3_device == my_dev)
			continue;
		if (table_map != null && length(table_map) > 0 && table_map[intf.l3_device] == null)
			continue;
		let other = iface_default_nexthop(intf, family);
		if (other && other.gateway == gw)
			return true;
	}
	return false;
}

function attach_shared_onlink(r, dump_interfaces, family, table_map) {
	if (!is_default_route(r) || r.gateway == null)
		return;
	if (r.onlink)
		return;
	if (gateway_shared_other_dev(dump_interfaces, r.gateway, r.oif, family, table_map))
		r.onlink = true;
}

let family_num = (ARGV[0] == "6") ? AF_INET6 : AF_INET;
let family_name = (ARGV[0] == "6") ? "ipv6" : "ipv4";
let table_id = +ARGV[1];
let source_routing = +ARGV[2];

let cur = uci.cursor();
cur.load("mwan3");

let extra_table_set = {};
let rt_tables = cur.get("mwan3", "globals", "rt_table_lookup");
if (type(rt_tables) == "array") {
	for (let t in rt_tables)
		extra_table_set[+t] = true;
} else if (rt_tables != null) {
	extra_table_set[+rt_tables] = true;
}

let name_tid = {};
let tid = 0;
cur.foreach("mwan3", "interface", function(s) {
	tid++;
	let fam = s.family ?? "ipv4";
	let enabled = +(s.enabled ?? "0");
	if (enabled && fam == family_name)
		name_tid[s[".name"]] = tid;
});
cur.unload("mwan3");

log_open("mwan3-create-iface-route");

let dump_interfaces = [];
let dev_table_map = {};
let uconn = ubus.connect();
if (uconn) {
	let dump = uconn.call("network.interface", "dump");
	if (dump && dump.interface) {
		dump_interfaces = dump.interface;
		for (let intf in dump_interfaces) {
			let name = intf.interface;
			let t = name_tid[name];
			if (t == null) {
				let m = match(name, /^(.+)_([46])$/);
				if (m) {
					let suffix_fam = (m[2] == "4") ? "ipv4" : "ipv6";
					if (suffix_fam == family_name)
						t = name_tid[m[1]];
				}
			}
			if (t != null && intf.l3_device)
				dev_table_map[intf.l3_device] = t;
		}
	}
	uconn.disconnect();
}

let all_routes = rtnl.request(RTM_GETROUTE, NLM_F_DUMP, { family: family_num }) ?? [];

let source_routes = [];
for (let r in all_routes) {
	if (r.table == RT_TABLE_MAIN || extra_table_set[r.table])
		push(source_routes, r);
}

let existing_keys = {};
for (let r in all_routes) {
	if (r.table != table_id) continue;
	let key = (r.dst ?? "") + "|" + (r.oif ?? "") + "|" + (r.gateway ?? "") + "|" + (r.priority ?? "");
	existing_keys[key] = true;
}

for (let route in source_routes) {
	let dev = route.oif;
	let target_tid = (dev != null) ? dev_table_map[dev] : null;

	if (is_default_route(route) || route.dst == "fe80::/64") {
		if (target_tid != table_id) continue;
	} else if (target_tid != null && target_tid != table_id) {
		continue;
	}

	let key = (route.dst ?? "") + "|" + (route.oif ?? "") + "|" + (route.gateway ?? "") + "|" + (route.priority ?? "");
	if (existing_keys[key]) continue;

	let r = build_route_for_table(route, table_id, source_routing);
	attach_shared_onlink(r, dump_interfaces, family_num, dev_table_map);
	rtnl.request(RTM_NEWROUTE, NLM_F_CREATE | NLM_F_REPLACE, r);
	let err = rtnl.error();
	if (err)
		log_msg("err", sprintf("table %d: %s", table_id, err));
}

let my_devs = {};
for (let d in keys(dev_table_map))
	if (dev_table_map[d] == table_id)
		my_devs[d] = true;

for (let intf in dump_interfaces) {
	let dev = intf.l3_device;
	if (dev == null || !my_devs[dev])
		continue;
	let nh = iface_default_nexthop(intf, family_num);
	if (nh == null)
		continue;

	let r = {
		family: family_num,
		table: table_id,
		oif: dev,
		dst: (family_num == AF_INET) ? "0.0.0.0/0" : "::/0"
	};
	if (nh.gateway)
		r.gateway = nh.gateway;
	if (nh.onlink || gateway_shared_other_dev(dump_interfaces, nh.gateway, dev, family_num, dev_table_map))
		r.onlink = true;

	rtnl.request(RTM_NEWROUTE, NLM_F_CREATE | NLM_F_REPLACE, r);
	let err = rtnl.error();
	if (err)
		log_msg("err", sprintf("table %d synthesize default: %s", table_id, err));
	else if (r.onlink)
		log_msg("notice", sprintf("table %d: default via %s dev %s onlink",
			table_id, nh.gateway ?? "on-link", dev));
}
