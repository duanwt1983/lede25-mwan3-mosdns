#!/bin/bash
# frps dashboard snapshot (API v2 + v1 fallback) + tunnel reachability for the portal.
set -euo pipefail

OUT="${1:-/var/www/center-portal/api/status.json}"
TMP="${OUT}.tmp"
SITES="${SITES_JSON:-/var/www/center-portal/sites.json}"
FRPS_TOML="${FRPS_TOML:-/etc/frp/frps.toml}"
DASH_ADDR="${FRPS_DASHBOARD_ADDR:-}"
DASH_PORT="${FRPS_DASHBOARD_PORT:-}"
DASH_USER="${FRPS_DASHBOARD_USER:-}"
DASH_PASS="${FRPS_DASHBOARD_PASS:-}"

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

read_frps_toml() {
  local key="$1" line val
  [ -f "$FRPS_TOML" ] || return 1
  line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$FRPS_TOML" 2>/dev/null | grep -v '^[[:space:]]*#' | head -1)" || return 1
  [ -n "$line" ] || return 1
  val="$(printf '%s' "$line" | sed -E 's/^[^=]*=[[:space:]]*//; s/^"//; s/"[[:space:]]*(#.*)?$//; s/[[:space:]]+#.*$//')"
  [ -n "$val" ] || return 1
  printf '%s' "$val"
}

load_dashboard_config() {
  if [ -z "$DASH_ADDR" ]; then
    DASH_ADDR="$(read_frps_toml 'webServer.addr' 2>/dev/null || true)"
  fi
  [ -n "$DASH_ADDR" ] || DASH_ADDR="127.0.0.1"
  if [ -z "$DASH_PORT" ]; then
    DASH_PORT="$(read_frps_toml 'webServer.port' 2>/dev/null || true)"
  fi
  [ -n "$DASH_PORT" ] || DASH_PORT="7500"
  if [ -z "$DASH_USER" ]; then
    DASH_USER="$(read_frps_toml 'webServer.user' 2>/dev/null || true)"
  fi
  if [ -z "$DASH_PASS" ]; then
    DASH_PASS="$(read_frps_toml 'webServer.password' 2>/dev/null || true)"
  fi
  API="http://${DASH_ADDR}:${DASH_PORT}"
}

frp_curl() {
  local path="$1"
  local extra=() user="$DASH_USER"
  if [ -n "$DASH_PASS" ]; then
    [ -n "$user" ] || user="portal"
    extra=(-u "${user}:${DASH_PASS}")
  elif [ -n "$user" ]; then
    extra=(-u "${user}:")
  fi
  curl -sf --max-time 8 "${extra[@]}" "${API}${path}" 2>/dev/null || true
}

v2_page_items() {
  echo "$1" | jq -c '.data.items // .items // []'
}

v2_page_total() {
  echo "$1" | jq '.data.total // .total // 0'
}

fetch_v2_all_tcp_proxies() {
  local page=1 page_size=200 merged='[]' chunk total pages
  while [ "$page" -le 50 ]; do
    chunk="$(frp_curl "/api/v2/proxies?type=tcp&page=${page}&pageSize=${page_size}")"
    [ -n "$chunk" ] || break
    echo "$chunk" | jq -e '.data.items // .items' >/dev/null 2>&1 || break
    merged="$(jq -nc --argjson acc "$merged" --argjson chunk "$(v2_page_items "$chunk")" '$acc + $chunk')"
    total="$(v2_page_total "$chunk")"
    pages=$(( (total + page_size - 1) / page_size ))
    [ "$pages" -lt 1 ] && pages=1
    [ "$page" -ge "$pages" ] && break
    page=$((page + 1))
  done
  printf '%s' "$merged"
}

fetch_v2_all_clients() {
  local page=1 page_size=200 merged='[]' chunk total pages
  while [ "$page" -le 20 ]; do
    chunk="$(frp_curl "/api/v2/clients?page=${page}&pageSize=${page_size}")"
    [ -n "$chunk" ] || break
    echo "$chunk" | jq -e '.data.items // .items' >/dev/null 2>&1 || break
    merged="$(jq -nc --argjson acc "$merged" --argjson chunk "$(v2_page_items "$chunk")" '$acc + $chunk')"
    total="$(v2_page_total "$chunk")"
    pages=$(( (total + page_size - 1) / page_size ))
    [ "$pages" -lt 1 ] && pages=1
    [ "$page" -ge "$pages" ] && break
    page=$((page + 1))
  done
  printf '%s' "$merged"
}

load_dashboard_config

# 兼容旧部署：Dashboard 曾固定 7400，配置未写 webServer.port 时自动探测
if [ -z "${FRPS_DASHBOARD_PORT:-}" ] && [ -f "$FRPS_TOML" ] && ! grep -qE '^[[:space:]]*webServer\.port[[:space:]]*=' "$FRPS_TOML" 2>/dev/null; then
  for try_port in 7500 7400; do
    probe="http://${DASH_ADDR}:${try_port}/api/healthz"
    if curl -sf --max-time 2 "$probe" >/dev/null 2>&1; then
      DASH_PORT="$try_port"
      API="http://${DASH_ADDR}:${DASH_PORT}"
      break
    fi
  done
fi

api_version=1
server_v2='null'
clients='[]'
v2_tcp_items='[]'

json_valid() {
  echo "$1" | jq -e . >/dev/null 2>&1
}

sys_v2_raw="$(frp_curl /api/v2/system/info)"
[ -n "$sys_v2_raw" ] || sys_v2_raw='{}'
sys_v2="$(echo "$sys_v2_raw" | jq -c '.data // .' 2>/dev/null || echo '{}')"
if [ -n "$sys_v2" ] && json_valid "$sys_v2" && echo "$sys_v2" | jq -e '.version' >/dev/null 2>&1; then
  api_version=2
  server_v2="$sys_v2"
  v2_tcp_items="$(fetch_v2_all_tcp_proxies)"
  clients="$(fetch_v2_all_clients)"
  json_valid "$v2_tcp_items" || v2_tcp_items='[]'
  json_valid "$clients" || clients='[]'
  server="$(echo "$sys_v2" | jq -c '{
    version: .version,
    clientCounts: (.status.clientCounts // 0),
    totalTrafficIn: (.status.totalTrafficIn // 0),
    totalTrafficOut: (.status.totalTrafficOut // 0),
    curConns: (.status.curConns // 0),
    proxyTypeCounts: (.status.proxyTypeCounts // {})
  }')"
else
  server="$(frp_curl /api/serverinfo)"
  server_v2='null'
fi

[ -n "$server" ] || server='{}'
json_valid "$server" || server='{}'

tcp_v1="$(frp_curl /api/proxy/tcp)"
[ -n "$tcp_v1" ] || tcp_v1='{"proxies":[]}'
json_valid "$tcp_v1" || tcp_v1='{"proxies":[]}'

proxies_tcp="$(jq -nc \
  --argjson v2 "$v2_tcp_items" \
  --argjson v1 "$tcp_v1" \
  --argjson api "$api_version" '
  def v1_conf_map:
    reduce (($v1.proxies // [])[]) as $p ({}; .[$p.name] = ($p.conf // {}));
  def from_v2($items; $confmap):
    [$items[] | {
      name: .name,
      user: (.user // ""),
      clientId: (.clientID // .clientId // ""),
      status: (.status.state // "offline"),
      todayTrafficIn: (.status.todayTrafficIn // 0),
      todayTrafficOut: (.status.todayTrafficOut // 0),
      curConns: (.status.curConns // 0),
      lastStartTime: (.status.lastStartAt // .status.lastStartTime // ""),
      lastCloseTime: (.status.lastCloseAt // .status.lastCloseTime // ""),
      conf: ($confmap[.name] // {})
    }];
  def from_v1:
    [($v1.proxies // [])[] | {
      name: .name,
      user: (.user // ""),
      clientId: (.clientId // .clientID // ""),
      status: (.status // "offline"),
      todayTrafficIn: (.todayTrafficIn // 0),
      todayTrafficOut: (.todayTrafficOut // 0),
      curConns: (.curConns // 0),
      lastStartTime: (.lastStartTime // ""),
      lastCloseTime: (.lastCloseTime // ""),
      conf: (.conf // {})
    }];
  (v1_conf_map) as $cm |
  if ($api == 2) and ($v2 | length) > 0 then from_v2($v2; $cm)
  else from_v1 end
')"

tcp="$(jq -nc --argjson proxies "$proxies_tcp" '{proxies: $proxies}')"

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
    online="$(echo "$proxies_tcp" | jq -r --arg n "$pname" '.[]? | select(.name==$n) | .status' 2>/dev/null | head -1)"
    [ -n "$online" ] || online="offline"
    frp_local="$(echo "$proxies_tcp" | jq -r --arg n "$pname" '.[]? | select(.name==$n) | .conf.localIP // empty' 2>/dev/null | head -1)"
    frp_lport="$(echo "$proxies_tcp" | jq -r --arg n "$pname" '.[]? | select(.name==$n) | .conf.localPort // empty' 2>/dev/null | head -1)"
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
      hint="内网 IP 指回中心 6.251，请在网关隧道改为门店 LAN 或测试目标 IP"
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

json_valid "$proxies_tcp" || proxies_tcp='[]'
json_valid "${server_v2:-null}" || server_v2='null'

jq -n \
  --argjson api_version "$api_version" \
  --argjson server "$server" \
  --argjson server_v2 "$server_v2" \
  --argjson tcp "$tcp" \
  --argjson proxies_tcp "$proxies_tcp" \
  --argjson clients "$clients" \
  --argjson tunnel_checks "$tunnel_checks" \
  --arg dashboard_api "$API" \
  --arg updated "$updated" \
  '{
    api_version: $api_version,
    server: $server,
    server_v2: (if $server_v2 == null then null else $server_v2 end),
    tcp: $tcp,
    proxies_tcp: $proxies_tcp,
    clients: $clients,
    tunnel_checks: $tunnel_checks,
    dashboard_api: $dashboard_api,
    updated: $updated
  }' >"$TMP"
mv -f "$TMP" "$OUT"
chmod 644 "$OUT"
