#!/bin/sh
# Idempotent stack for multi-GB LuCI cgi-upload → /data/firmware.bin
# Fixes: nginx body limit/temp dir, uwsgi memory reload, cgi-io /tmp → /dat bind.
set -eu
export PATH=/usr/sbin:/sbin:/usr/bin:/bin

mkdir -p /data/nginx-body /data/cgi-tmp
mkdir -p /dat
chmod 700 /data/nginx-body /data/cgi-tmp 2>/dev/null || true
chmod 755 /dat 2>/dev/null || true

for f in /etc/nginx/uci.conf /etc/nginx/uci.conf.template; do
	[ -f "$f" ] || continue
	if grep -q 'client_max_body_size' "$f"; then
		sed -i 's/client_max_body_size[^;]*;/client_max_body_size 0;/g' "$f"
	else
		sed -i '/http {/a\        client_max_body_size 0;' "$f" 2>/dev/null || true
	fi
	grep -q 'client_body_temp_path /data/nginx-body' "$f" || \
		sed -i '/client_max_body_size 0;/a\        client_body_temp_path /data/nginx-body;' "$f"
done

if ! grep -q ' /dat ' /proc/mounts 2>/dev/null; then
	mount --bind /data/cgi-tmp /dat || {
		echo "lede-firmware-upload-env: bind /data/cgi-tmp -> /dat failed" >&2
		exit 1
	}
fi

patch_cgi_io() {
	local bin=/usr/libexec/cgi-io
	[ -f "$bin" ] || return 0
	if strings "$bin" 2>/dev/null | grep -qx '/dat'; then
		return 0
	fi
	local off cur
	for off in $(grep -abo '/tmp' "$bin" 2>/dev/null | cut -d: -f1); do
		cur=$(dd if="$bin" bs=1 skip="$off" count=4 2>/dev/null || true)
		if [ "$cur" = "/tmp" ]; then
			printf '/dat' | dd of="$bin" bs=1 seek="$off" conv=notrunc 2>/dev/null || true
			return 0
		fi
	done
	# Legacy offset (older cgi-io builds)
	cur=$(dd if="$bin" bs=1 skip=17084 count=4 2>/dev/null || true)
	if [ "$cur" = "/tmp" ]; then
		printf '/dat' | dd of="$bin" bs=1 seek=17084 conv=notrunc 2>/dev/null || true
	fi
}
patch_cgi_io

rm -f /tmp/sysupgrade.img /tmp/image.bs 2>/dev/null || true
exit 0
