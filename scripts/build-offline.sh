#!/bin/bash
# Offline build on Ubuntu 24 — same steps as .github/workflows/build-lede.yml.
# All patches under patches/ are applied inside diy-part2.sh (plus files/ overlay).
#
# Usage (on the build host, after setup-ubuntu24-build-host.sh):
#   export LEDE_WORK=/workdir/lede-build   # large disk, 80+ GiB free
#   ./scripts/build-offline.sh
#
# Optional env:
#   REPO_URL      default https://github.com/coolsnowwolf/lede
#   REPO_BRANCH   default master
#   LEDE_JOBS     default nproc
#   SKIP_DOWNLOAD set to 1 to reuse dl/
#   SKIP_CLONE    set to 1 if openwrt/ already exists under LEDE_WORK

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/coolsnowwolf/lede}"
REPO_BRANCH="${REPO_BRANCH:-master}"
LEDE_JOBS="${LEDE_JOBS:-$(nproc)}"
LEDE_WORK="${LEDE_WORK:-$HOME/lede-build}"
TZ="${TZ:-Asia/Shanghai}"
export TZ

OVERLAY="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
DIY_P1="$OVERLAY/diy-part1.sh"
DIY_P2="$OVERLAY/diy-part2.sh"
CONFIG_FILE="$OVERLAY/.config"
FEEDS_CONF="$OVERLAY/feeds.conf.default"

for f in "$DIY_P1" "$DIY_P2" "$CONFIG_FILE"; do
  [ -f "$f" ] || { echo "Missing $f (sync full overlay repo first)" >&2; exit 1; }
done
chmod +x "$DIY_P1" "$DIY_P2" "$OVERLAY/scripts/"*.sh 2>/dev/null || true

mkdir -p "$LEDE_WORK"
cd "$LEDE_WORK"

if [ "${SKIP_CLONE:-0}" != 1 ]; then
  rm -rf openwrt
  echo "Cloning $REPO_URL ($REPO_BRANCH) into $LEDE_WORK/openwrt ..."
  git clone --depth=1 "$REPO_URL" -b "$REPO_BRANCH" openwrt
fi
[ -d openwrt/.git ] || { echo "No openwrt tree in $LEDE_WORK/openwrt" >&2; exit 1; }

if [ -f "$FEEDS_CONF" ]; then
  cp "$FEEDS_CONF" openwrt/feeds.conf.default
fi

echo "=== diy-part1 (feeds.conf / PassWall sources) ==="
( cd openwrt && "$DIY_P1" )

echo "=== feeds update -a ==="
( cd openwrt && ./scripts/feeds update -a )

echo "=== feeds install -a ==="
( cd openwrt && ./scripts/feeds install -a )

echo "=== overlay: files/ + .config + diy-part2 (all patches) ==="
rm -rf openwrt/files
cp -a "$OVERLAY/files" openwrt/files
cp "$CONFIG_FILE" openwrt/.config
( cd openwrt && "$DIY_P2" )

echo "=== defconfig + after-defconfig + audit ==="
(
  cd openwrt
  make defconfig
  "$OVERLAY/scripts/after-defconfig.sh"
  "$OVERLAY/scripts/audit-config.sh"
)

if [ "${SKIP_DOWNLOAD:-0}" != 1 ]; then
  echo "=== make download ==="
  (
    cd openwrt
    rm -rf dl/go-mod-cache tmp/go-build
    timeout 25m make download -j8 || timeout 10m make download -j1
    find dl -size -1024c -exec rm -f {} \;
  )
fi

if ! command -v qemu-img >/dev/null 2>&1; then
  echo "qemu-img required for VMDK images; install qemu-utils" >&2
  exit 1
fi

dump_fail_logs() {
  cd openwrt
  echo "===== df ====="
  df -hT || true
  grep -R "ERROR:\|Error 1\|Cannot satisfy\|Collected errors\|No space" logs tmp 2>/dev/null | tail -n 120 || true
}

echo "=== host golang (diy-part2 picks sbwml branch) ==="
(
  cd openwrt
  rm -rf dl/go-mod-cache tmp/go-build
  make -j1 package/feeds/packages/golang/host/compile
  staging_dir/hostpkg/bin/go version 2>/dev/null || staging_dir/host/bin/go version
)

echo "=== make -j$LEDE_JOBS ==="
if ! ( cd openwrt && make -j"$LEDE_JOBS" ); then
  echo "Parallel make failed, retry -j1 ..."
  if ! ( cd openwrt && make -j1 ); then
    dump_fail_logs
    exit 1
  fi
fi

echo "=== firmware output ==="
dest=$(echo openwrt/bin/targets/*/*)
cd "$LEDE_WORK/$dest"
ls -lh
mf=$(ls -1 *.manifest 2>/dev/null | head -1 || true)
if [ -n "$mf" ]; then
  echo "==== manifest (disk / ixgbe / tools) ===="
  grep -E 'luci-app-diskman|parted|sgdisk|kmod-ixgbe|mosdns|mwan3|passwall' "$mf" || true
fi
echo "Done. Images: $LEDE_WORK/$dest"
