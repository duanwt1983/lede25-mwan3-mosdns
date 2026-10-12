#!/bin/bash
# Idempotent: expose POST /home/api/gateway/register on the portal vhost (no Authelia).
set -euo pipefail

VHOST="${1:-${CENTER_NGINX_VHOST:-}}"
if [ -z "$VHOST" ]; then
  for c in /www/server/panel/vhost/nginx/center.123.gd.cn.conf \
    /www/server/panel/vhost/nginx/center.example.com.conf; do
    [ -f "$c" ] && VHOST="$c" && break
  done
fi
[ -n "$VHOST" ] && [ -f "$VHOST" ] || {
  echo "skip gateway/register nginx patch (no vhost)" >&2
  exit 0
}

if grep -q 'gateway/register' "$VHOST" 2>/dev/null; then
  echo "gateway/register already in $VHOST"
  exit 0
fi

MARKER='location /home/api/admin/'
if ! grep -q "$MARKER" "$VHOST"; then
  echo "WARN: $MARKER not found in $VHOST — add gateway/register block manually" >&2
  exit 0
fi

SNIP='    location = /home/api/gateway/register {
        proxy_pass http://127.0.0.1:8765/gateway/register;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header Authorization $http_authorization;
        proxy_set_header X-Lede-Token $http_x_lede_token;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        add_header Cache-Control "no-store";
    }

'
tmp="${VHOST}.gwreg.$$"
awk -v snip="$SNIP" -v mark="$MARKER" '
  index($0, mark) && !done { printf "%s", snip; done=1 }
  { print }
' "$VHOST" >"$tmp"
install -m 0644 "$tmp" "$VHOST"
rm -f "$tmp"
nginx -t 2>/dev/null && nginx -s reload 2>/dev/null || /etc/init.d/nginx reload 2>/dev/null || true
echo "patched gateway/register in $VHOST"
