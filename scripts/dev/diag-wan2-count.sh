#!/bin/sh
LOG=/data/logs/alert/sys-alert.log
FROM='2026-09-17 23:44:00'
TO='2026-09-17 23:45:59'
echo "=== Wan_2 events $FROM - $TO ==="
awk -F'|' -v from="$FROM" -v to="$TO" '
  $1 >= from && $1 <= to && $0 ~ /Wan_2/ {
    print $1, $2, $3, $4
  }
' "$LOG"
echo "=== counts by title ==="
awk -F'|' -v from="$FROM" -v to="$TO" '
  $1 >= from && $1 <= to && $0 ~ /Wan_2/ {
    print $4
  }
' "$LOG" | sort | uniq -c
echo "=== pushable (not 信息) ==="
awk -F'|' -v from="$FROM" -v to="$TO" '
  $1 >= from && $1 <= to && $0 ~ /Wan_2/ && $2 != "信息" {
    print $1, $2, $4
  }
' "$LOG" | wc -l
echo "=== state file ==="
cat /tmp/wan-alert.state 2>/dev/null || true
