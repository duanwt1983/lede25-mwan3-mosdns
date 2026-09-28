#!/bin/bash
# Incremental firmware build: reuse LEDE_WORK/openwrt (no re-clone / no download).
# Usage on build host:
#   LEDE_WORK=/openwrt-build OVERLAY=$LEDE_WORK/overlay ./scripts/build-incremental.sh
set -euo pipefail

LEDE_WORK="${LEDE_WORK:-/openwrt-build}"
OVERLAY="${OVERLAY:-$LEDE_WORK/overlay}"
LEDE_JOBS="${LEDE_JOBS:-$(nproc)}"
export TZ="${TZ:-Asia/Shanghai}"
LOCK_FILE="${LEDE_WORK}/incremental.lock"

mkdir -p "$LEDE_WORK"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "ERROR: another incremental build holds $LOCK_FILE (see build.pid / incremental-*.log)" >&2
  exit 1
fi

[ -d "$LEDE_WORK/openwrt/.git" ] || { echo "Missing $LEDE_WORK/openwrt — run full build-offline first" >&2; exit 1; }
[ -f "$OVERLAY/diy-part2.sh" ] || { echo "Missing overlay at $OVERLAY" >&2; exit 1; }

cd "$LEDE_WORK/openwrt"
echo "=== incremental $(date -Is) jobs=$LEDE_JOBS ==="

rm -rf files && cp -a "$OVERLAY/files" files
cp "$OVERLAY/.config" .config
bash "$OVERLAY/diy-part2.sh"

make defconfig
bash "$OVERLAY/scripts/after-defconfig.sh"
bash "$OVERLAY/scripts/audit-config.sh"

if ! make -j"$LEDE_JOBS"; then
  echo "Parallel make failed, retry -j1 ..."
  make -j1
fi

echo "=== done $(date -Is) ==="
dest=$(echo bin/targets/*/*)
ls -lh "$dest"
mf=$(ls -1 "$dest"/*.manifest 2>/dev/null | head -1 || true)
[ -n "$mf" ] && grep -E 'luci-mod-system|samba4|mosdns|mwan3' "$mf" | head -20 || true
