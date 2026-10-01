#!/bin/bash
# Deploy center portal to 6.251 (CentOS + Baota nginx).
# Usage: SSHPASS='…' ./scripts/deploy-center-portal-251.sh [root@192.168.6.251]

set -euo pipefail

TARGET="${1:-root@192.168.6.251}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
PORTAL="$ROOT/center-portal"
ENV_FILE="$ROOT/scripts/center-portal-251.env"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  export SSHPASS
fi

SSH_OPTS=(-o StrictHostKeyChecking=no)
RSYNC_SSH="ssh ${SSH_OPTS[*]}"
RUN=(ssh "${SSH_OPTS[@]}")
if [ -n "${SSHPASS:-}" ]; then
  RSYNC_SSH="sshpass -e ssh ${SSH_OPTS[*]}"
  RUN=(sshpass -e ssh "${SSH_OPTS[@]}")
fi

echo "Deploy portal -> $TARGET"
rsync -e "$RSYNC_SSH" --archive --delete \
  --exclude '.gitkeep' \
  --exclude 'scripts/' \
  --exclude 'nginx/' \
  --exclude 'sites.json' \
  --exclude 'api/status.json' \
  "$PORTAL/" "${TARGET}:/var/www/center-portal/"

rsync -e "$RSYNC_SSH" --archive \
  "$PORTAL/scripts/center-portal-status.sh" \
  "$PORTAL/scripts/center-portal-sync.sh" \
  "$PORTAL/scripts/center-portal-admin.py" \
  "$PORTAL/scripts/center-portal-admin.service" \
  "$PORTAL/scripts/center-portal-auth.lua" \
  "$PORTAL/scripts/center-portal-authelia-gate.lua" \
  "$PORTAL/scripts/center-portal-gw-enter.lua" \
  "$PORTAL/scripts/center-portal-gw-proxy.lua" \
  "$PORTAL/scripts/center-portal-gw-rewrite.lua" \
  "$PORTAL/scripts/center-portal-gw-handler.lua" \
  "$PORTAL/scripts/center-portal-frp-firewall.sh" \
  "${TARGET}:/tmp/center-portal-deploy/"

"${RUN[@]}" "$TARGET" 'bash -s' <<'REMOTE'
set -euo pipefail
mkdir -p /opt/center-portal /etc/nginx/lua /var/www/center-portal/api
install -m 0755 /tmp/center-portal-deploy/center-portal-status.sh /opt/center-portal/
install -m 0755 /tmp/center-portal-deploy/center-portal-frp-firewall.sh /opt/center-portal/
install -m 0755 /tmp/center-portal-deploy/center-portal-sync.sh /opt/center-portal/
install -m 0755 /tmp/center-portal-deploy/center-portal-admin.py /opt/center-portal/
install -m 0644 /tmp/center-portal-deploy/center-portal-auth.lua /etc/nginx/lua/
install -m 0644 /tmp/center-portal-deploy/center-portal-authelia-gate.lua /etc/nginx/lua/
install -m 0644 /tmp/center-portal-deploy/center-portal-gw-enter.lua /etc/nginx/lua/
install -m 0644 /tmp/center-portal-deploy/center-portal-gw-proxy.lua /etc/nginx/lua/
install -m 0644 /tmp/center-portal-deploy/center-portal-gw-rewrite.lua /etc/nginx/lua/
install -m 0644 /tmp/center-portal-deploy/center-portal-gw-handler.lua /etc/nginx/lua/
install -m 0644 /tmp/center-portal-deploy/center-portal-admin.service /etc/systemd/system/center-portal-admin.service
ln -sf /opt/center-portal/center-portal-status.sh /usr/local/bin/center-portal-status
ln -sf /opt/center-portal/center-portal-sync.sh /usr/local/bin/center-portal-sync
systemctl daemon-reload
systemctl enable center-portal-admin.service
systemctl restart center-portal-admin.service
/opt/center-portal/center-portal-frp-firewall.sh || true
/opt/center-portal/center-portal-status.sh
REMOTE

CENTER_SERVER_NAME="${CENTER_SERVER_NAME:-}"
CENTER_NGINX_VHOST="${CENTER_NGINX_VHOST:-}"

if [ -n "$CENTER_SERVER_NAME" ]; then
  echo "Install nginx vhost for ${CENTER_SERVER_NAME}"
  rsync -e "$RSYNC_SSH" --archive \
    "$PORTAL/nginx/center.example.com.conf" \
    "${TARGET}:/tmp/center-portal-deploy/center.example.com.conf"

  "${RUN[@]}" "$TARGET" "bash -s" <<REMOTE
set -euo pipefail
VHOST="\${CENTER_NGINX_VHOST:-/www/server/panel/vhost/nginx/${CENTER_SERVER_NAME}.conf}"
SRC=/tmp/center-portal-deploy/center.example.com.conf
sed "s/center.example.com/${CENTER_SERVER_NAME}/g" "\$SRC" >"\${SRC}.live"
install -m 0644 "\${SRC}.live" "\$VHOST"
rm -f /www/server/panel/vhost/nginx/center.example.com.conf
REMOTE
else
  echo "Skip nginx vhost (仓库模板为 center.example.com；生产请在 center-portal-251.env 设置 CENTER_SERVER_NAME)"
fi

"${RUN[@]}" "$TARGET" 'bash -s' <<'REMOTE'
set -euo pipefail
touch /www/server/panel/vhost/nginx/center-portal-gw.inc
/opt/center-portal/center-portal-sync.sh
CRON=/etc/cron.d/center-portal
if [ ! -f "$CRON" ]; then
  echo '* * * * * root /opt/center-portal/center-portal-status.sh >/dev/null 2>&1' > "$CRON"
  chmod 644 "$CRON"
fi
REMOTE

echo "Done. Open https://${CENTER_SERVER_NAME:-center.example.com}:18443/home/"
