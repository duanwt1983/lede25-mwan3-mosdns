#!/bin/sh
# macOS port of diag-lansec-ttl3.ps1. Talks to the router over LuCI ubus.
# Usage: ./diag-lansec-ttl3.sh [router-ip] [password]
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
# shellcheck disable=SC1091
. "$HERE/ubus.sh"
export UBUS_TIMEOUT=180

router_open "${1:-192.168.8.1}" "${2:-password}"
printf 'LOGIN_OK %s\n' "$ROUTER_IP"

router_sh "$(cat <<'END_REMOTE'
echo === lan-origin to internet ===
timeout 8 tcpdump -i br-lan -nn -c 100 -v "src net 192.168.8.0/24 and not dst net 192.168.8.0/24" > /tmp/lede-ttl-out.txt 2>/tmp/lede-ttl-out.err
cat /tmp/lede-ttl-out.err
echo TTL_HIST
grep -oE "ttl [0-9]+" /tmp/lede-ttl-out.txt | sort | uniq -c | sort -nr
echo BY_SRC
# pair src IP with ttl from following header line
awk '
  /^[0-9]/ && /IP / {
    src=$3
    gsub(/\.[0-9]+$/,"",src)
  }
  /ttl / {
    ttl=""
    if (match($0, /ttl [0-9]+/)) ttl=substr($0, RSTART+4, RLENGTH-4)
    if (src!="" && ttl!="") { print src, ttl; src="" }
  }
' /tmp/lede-ttl-out.txt | sort | uniq -c | sort -nr | head -n 40
echo === sample iphone 8.176 / ipad 8.240 / desktop 8.107 / honor 8.74 ===
grep -A1 -E "192.168.8.(176|240|107|74|38)[.]" /tmp/lede-ttl-out.txt | head -n 40
END_REMOTE
)"
router_print
