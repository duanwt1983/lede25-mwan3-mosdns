#!/bin/sh
# After center-hub component pack: refresh LuCI, merge new UCI keys, re-apply frpc + portal register.
export PATH=/usr/sbin:/sbin:/usr/bin:/bin

chmod 755 /usr/libexec/lede-center-frpc 2>/dev/null || true
if [ -f /etc/nginx/conf.d/20-lede-ttyd.conf ]; then
	if [ ! -f /etc/nginx/conf.d/20-lede-ttyd.locations ]; then
		mv /etc/nginx/conf.d/20-lede-ttyd.conf /etc/nginx/conf.d/20-lede-ttyd.locations
	else
		rm -f /etc/nginx/conf.d/20-lede-ttyd.conf
	fi
fi
if [ -f /etc/nginx/conf.d/20-lede-ttyd.locations ]; then
	nginx -t -c /etc/nginx/uci.conf >>/tmp/lede-component-apply.log 2>&1 \
		&& /etc/init.d/nginx restart >>/tmp/lede-component-apply.log 2>&1 || true
fi
/etc/init.d/ttyd enabled 2>/dev/null && /etc/init.d/ttyd start >>/tmp/lede-component-apply.log 2>&1 || true
rm -rf /tmp/luci-*cache* 2>/dev/null || true
[ -x /sbin/luci-clear-cache ] && /sbin/luci-clear-cache 2>/dev/null || true

if uci -q get lede-center.main >/dev/null 2>&1; then
	uci -q get lede-center.main.display_name >/dev/null 2>&1 || uci set lede-center.main.display_name=''
	uci -q get lede-center.main.region >/dev/null 2>&1 || uci set lede-center.main.region=''
	uci -q get lede-center.main.portal_lan_host >/dev/null 2>&1 || uci set lede-center.main.portal_lan_host=''
	uci commit lede-center 2>/dev/null || true
fi

if [ -x /usr/libexec/lede-center-frpc ] && [ "$(uci -q get lede-center.main.enabled 2>/dev/null)" = "1" ]; then
	/usr/libexec/lede-center-frpc write-config >>/tmp/lede-component-apply.log 2>&1 || true
	/etc/init.d/lede-center-frpc restart >>/tmp/lede-component-apply.log 2>&1 || true
	( sleep 8
	  i=0
	  while [ "$i" -lt 3 ]; do
		if /usr/libexec/lede-center-frpc register-portal >>/tmp/lede-component-apply.log 2>&1 \
			&& grep -q 'portal register ok:' /tmp/lede-component-apply.log 2>/dev/null; then
			break
		fi
		i=$((i + 1))
		sleep 5
	  done
	) &
fi
exit 0
