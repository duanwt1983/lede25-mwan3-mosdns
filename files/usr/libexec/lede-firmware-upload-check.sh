#!/bin/sh
# Print human-readable OK/FAIL lines for firmware upload prerequisites.
set -eu
export PATH=/usr/sbin:/sbin:/usr/bin:/bin

. /usr/libexec/lede-firmware-cgi-io.sh

ok=0
fail=0
note(){ echo "OK: $*"; ok=$((ok + 1)); }
bad(){ echo "FAIL: $*"; fail=$((fail + 1)); }

if grep -q ' /data ' /proc/mounts 2>/dev/null; then
	note "/data mounted (block device)"
elif [ -d /data ] && [ -w /data ]; then
	note "/data writable (overlay — large images need LEDEDATA partition)"
else
	bad "/data not mounted and not writable (bootstrap or lede-data-setup)"
fi

_nginx_global_ok() {
	local f
	for f in /etc/nginx/uci.conf /etc/nginx/nginx.conf; do
		[ -f "$f" ] || continue
		grep -q 'client_max_body_size 0' "$f" 2>/dev/null && return 0
	done
	return 1
}
_nginx_global_ok && note "nginx global client_max_body_size 0" || \
	bad "nginx global body limit not 0 (run lede-firmware-bootstrap.sh)"

grep -q 'client_max_body_size 0' /etc/nginx/conf.d/luci.locations 2>/dev/null && \
	note "luci.locations cgi-upload limit 0" || bad "luci.locations missing upload limit 0"

grep -q 'limit-as = 8192' /etc/uwsgi/vassals/luci-cgi_io.ini 2>/dev/null && \
	note "uwsgi limit-as 8192" || bad "uwsgi limit-as not 8192"

grep -q 'reload-on-as = 0' /etc/uwsgi/vassals/luci-cgi_io.ini 2>/dev/null && \
	note "uwsgi reload-on-as disabled" || bad "uwsgi reload-on-as still enabled (kills large uploads)"

grep -q 'uwsgi_request_buffering off' /etc/nginx/conf.d/luci.locations 2>/dev/null && \
	note "nginx uwsgi_request_buffering off" || \
	bad "luci.locations missing uwsgi_request_buffering off"

tmp_kb=$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $2}')
tmp_h=$(df -h /tmp 2>/dev/null | awk 'NR==2 {print $2}')
if [ -n "$tmp_kb" ] && [ "$tmp_kb" -ge $((2600 * 1024)) ]; then
	note "/tmp tmpfs ready for multi-GB upload ($tmp_h)"
elif [ -f /var/run/lede-fw-upload-active ]; then
	bad "/tmp tmpfs too small ($tmp_h) — re-run upload-env before upload"
else
	note "/tmp tmpfs $tmp_h (upload-env grows RAM tmpfs on demand)"
fi

if lede_cgi_io_patched_dat; then
	bad "cgi-io patched to /dat (legacy) — run upload-sanity boot to restore /tmp"
elif lede_cgi_io_patched_tmp; then
	note "cgi-io temp /tmp (memory upload path)"
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
