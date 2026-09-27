#!/bin/bash
# Build a LuCI-installable overlay pack (.tar.gz + manifest.json).
# Run on any host with bash, tar, and shasum (or sha256sum).
#
# Usage:
#   ./scripts/build-lede-component-pack.sh              # entire files/ tree
#   ./scripts/build-lede-component-pack.sh hwinfo       # paths from manifests/hwinfo.list
#   ./scripts/build-lede-component-pack.sh path1 path2  # explicit files/ relative paths
#
# Manifest builds use scripts/component-manifests/<name>.meta when present:
#   pack_id, version, description, archive (output filename under dist/)
# Otherwise: pack_id=lede-component-<name>, version=1.0.0,
#   archive=lede-component-<name>-v1.0.0.tar.gz

set -euo pipefail
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
FILES=$ROOT/files
MANIFESTS=$ROOT/scripts/component-manifests
STAGE=$(mktemp -d)
MANIFEST_KEY=""
PACK_ID=lede-overlay-full
VERSION=1.0.0
DESCRIPTION="LEDE overlay component pack"
ARCHIVE=""
trap 'rm -rf "$STAGE"' EXIT

load_meta() {
	local key=$1
	local f="$MANIFESTS/$key.meta"
	[ -f "$f" ] || return 0
	while IFS= read -r line || [ -n "$line" ]; do
		line=${line%%#*}
		line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
		[ -n "$line" ] || continue
		case "$line" in
			pack_id=*) PACK_ID=${line#pack_id=} ;;
			version=*) VERSION=${line#version=} ;;
			description=*) DESCRIPTION=${line#description=} ;;
			archive=*) ARCHIVE=${line#archive=} ;;
		esac
	done < "$f"
}

paths=()
if [ $# -eq 0 ]; then
	PACK_ID=lede-overlay-full
	VERSION=1.0.0
	DESCRIPTION="LEDE full overlay (all files/)"
	ARCHIVE=lede-component-full-v1.0.0.tar.gz
	while IFS= read -r -d '' f; do
		paths+=("${f#"$FILES/"}")
	done < <(find "$FILES" -type f ! -name '.gitkeep' -print0)
elif [ $# -eq 1 ] && [ -f "$MANIFESTS/$1.list" ]; then
	MANIFEST_KEY=$1
	PACK_ID="lede-component-$1"
	VERSION=1.0.0
	DESCRIPTION="LEDE component: $1"
	ARCHIVE="lede-component-$1-v1.0.0.tar.gz"
	load_meta "$1"
	while IFS= read -r line || [ -n "$line" ]; do
		line=${line%%#*}
		line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
		[ -n "$line" ] && paths+=("$line")
	done < "$MANIFESTS/$1.list"
else
	PACK_ID=lede-component-custom
	VERSION=1.0.0
	DESCRIPTION="LEDE custom file list"
	ARCHIVE=lede-component-custom-v1.0.0.tar.gz
	paths=("$@")
fi

[ -n "$ARCHIVE" ] || ARCHIVE="${PACK_ID}.tar.gz"

mkdir -p "$STAGE/root"
json_files=()
for rel in "${paths[@]}"; do
	src="$FILES/$rel"
	[ -f "$src" ] || { echo "missing: $src" >&2; exit 1; }
	dest="$STAGE/root/$rel"
	mkdir -p "$(dirname "$dest")"
	cp -f "$src" "$dest"
	mode=644
	case "$rel" in
		usr/libexec/*|etc/init.d/*|etc/hotplug.d/*|etc/uci-defaults/*)
			mode=755
			;;
	esac
	if [ -x "$src" ]; then mode=755; fi
	sha=$(shasum -a 256 "$src" | awk '{print $1}')
	json_files+=("{\"path\":\"$rel\",\"mode\":\"$mode\",\"sha256\":\"$sha\"}")
done

desc_json=$(printf '%s' "$DESCRIPTION" | sed 's/\\/\\\\/g; s/"/\\"/g')

{
  printf '%s\n' '{' \
    '  "format": 1,' \
    "  \"pack_id\": \"$PACK_ID\"," \
    "  \"version\": \"$VERSION\"," \
    "  \"description\": \"$desc_json\"," \
    '  "files": ['
  n=${#json_files[@]}
  for i in "${!json_files[@]}"; do
    printf '    %s' "${json_files[$i]}"
    [ "$i" -lt $((n - 1)) ] && printf ','
    printf '\n'
  done
  printf '%s\n' '  ]' '}'
} > "$STAGE/root/manifest.json"

if [ -n "$MANIFEST_KEY" ] && [ -f "$MANIFESTS/$MANIFEST_KEY.post-apply.sh" ]; then
	cp "$MANIFESTS/$MANIFEST_KEY.post-apply.sh" "$STAGE/root/post-apply.sh"
	chmod 755 "$STAGE/root/post-apply.sh"
elif [ -f "$MANIFESTS/post-apply.sh" ] && [ "$MANIFEST_KEY" = samba4 ]; then
	cp "$MANIFESTS/post-apply.sh" "$STAGE/root/post-apply.sh"
	chmod 755 "$STAGE/root/post-apply.sh"
fi

mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/$ARCHIVE"
tar -C "$STAGE/root" -czf "$OUT" .
echo "Wrote $OUT"
echo "  pack_id:  $PACK_ID"
echo "  version:  $VERSION"
echo "Install: 系统 → 备份与更新 → 操作 → 组件升级"
