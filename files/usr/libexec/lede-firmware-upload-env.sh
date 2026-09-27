#!/bin/sh
# On-demand prep for multi-GB LuCI cgi-upload → /data/firmware.bin (call before upload/validate).
set -eu
export PATH=/usr/sbin:/sbin:/usr/bin:/bin

. /usr/libexec/lede-firmware-cgi-io.sh

[ -x /usr/libexec/lede-firmware-restore-upgrade.sh ] && \
	/usr/libexec/lede-firmware-restore-upgrade.sh || true

if ! grep -q ' /data ' /proc/mounts 2>/dev/null; then
	echo "lede-firmware-upload-env: /data partition not mounted yet" >&2
	exit 1
fi

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
		echo "lede-firmware-upload-env: bind /data/cgi-tmp -> /dat failed (is /data mounted?)" >&2
		exit 1
	}
fi

lede_cgi_io_patch_dat
mkdir -p "$(dirname "$LEDE_FW_UPLOAD_ACTIVE")"
: >"$LEDE_FW_UPLOAD_ACTIVE"

rm -f /tmp/sysupgrade.img /tmp/image.bs 2>/dev/null || true
exit 0
