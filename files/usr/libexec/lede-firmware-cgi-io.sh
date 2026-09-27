#!/bin/sh
# Patch /usr/libexec/cgi-io temp path between /tmp (default) and /dat (large upload).
export PATH=/usr/sbin:/sbin:/usr/bin:/bin

LEDE_FW_UPLOAD_ACTIVE=/var/run/lede-fw-upload-active

lede_cgi_io_patched_dat() {
	strings /usr/libexec/cgi-io 2>/dev/null | grep -qx '/dat'
}

lede_cgi_io_patched_tmp() {
	strings /usr/libexec/cgi-io 2>/dev/null | grep -qx '/tmp'
}

_lede_cgi_io_grep_off() {
	# BusyBox grep needs -a for binary; -abo alone often finds nothing on cgi-io.
	grep -a -bo "$1" "$2" 2>/dev/null | cut -d: -f1
}

lede_cgi_io_patch_dat() {
	local bin=/usr/libexec/cgi-io off cur
	[ -f "$bin" ] || return 0
	lede_cgi_io_patched_dat && return 0
	for off in $(_lede_cgi_io_grep_off '/tmp' "$bin"); do
		cur=$(dd if="$bin" bs=1 skip="$off" count=4 2>/dev/null || true)
		if [ "$cur" = "/tmp" ]; then
			printf '/dat' | dd of="$bin" bs=1 seek="$off" conv=notrunc 2>/dev/null || true
			return 0
		fi
	done
	cur=$(dd if="$bin" bs=1 skip=17084 count=4 2>/dev/null || true)
	if [ "$cur" = "/tmp" ]; then
		printf '/dat' | dd of="$bin" bs=1 seek=17084 conv=notrunc 2>/dev/null || true
	fi
}

lede_cgi_io_revert_tmp() {
	local bin=/usr/libexec/cgi-io off cur patched=0
	[ -f "$bin" ] || return 0
	lede_cgi_io_patched_tmp && return 0
	for off in $(_lede_cgi_io_grep_off '/dat' "$bin"); do
		cur=$(dd if="$bin" bs=1 skip="$off" count=4 2>/dev/null || true)
		if [ "$cur" = "/dat" ]; then
			printf '/tmp' | dd of="$bin" bs=1 seek="$off" conv=notrunc 2>/dev/null || true
			patched=1
		fi
	done
	if [ "$patched" = 0 ]; then
		cur=$(dd if="$bin" bs=1 skip=17084 count=4 2>/dev/null || true)
		if [ "$cur" = "/dat" ]; then
			printf '/tmp' | dd of="$bin" bs=1 seek=17084 conv=notrunc 2>/dev/null || true
		fi
	fi
}
