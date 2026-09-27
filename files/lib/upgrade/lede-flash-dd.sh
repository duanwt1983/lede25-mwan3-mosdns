# LEDE: log dd(1) lines during sysupgrade (included after common.sh).

LEDE_FW_LOG=/tmp/lede-fw-flash.log

get_image_dd() {
	local from="$1"
	shift

	v "LEDE dd 写盘开始"
	v "  源: $from"
	v "  参数: dd $*"
	{
		echo "=== dd start $(date -Is 2>/dev/null || date) ==="
		echo "from=$from"
		echo "dd $*"
	} >>"$LEDE_FW_LOG"

	(
		exec 3>&2
		( exec 3>&2; get_image "$from" 2>&1 1>&3 | grep -v -F ' Broken pipe' ) 2>&1 1>&3 \
			| ( exec 3>&2; dd "$@" 2>&1 | tee -a "$LEDE_FW_LOG" 1>&3 ) 2>&1 1>&3
		exec 3>&-
	)

	v "LEDE dd 写盘阶段结束"
	echo "=== dd end $(date -Is 2>/dev/null || date) ===" >>"$LEDE_FW_LOG"
}
