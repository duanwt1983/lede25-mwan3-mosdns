#!/bin/bash
# Write frps dashboard snapshot + tunnel reachability hints for the portal (run on 6.251).
set -euo pipefail

OUT="${1:-/var/www/center-portal/api/status.json}"
TMP="${OUT}.tmp"
API="http://127.0.0.1:7400"
SITES="${SITES_JSON:-/var/www/center-portal/sites.json}"

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

server="$(curl -sf --max-time 5 "${API}/api/serverinfo" || echo '{}')"
tcp="$(curl -sf --max-time 5 "${API}/api/proxy/tcp" || echo '{"proxies":[]}')"
updated="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

tunnel_checks='[]'
if [ -f "$SITES" ]; then
  tunnel_checks="$(jq -c '
    .sites[]? | . as $s | (.tunnels // [])[]? | {
      site_id: $s.id,
      name: .name,
      port: .port,
      local: (.local // "")
    }
  ' "$SITES" | while read -r row; do
    port="$(echo "$row" | jq -r '.port')"
    sid="$(echo "$row" | jq -r '.site_id')"
    tname="$(echo "$row" | jq -r '.name')"
    local="$(echo "$row" | jq -r '.local // ""')"
    pname="${sid}-${tname}"
    online="$(echo "$tcp" | jq -r --arg n "$pname" '.proxies[]? | select(.name==$n) | .status' 2>/dev/null | head -1)"
    [ -n "$online" ] || online="offline"
    frp_local="$(echo "$tcp" | jq -r --arg n "$pname" '.proxies[]? | select(.name==$n) | .conf.localIP' 2>/dev/null | head -1)"
    frp_lport="$(echo "$tcp" | jq -r --arg n "$pname" '.proxies[]? | select(.name==$n) | .conf.localPort // empty' 2>/dev/null | head -1)"
    frp_target=""
    if [ -n "$frp_local" ]; then
      if [ -n "$frp_lport" ] && [ "$frp_lport" != "null" ]; then
        frp_target="${frp_local}:${frp_lport}"
      else
        frp_target="$frp_local"
      fi
    fi
    hint=""
    level="ok"
    lan_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
    hdr="$(curl -sfI --max-time 3 "http://127.0.0.1:${port}/" 2>/dev/null || true)"
    code="$(printf '%s' "$hdr" | awk '/^HTTP/{print $2; exit}')"
    lan_code=""
    if [ -n "$lan_ip" ] && [ "$lan_ip" != "127.0.0.1" ]; then
      lan_hdr="$(curl -sfI --max-time 3 "http://${lan_ip}:${port}/" 2>/dev/null || true)"
      lan_code="$(printf '%s' "$lan_hdr" | awk '/^HTTP/{print $2; exit}')"
    fi
    srv="$(printf '%s' "$hdr" | awk -F': ' 'tolower($1)=="server"{print $2; exit}')"
    if [ "$online" != "online" ]; then
      hint="frp 离线：请在门店网关保存并应用区域接入中心"
      level="bad"
    elif [ "$frp_local" = "192.168.6.251" ]; then
      hint="内网 IP 指回中心 6.251，请在 9.1 隧道改为门店 LAN 或测试目标 IP"
      level="bad"
    elif [ "$code" = "400" ] && [ "${srv#nginx}" != "$srv" ]; then
      hint="连到中心 Nginx/宝塔，非门店设备：请改网关隧道内网 IP/端口"
      level="bad"
    elif [ -n "$code" ] && [ -z "$lan_code" ] && [ -n "$lan_ip" ]; then
      hint="本机 127.0.0.1 可连但 ${lan_ip}:${port} 不通：请在中心机 firewalld 放行 19100–19999/tcp（deploy 会执行 center-portal-frp-firewall.sh）"
      level="bad"
    elif [ -z "$code" ]; then
      hint="中心 ${port} 无 HTTP 响应（非 Web 服务可忽略；外网仍须 WAN 转发）"
      level="warn"
    else
      hint="中心机探测正常；内网用 http://${lan_ip:-192.168.6.251}:${port}/；外网须在入口 LEDE 转发 TCP ${port}→6.251:${port}"
      level="ok"
    fi
    jq -nc \
      --arg site_id "$sid" \
      --arg name "$tname" \
      --argjson port "$port" \
      --arg local "$local" \
      --arg online "$online" \
      --arg frp_local "${frp_local:-}" \
      --arg frp_target "${frp_target:-}" \
      --arg hint "$hint" \
      --arg level "$level" \
      --arg http_code "${code:-}" \
      '{site_id:$site_id,name:$name,port:$port,local:$local,online:($online=="online"),frp_local:$frp_local,frp_target:$frp_target,hint:$hint,level:$level,http_code:$http_code}'
  done | jq -s '.')"
fi

jq -n \
  --argjson server "$server" \
  --argjson tcp "$tcp" \
  --argjson tunnel_checks "$tunnel_checks" \
  --arg updated "$updated" \
  '{server: $server, tcp: $tcp, tunnel_checks: $tunnel_checks, updated: $updated}' >"$TMP"
mv -f "$TMP" "$OUT"
chmod 644 "$OUT"
