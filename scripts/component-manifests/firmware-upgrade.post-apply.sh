#!/bin/sh
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
set -eu

STAGE_NGINX=/www/luci-static/resources/lede-firmware/nginx-luci.locations
STAGE_UWSGI=/www/luci-static/resources/lede-firmware/uwsgi-luci-cgi_io.ini

[ -x /usr/libexec/lede-firmware-restore-upgrade.sh ] && \
	/usr/libexec/lede-firmware-restore-upgrade.sh
[ -x /usr/libexec/lede-firmware-upload-sanity.sh ] && \
	/usr/libexec/lede-firmware-upload-sanity.sh boot
mkdir -p /dat
[ -x /usr/libexec/lede-firmware-upload-env.sh ] && /usr/libexec/lede-firmware-upload-env.sh

if [ -f "$STAGE_NGINX" ]; then
	cp -f "$STAGE_NGINX" /etc/nginx/conf.d/luci.locations
fi
if [ -f "$STAGE_UWSGI" ]; then
	mkdir -p /etc/uwsgi/vassals
	cp -f "$STAGE_UWSGI" /etc/uwsgi/vassals/luci-cgi_io.ini
fi

/etc/init.d/lede-cgi-tmp disable 2>/dev/null || true

/etc/init.d/uwsgi restart 2>/dev/null || true
/etc/init.d/nginx reload 2>/dev/null || /etc/init.d/nginx restart 2>/dev/null || true

[ -x /usr/libexec/lede-firmware-upload-check.sh ] && \
	/usr/libexec/lede-firmware-upload-check.sh >> /tmp/lede-component-apply.log 2>&1 || true

rm -rf /tmp/luci-*cache* 2>/dev/null || true
[ -x /sbin/luci-clear-cache ] && /sbin/luci-clear-cache 2>/dev/null || true
exit 0
