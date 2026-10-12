#!/bin/sh
# Recover LuCI when 20-lede-ttyd.conf broke nginx (1.0.4 center-hub). Run on the gateway (SSH/LAN).
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
if [ -f /etc/nginx/conf.d/20-lede-ttyd.conf ]; then
	if [ ! -f /etc/nginx/conf.d/20-lede-ttyd.locations ]; then
		mv /etc/nginx/conf.d/20-lede-ttyd.conf /etc/nginx/conf.d/20-lede-ttyd.locations
	else
		rm -f /etc/nginx/conf.d/20-lede-ttyd.conf
	fi
fi
nginx -t -c /etc/nginx/uci.conf && /etc/init.d/nginx restart
curl -fsSk -o /dev/null -w 'https_local=%{http_code}\n' https://127.0.0.1/ || true
