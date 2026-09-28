#!/bin/bash
# Sync overlay to build host and start incremental make in background (no log follow).
#
# Usage:
#   export SSHPASS='your-password'
#   ./scripts/trigger-remote-incremental.sh user@192.168.6.80
#
# Env:
#   LEDE_WORK     default /openwrt-build
#   REMOTE_DIR    default /openwrt-build/overlay
#   FULL=1        run build-offline.sh instead (no existing openwrt tree)

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: SSHPASS=… $0 user@192.168.6.80" >&2
  exit 1
fi

SSH_TARGET="$1"
OVERLAY="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
REMOTE_DIR="${REMOTE_DIR:-/openwrt-build/overlay}"
LEDE_WORK="${LEDE_WORK:-/openwrt-build}"
LOG="$LEDE_WORK/incremental-$(date +%Y%m%d-%H%M%S).log"
BUILD="${FULL:-0}"

SSH_OPTS=(-o PubkeyAuthentication=no -o PreferredAuthentications=password -o StrictHostKeyChecking=no)
RSYNC_SSH="ssh ${SSH_OPTS[*]}"
RUN_SSH=(ssh "${SSH_OPTS[@]}")
if [ -n "${SSHPASS:-}" ]; then
  RSYNC_SSH="sshpass -e ssh ${SSH_OPTS[*]}"
  RUN_SSH=(sshpass -e ssh "${SSH_OPTS[@]}")
fi

echo "Sync overlay -> ${SSH_TARGET}:${REMOTE_DIR}"
rsync -e "$RSYNC_SSH" --archive --delete --compress \
  --exclude '.DS_Store' --exclude 'tmp-topo-pull' --exclude 'openwrt' --exclude '.git' --exclude 'dist' \
  "$OVERLAY/" "${SSH_TARGET}:${REMOTE_DIR}/"

REMOTE=$(cat <<EOF
set -eu
export LEDE_WORK=${LEDE_WORK}
export OVERLAY=${REMOTE_DIR}
export TZ=Asia/Shanghai
chmod +x "\$OVERLAY/scripts/"*.sh "\$OVERLAY/diy-part"*.sh 2>/dev/null || true
mkdir -p "\$LEDE_WORK"
if [ -f "\$LEDE_WORK/build.pid" ]; then
  old=\$(cat "\$LEDE_WORK/build.pid" 2>/dev/null || true)
  if [ -n "\$old" ] && kill -0 "\$old" 2>/dev/null; then
    echo "Stopping previous build pid=\$old (avoid parallel make on same tree)"
    kill -TERM "\$old" 2>/dev/null || true
    sleep 3
    kill -KILL "\$old" 2>/dev/null || true
  fi
fi
if [ "${BUILD}" = 1 ] || [ ! -d "\$LEDE_WORK/openwrt/.git" ]; then
  echo "Starting FULL build-offline in background -> ${LOG}.full"
  nohup bash "\$OVERLAY/scripts/build-offline.sh" > "${LOG}.full" 2>&1 &
else
  echo "Starting INCREMENTAL build in background -> ${LOG}"
  nohup bash "\$OVERLAY/scripts/build-incremental.sh" > "${LOG}" 2>&1 &
fi
echo \$! > "\$LEDE_WORK/build.pid"
echo "pid=\$(cat \$LEDE_WORK/build.pid)"
echo "tail -f ${LOG}   # on build host"
EOF
)

"${RUN_SSH[@]}" "$SSH_TARGET" "bash -s" <<< "$REMOTE"

echo ""
echo "Remote build started. On ${SSH_TARGET}:"
echo "  tail -f ${LOG}"
echo "  ls -lh ${LEDE_WORK}/openwrt/bin/targets/x86/64/   # when done"
