#!/bin/sh
# Install nginx/uwsgi snippets (component apply whitelist cannot write /etc/nginx directly on old apply).
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
set -eu

STAGE_NGINX=/www/luci-static/resources/lede-firmware/nginx-luci.locations
STAGE_UWSGI=/www/luci-static/resources/lede-firmware/uwsgi-luci-cgi_io.ini

mkdir -p /data/nginx-body /data/cgi-tmp /dat
chmod 700 /data/nginx-body 2>/dev/null || true

if [ -f "$STAGE_NGINX" ]; then
	cp -f "$STAGE_NGINX" /etc/nginx/conf.d/luci.locations
fi
if [ -f "$STAGE_UWSGI" ]; then
	mkdir -p /etc/uwsgi/vassals
	cp -f "$STAGE_UWSGI" /etc/uwsgi/vassals/luci-cgi_io.ini
fi

/etc/uci-defaults/45-nginx-firmware-upload 2>/dev/null || true
/etc/init.d/lede-cgi-tmp enable 2>/dev/null || true
/etc/init.d/lede-cgi-tmp start 2>/dev/null || true

/etc/init.d/nginx reload 2>/dev/null || /etc/init.d/nginx restart 2>/dev/null || true
/etc/init.d/uwsgi restart 2>/dev/null || true

rm -rf /tmp/luci-*cache* 2>/dev/null || true
[ -x /sbin/luci-clear-cache ] && /sbin/luci-clear-cache 2>/dev/null || true

exit 0
