#!/bin/sh
# Print human-readable OK/FAIL lines for firmware upload prerequisites.
set -eu
export PATH=/usr/sbin:/sbin:/usr/bin:/bin

ok=0
fail=0
note(){ echo "OK: $*"; ok=$((ok + 1)); }
bad(){ echo "FAIL: $*"; fail=$((fail + 1)); }

df -h /data 2>/dev/null | grep -q /data && note "/data mounted" || bad "/data not mounted"

grep -q 'client_max_body_size 0' /etc/nginx/uci.conf 2>/dev/null && \
	note "nginx client_max_body_size 0" || bad "nginx global body limit not 0"

grep -q 'client_body_temp_path /data/nginx-body' /etc/nginx/uci.conf 2>/dev/null && \
	note "nginx body temp on /data" || bad "nginx body temp not on /data/nginx-body"

grep -q 'client_max_body_size 0' /etc/nginx/conf.d/luci.locations 2>/dev/null && \
	note "luci.locations cgi-upload limit 0" || bad "luci.locations missing upload limit 0"

grep -q 'limit-as = 8192' /etc/uwsgi/vassals/luci-cgi_io.ini 2>/dev/null && \
	note "uwsgi limit-as 8192" || bad "uwsgi limit-as not 8192"

grep -q 'reload-on-as = 0' /etc/uwsgi/vassals/luci-cgi_io.ini 2>/dev/null && \
	note "uwsgi reload-on-as disabled" || bad "uwsgi reload-on-as still enabled (kills large uploads)"

if grep -q ' /dat ' /proc/mounts 2>/dev/null; then
	note "/dat bind mount (upload session active)"
else
	note "/dat not mounted (idle; upload-env mounts only during firmware upload)"
fi

if strings /usr/libexec/cgi-io 2>/dev/null | grep -qx '/dat'; then
	note "cgi-io temp path /dat"
elif strings /usr/libexec/cgi-io 2>/dev/null | grep -qx '/tmp'; then
	bad "cgi-io still uses /tmp"
else
	bad "cgi-io path unknown"
fi

[ -x /usr/libexec/lede-firmware-prepare.sh ] && note "lede-firmware-prepare.sh" || bad "prepare script missing"

_lede_stage2_ok() {
	grep -q 'LEDE: 刷写已完成' /lib/upgrade/do_stage2 2>/dev/null && \
		! grep -E '^[[:space:]]*umount -a' /lib/upgrade/do_stage2 2>/dev/null
}
if _lede_stage2_ok; then
	note "do_stage2 LEDE reboot (no umount -a)"
elif [ -x /usr/libexec/lede-firmware-restore-upgrade.sh ]; then
	/usr/libexec/lede-firmware-restore-upgrade.sh && _lede_stage2_ok && \
		note "do_stage2 LEDE reboot (restored)" || \
		bad "do_stage2 still stock (umount -a hangs x86 /data)"
else
	bad "do_stage2 still stock (umount -a hangs x86 /data)"
fi

echo "SUMMARY ok=$ok fail=$fail"
[ "$fail" -eq 0 ]
