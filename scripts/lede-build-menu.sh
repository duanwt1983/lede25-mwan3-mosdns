#!/bin/bash
# LEDE 编译机统一菜单（增量 / 全量 / 清理）
# 建议安装路径：/openwrt-build/lede-build-menu.sh
#
# 环境变量（可选）：
#   LEDE_WORK=/openwrt-build
#   OVERLAY=$LEDE_WORK/overlay

set -euo pipefail

LEDE_WORK="${LEDE_WORK:-/openwrt-build}"
OVERLAY="${OVERLAY:-$LEDE_WORK/overlay}"
export TZ="${TZ:-Asia/Shanghai}"
export LEDE_WORK OVERLAY

SCRIPTS="$OVERLAY/scripts"
INCR="$SCRIPTS/build-incremental.sh"
FULL="$SCRIPTS/build-offline.sh"
CLEAN="$SCRIPTS/cleanup-build-host.sh"

die() { echo "错误: $*" >&2; exit 1; }

check_overlay() {
	[ -f "$OVERLAY/diy-part2.sh" ] || die "未找到 overlay：$OVERLAY（请先 rsync 同步 overlay）"
	[ -x "$INCR" ] || [ -f "$INCR" ] || die "缺少 $INCR"
	[ -f "$FULL" ] || die "缺少 $FULL"
	[ -f "$CLEAN" ] || die "缺少 $CLEAN"
	chmod +x "$INCR" "$FULL" "$CLEAN" 2>/dev/null || true
}

build_running() {
	if [ -f "$LEDE_WORK/build.pid" ]; then
		local pid
		pid=$(cat "$LEDE_WORK/build.pid" 2>/dev/null || true)
		if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
			return 0
		fi
	fi
	if [ -f "$LEDE_WORK/incremental.lock" ] && command -v flock >/dev/null 2>&1; then
		if ! flock -n "$LEDE_WORK/incremental.lock" true 2>/dev/null; then
			return 0
		fi
	fi
	return 1
}

stop_build_prompt() {
	if ! build_running; then
		return 0
	fi
	local pid
	pid=$(cat "$LEDE_WORK/build.pid" 2>/dev/null || true)
	echo "检测到编译进程仍在运行（pid=${pid:-未知}）。"
	read -r -p "是否终止并开始新任务？[y/N] " ans
	case "${ans:-N}" in
		y|Y|yes|YES)
			[ -n "${pid:-}" ] && kill -TERM "$pid" 2>/dev/null || true
			sleep 2
			[ -n "${pid:-}" ] && kill -KILL "$pid" 2>/dev/null || true
			rm -f "$LEDE_WORK/build.pid"
			;;
		*)
			die "已取消（请勿并行 make 同一棵树）"
			;;
	esac
}

run_build_bg() {
	local title=$1 log=$2 script=$3
	echo ""
	echo "======== $title ========"
	echo "日志: $log"
	echo "开始: $(date '+%F %T')"
	mkdir -p "$LEDE_WORK"
	stop_build_prompt
	: >"$log"
	nohup env LEDE_WORK="$LEDE_WORK" OVERLAY="$OVERLAY" bash "$script" >>"$log" 2>&1 &
	echo $! >"$LEDE_WORK/build.pid"
	echo "已在后台启动，pid=$(cat "$LEDE_WORK/build.pid")"
	echo "查看进度: tail -f $log"
}

do_incremental() {
	check_overlay
	local log="$LEDE_WORK/incremental-$(date +%Y%m%d-%H%M%S).log"
	run_build_bg "增量编译" "$log" "$INCR"
}

do_full() {
	check_overlay
	echo ""
	echo "全量编译将删除并重新 clone openwrt（耗时最长）。"
	echo "若仅需释放磁盘，请用菜单「清理」而非全量。"
	read -r -p "确认开始全量编译？[y/N] " ans
	case "${ans:-N}" in
		y|Y|yes|YES) ;;
		*) echo "已取消。"; return 0 ;;
	esac
	local log="$LEDE_WORK/incremental-$(date +%Y%m%d-%H%M%S).log.full"
	run_build_bg "全量编译" "$log" "$FULL"
}

do_cleanup() {
	check_overlay
	echo ""
	echo "清理选项："
	echo "  1. 常规清理（日志、tmp、旧镜像，保留 build_dir）"
	echo "  2. 深度清理（常规 + make dirclean，下次增量会重编所有包，保留 dl/）"
	read -r -p "请选择 [1/2，默认 1]: " mode
	local extra=""
	case "${mode:-1}" in
		2) extra="AGGRESSIVE=1" ;;
		*) extra="" ;;
	esac
	if build_running; then
		die "编译进行中，请先停止编译再清理"
	fi
	echo ""
	echo "======== 清理垃圾文件 ========"
	# shellcheck disable=SC2086
	env $extra LEDE_WORK="$LEDE_WORK" bash "$CLEAN"
	echo "完成: $(date '+%F %T')"
}

show_status() {
	echo ""
	echo "======== 状态 ========"
	df -hT "$LEDE_WORK" 2>/dev/null | tail -1 || df -h "$LEDE_WORK" | tail -1
	if [ -d "$LEDE_WORK/openwrt" ]; then
		du -sh "$LEDE_WORK/openwrt" "$LEDE_WORK/openwrt/dl" "$LEDE_WORK/openwrt/build_dir" 2>/dev/null || true
		dest=$(echo "$LEDE_WORK/openwrt/bin/targets/"*/* 2>/dev/null | head -1)
		if [ -d "$dest" ]; then
			echo "固件目录: $dest"
			ls -lh "$dest"/*sysupgrade*.img* 2>/dev/null | tail -3 || echo "（暂无 sysupgrade 镜像）"
		fi
	else
		echo "openwrt 树: 不存在（需全量或首次 build-offline）"
	fi
	if build_running; then
		echo "编译: 运行中 pid=$(cat "$LEDE_WORK/build.pid" 2>/dev/null)"
		local latest
		latest=$(ls -1t "$LEDE_WORK"/incremental-*.log 2>/dev/null | head -1 || true)
		[ -n "$latest" ] && echo "最近日志: $latest"
	else
		echo "编译: 空闲"
	fi
	echo ""
}

pause() {
	read -r -p "按回车返回菜单…" _
}

main_menu() {
	while true; do
		clear 2>/dev/null || true
		echo "=============================================="
		echo "   LEDE 编译机菜单  ($LEDE_WORK)"
		echo "   overlay: $OVERLAY"
		echo "=============================================="
		echo "  1. 增量编译（日常推荐，保留 openwrt + dl）"
		echo "  2. 全量编译（删树重 clone，首编或大版本升级）"
		echo "  3. 一键清理垃圾文件"
		echo "  4. 查看磁盘 / 编译状态"
		echo "  0. 退出"
		echo "----------------------------------------------"
		read -r -p "请输入选项 [0-4]: " choice
		case "${choice:-}" in
			1) do_incremental; pause ;;
			2) do_full; pause ;;
			3) do_cleanup; pause ;;
			4) show_status; pause ;;
			0|q|Q) echo "再见。"; exit 0 ;;
			*) echo "无效选项"; sleep 1 ;;
		esac
	done
}

check_overlay
main_menu
