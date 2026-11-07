#!/bin/sh
# Write the firmware compile time into the OpenWrt files/ overlay.
# Format: YYYY-MM-DD-HH:MM:SS (Asia/Shanghai), shown after「固件升级」.
# Usage: stamp-lede-buildtime.sh /path/to/openwrt
set -eu
root="${1:-.}"
export TZ="${TZ:-Asia/Shanghai}"
dir="$root/files/etc"
mkdir -p "$dir"
stamp=$(date '+%Y-%m-%d-%H:%M:%S')
printf '%s\n' "$stamp" > "$dir/lede-buildtime"
echo "lede-buildtime=$stamp"
