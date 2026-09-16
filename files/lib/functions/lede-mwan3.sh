# Shared: mwan3 helpers stay idle until the user adds an enabled interface.

lede_mwan3_ready() {
	local sid
	[ -f /etc/config/mwan3 ] || return 1
	[ "$(uci -q get mwan3.globals.lede_lb_paused)" = "1" ] && return 1
	for sid in $(uci -q show mwan3 2>/dev/null | sed -n 's/^mwan3\.\([^.]*\)=interface$/\1/p'); do
		[ "$(uci -q get "mwan3.${sid}.enabled")" = "0" ] && continue
		return 0
	done
	return 1
}

lede_mwan3_helper_crons_sync() {
	local f=/etc/crontabs/root
	mkdir -p /etc/crontabs
	touch "$f"
	if lede_mwan3_ready; then
		grep -q '25-multiwan-main-default' "$f" 2>/dev/null || \
			echo '*/2 * * * * /bin/sh /etc/hotplug.d/iface/25-multiwan-main-default' >> "$f"
		grep -q '27-mwan3-iface-default' "$f" 2>/dev/null || \
			echo '*/2 * * * * /bin/sh /etc/hotplug.d/iface/27-mwan3-iface-default' >> "$f"
		grep -q '29-mwan3-policy-live' "$f" 2>/dev/null || \
			echo '* * * * * /bin/sh /etc/hotplug.d/iface/29-mwan3-policy-live' >> "$f"
	else
		if grep -qE '25-multiwan-main-default|27-mwan3-iface-default|29-mwan3-policy-live' "$f" 2>/dev/null; then
			sed -i '/25-multiwan-main-default/d;/27-mwan3-iface-default/d;/29-mwan3-policy-live/d' "$f"
		fi
	fi
}
