#!/bin/bash
# Copy this overlay to an Ubuntu 24 build host over SSH and start an offline build.
#
# Usage:
#   ./scripts/deploy-remote-build.sh user@192.168.x.x
#   ./scripts/deploy-remote-build.sh user@host --setup   # also run apt setup (needs sudo)
#   LEDE_WORK=/data/lede-build ./scripts/deploy-remote-build.sh user@host
#
# Requires: local rsync + sshpass + ssh; remote user can write REMOTE_DIR and LEDE_WORK.
# Password login example:
#   export SSHPASS='your-password'
#   sshpass -e rsync ...  (see rsync below)

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 user@host [--setup]" >&2
  exit 1
fi

SSH_TARGET="$1"
DO_SETUP=0
[ "${2:-}" = "--setup" ] && DO_SETUP=1

OVERLAY="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
REMOTE_DIR="${REMOTE_DIR:-/openwrt-build/overlay}"
LEDE_WORK="${LEDE_WORK:-/openwrt-build}"

RSYNC_EX=(
  --archive --delete --compress
  --exclude '.DS_Store'
  --exclude 'tmp-topo-pull'
  --exclude 'openwrt'
  --exclude '.git'
)

SSH_OPTS=(-o PubkeyAuthentication=no -o PreferredAuthentications=password -o StrictHostKeyChecking=no)
RSYNC_SSH="ssh ${SSH_OPTS[*]}"
if [ -n "${SSHPASS:-}" ]; then
  RSYNC_SSH="sshpass -e ssh ${SSH_OPTS[*]}"
fi

echo "Sync overlay -> ${SSH_TARGET}:${REMOTE_DIR}"
rsync -e "$RSYNC_SSH" "${RSYNC_EX[@]}" "$OVERLAY/" "${SSH_TARGET}:${REMOTE_DIR}/"

REMOTE_SCRIPT=$(cat <<EOF
set -eu
chmod +x ${REMOTE_DIR}/scripts/*.sh ${REMOTE_DIR}/diy-part*.sh 2>/dev/null || true
export LEDE_WORK=${LEDE_WORK}
export TZ=Asia/Shanghai
mkdir -p "\$LEDE_WORK"
EOF
)

if [ "$DO_SETUP" = 1 ]; then
  REMOTE_SCRIPT+=$(printf '\n%s\n' "sudo bash ${REMOTE_DIR}/scripts/setup-ubuntu24-build-host.sh")
fi

REMOTE_SCRIPT+=$(printf '\n%s\n' "bash ${REMOTE_DIR}/scripts/build-offline.sh")

echo "Starting remote build (log follows) ..."
if [ -n "${SSHPASS:-}" ]; then
  sshpass -e ssh -t "${SSH_OPTS[@]}" "$SSH_TARGET" "bash -s" <<< "$REMOTE_SCRIPT"
else
  ssh -t "${SSH_OPTS[@]}" "$SSH_TARGET" "bash -s" <<< "$REMOTE_SCRIPT"
fi
