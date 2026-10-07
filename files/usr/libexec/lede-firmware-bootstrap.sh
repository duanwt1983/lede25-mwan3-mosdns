#!/bin/sh
# Idempotent prep for lede-firmware-* on diverse images (manual component install, old overlay).
# Safe to run from post-apply, upload-env, upload-check, or SSH before upgrading firmware.
set -u
export PATH=/usr/sbin:/sbin:/usr/bin:/bin

LOG=/tmp/lede-firmware-bootstrap.log
STAGE_NGINX=/www/luci-static/resources/lede-firmware/nginx-luci.locations
STAGE_UWSGI=/www/luci-static/resources/lede-firmware/uwsgi-luci-cgi_io.ini

log() {
	printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG" >&2
}

data_usable() {
	if grep -q ' /data ' /proc/mounts 2>/dev/null; then
		return 0
	fi
	[ -d /data ] && [ -w /data ] 2>/dev/null
}

ensure_data() {
	mkdir -p /data
	if data_usable; then
		return 0
	fi

	if [ -x /etc/init.d/lede-data-mount ]; then
		/etc/init.d/lede-data-mount enable 2>/dev/null || true
		/etc/init.d/lede-data-mount start 2>/dev/null || true
	fi
	if [ -x /usr/libexec/lede-data-mount ]; then
		/usr/libexec/lede-data-mount mount 2>>"$LOG" || true
	fi
	if [ -x /etc/init.d/fstab ]; then
		/etc/init.d/fstab enable 2>/dev/null || true
		/etc/init.d/fstab start 2>>"$LOG" || true
	fi
	block mount 2>>"$LOG" || true

	if data_usable; then
		log "OK /data ready"
		return 0
	fi

	mkdir -p /data
	if [ -w /data ]; then
		log "WARN /data is not a separate mount; large images need LEDEDATA + fstab (see lede-data-setup)"
		return 0
	fi

	log "FAIL /data not mounted and not writable"
	return 1
}

nginx_body_unlimited() {
	local f
	for f in /etc/nginx/uci.conf /etc/nginx/uci.conf.template /etc/nginx/nginx.conf; do
		[ -f "$f" ] || continue
		if grep -q 'client_max_body_size' "$f" 2>/dev/null; then
			sed -i 's/client_max_body_size[^;]*;/client_max_body_size 0;/g' "$f"
		else
			sed -i '/http {/a\        client_max_body_size 0;' "$f" 2>/dev/null || true
		fi
	done
}

web_stack() {
	nginx_body_unlimited
	# Emperor watches vassals/*.ini — cp triggers reload and kills multi-GB cgi-upload.
	if upload_session_active || [ "$mode" = "quick" ]; then
		log "skip nginx/uwsgi template copy (mode=$mode, upload_active=$(upload_session_active && echo yes || echo no))"
		return 0
	fi
	if [ -f "$STAGE_NGINX" ]; then
		mkdir -p /etc/nginx/conf.d
		cmp -s "$STAGE_NGINX" /etc/nginx/conf.d/luci.locations 2>/dev/null || \
			cp -f "$STAGE_NGINX" /etc/nginx/conf.d/luci.locations
	fi
	if [ -f "$STAGE_UWSGI" ]; then
		mkdir -p /etc/uwsgi/vassals
		cmp -s "$STAGE_UWSGI" /etc/uwsgi/vassals/luci-cgi_io.ini 2>/dev/null || \
			cp -f "$STAGE_UWSGI" /etc/uwsgi/vassals/luci-cgi_io.ini
	fi
}

run_uci_defaults() {
	local s f
	for s in 45-nginx-firmware-upload 47-lede-firmware-upload-boot; do
		f="/etc/uci-defaults/$s"
		[ -f "$f" ] || continue
		sh "$f" >>"$LOG" 2>&1 || true
	done
}

upload_session_active() {
	[ -f /var/run/lede-fw-upload-active ]
}

reload_web() {
	/etc/init.d/lede-cgi-tmp disable 2>/dev/null || true
	if upload_session_active; then
		log "skip uwsgi/nginx reload (firmware upload in progress)"
		return 0
	fi
	if [ "$mode" = "quick" ]; then
		log "quick mode: skip uwsgi restart (avoid breaking cgi-upload)"
		return 0
	fi
	[ -x /etc/init.d/uwsgi ] && /etc/init.d/uwsgi restart >>"$LOG" 2>&1 || true
	if [ -x /etc/init.d/nginx ]; then
		/etc/init.d/nginx reload >>"$LOG" 2>&1 || \
			/etc/init.d/nginx restart >>"$LOG" 2>&1 || true
	fi
}

rpcd_acl_reload() {
	local acl=/usr/share/rpcd/acl.d/zzz-lede-flash-acl.json
	local sum marker
	[ -f "$acl" ] || return 0
	sum=$(md5sum "$acl" 2>/dev/null | awk '{print $1}')
	[ -n "$sum" ] || sum=1
	marker="/var/run/lede-flash-acl-$sum"
	[ -f "$marker" ] && return 0
	[ -x /etc/init.d/rpcd ] || return 0
	log "reload rpcd (flash ACL $sum)"
	/etc/init.d/rpcd restart >>"$LOG" 2>&1 || true
	touch "$marker"
}

upgrade_hooks() {
	[ -x /usr/libexec/lede-firmware-restore-upgrade.sh ] && \
		/usr/libexec/lede-firmware-restore-upgrade.sh || true
	[ -f /lib/upgrade/lede-flash-dd.sh ] || \
		log "WARN missing /lib/upgrade/lede-flash-dd.sh (reinstall firmware-upgrade pack)"
}

mode=${1:-full}

main() {
	log "begin bootstrap mode=$mode"
	ensure_data || exit 1
	upgrade_hooks
	[ -x /usr/libexec/lede-firmware-upload-sanity.sh ] && \
		/usr/libexec/lede-firmware-upload-sanity.sh boot >>"$LOG" 2>&1 || true
	mkdir -p /dat
	web_stack
	if [ "$mode" = "full" ] && ! upload_session_active; then
		run_uci_defaults
	else
		log "skip uci-defaults web restart (mode=$mode)"
	fi
	reload_web
	if [ "$mode" = "full" ]; then
		rpcd_acl_reload
	fi
	rm -rf /tmp/luci-*cache* 2>/dev/null || true
	[ -x /sbin/luci-clear-cache ] && /sbin/luci-clear-cache >>"$LOG" 2>&1 || true
	log "bootstrap done"
	exit 0
}

main "$@"
