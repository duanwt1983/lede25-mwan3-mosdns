#!/bin/bash
# Reclaim disk on the LEDE build host (e.g. 192.168.6.80) without removing the
# openwrt tree needed for incremental builds.
#
# Usage on build host:
#   LEDE_WORK=/openwrt-build bash /openwrt-build/overlay/scripts/cleanup-build-host.sh
#
# Options (env):
#   DRY_RUN=1          print actions only
#   KEEP_LOGS=3        keep newest N incremental-*.log (default 3)
#   KEEP_IMAGE_SETS=1  keep newest N firmware file groups under bin/targets (default 1)
#   AGGRESSIVE=1       also run: make dirclean (drops build_dir + staging_dir; dl/ kept)
#   PURGE_DL=1         delete entire openwrt/dl (next build re-downloads; not recommended)
#
# Does NOT delete: overlay/, openwrt/.git, openwrt/.config, openwrt/feeds (unless AGGRESSIVE).

set -euo pipefail

LEDE_WORK="${LEDE_WORK:-/openwrt-build}"
OWRT="$LEDE_WORK/openwrt"
DRY_RUN="${DRY_RUN:-0}"
KEEP_LOGS="${KEEP_LOGS:-3}"
KEEP_IMAGE_SETS="${KEEP_IMAGE_SETS:-1}"
AGGRESSIVE="${AGGRESSIVE:-0}"
PURGE_DL="${PURGE_DL:-0}"

run() {
	if [ "$DRY_RUN" = 1 ]; then
		echo "[dry-run] $*"
	else
		"$@"
	fi
}

human() {
	df -hT "$LEDE_WORK" 2>/dev/null | tail -1 || df -h "$LEDE_WORK" 2>/dev/null | tail -1 || true
}

if [ -f "$LEDE_WORK/build.pid" ]; then
	pid=$(cat "$LEDE_WORK/build.pid" 2>/dev/null || true)
	if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
		echo "ERROR: build still running (pid=$pid). Stop it before cleanup." >&2
		exit 1
	fi
fi
if [ -f "$LEDE_WORK/incremental.lock" ] && command -v flock >/dev/null 2>&1; then
	if flock -n "$LEDE_WORK/incremental.lock" true 2>/dev/null; then
		:
	else
		echo "ERROR: incremental.lock held — another build may be running." >&2
		exit 1
	fi
fi

echo "=== cleanup-build-host LEDE_WORK=$LEDE_WORK ==="
echo "Before: $(human)"

# Workdir logs (not openwrt)
if ls "$LEDE_WORK"/incremental-*.log >/dev/null 2>&1; then
	mapfile -t _logs < <(ls -1t "$LEDE_WORK"/incremental-*.log 2>/dev/null || true)
	for ((i = KEEP_LOGS; i < ${#_logs[@]}; i++)); do
		run rm -f "${_logs[$i]}"
	done
fi
run rm -f "$LEDE_WORK"/incremental-*.log.full 2>/dev/null || true
run rm -f "$LEDE_WORK/build.pid" 2>/dev/null || true

# Host temp from bandix host-build
run rm -rf /tmp/bandix-plus-patched-* 2>/dev/null || true

[ -d "$OWRT" ] || {
	echo "No $OWRT — nothing else to clean."
	echo "After: $(human)"
	exit 0
}

# OpenWrt ephemeral dirs
run rm -rf "$OWRT/tmp"/* "$OWRT/logs"/* 2>/dev/null || true
run rm -rf "$OWRT/dl/go-mod-cache" "$OWRT/tmp/go-build" 2>/dev/null || true
if [ "$PURGE_DL" = 1 ]; then
	run rm -rf "$OWRT/dl"
else
	while IFS= read -r f; do
		[ -n "$f" ] && run rm -f "$f"
	done < <(find "$OWRT/dl" -type f -size -1024c 2>/dev/null || true)
fi

# Old firmware outputs under bin/targets (keep newest KEEP_IMAGE_SETS sysupgrade images)
for target_dir in "$OWRT"/bin/targets/*/*; do
	[ -d "$target_dir" ] || continue
	keep_list=$(
		ls -1t "$target_dir"/*sysupgrade*.img* 2>/dev/null | head -n "$KEEP_IMAGE_SETS" || true
	)
	keep_prefixes=""
	while IFS= read -r kf; do
		[ -n "$kf" ] || continue
		base=$(basename "$kf")
		pfx=${base%%-sysupgrade*}
		keep_prefixes="$keep_prefixes $pfx"
	done <<<"$keep_list"
	for f in "$target_dir"/*; do
		[ -f "$f" ] || continue
		base=$(basename "$f")
		case "$base" in
			*-sysupgrade*.img* | *-combined*.img* | *.manifest | sha256sums | profiles.json | version.buildinfo | config.buildinfo)
				pfx=${base%%-sysupgrade*}
				[ "$pfx" = "$base" ] && pfx=${base%%-combined*}
				keep=0
				for kp in $keep_prefixes; do
					[ "$pfx" = "$kp" ] && keep=1 && break
				done
				[ "$keep" = 1 ] || run rm -f "$f"
				;;
		esac
	done
done

if [ "$AGGRESSIVE" = 1 ]; then
	echo "AGGRESSIVE: make dirclean (keeps dl/, .config, feeds)"
	if [ "$DRY_RUN" = 1 ]; then
		echo "[dry-run] (cd $OWRT && make dirclean)"
	else
		( cd "$OWRT" && make dirclean )
	fi
fi

echo "After: $(human)"
echo "Done. Next build: bash \$OVERLAY/scripts/build-incremental.sh"
