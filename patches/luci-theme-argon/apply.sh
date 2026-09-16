#!/bin/bash
# Argon: system.description as brand title + DuanNing MaoBi font (compile + overlay).

set -e
ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"

_files_root() {
	if [ -d "$ROOT/files" ]; then
		echo "$ROOT/files"
	elif [ -d "$(dirname "$ROOT")/files" ]; then
		echo "$(cd "$(dirname "$ROOT")/files" && pwd)"
	else
		echo "$ROOT/files"
	fi
}

FILES_ROOT="$(_files_root)"
SRC_UCODE="$FILES_ROOT/ucode/template/themes/argon"
SRC_SHARE="$FILES_ROOT/usr/share/ucode/luci/template/themes/argon"
if [ -d "$SRC_SHARE" ]; then
	SRC="$SRC_SHARE"
elif [ -d "$SRC_UCODE" ]; then
	SRC="$SRC_UCODE"
else
	SRC="$SRC_UCODE"
fi

CSS_SRC="$FILES_ROOT/www/luci-static/argon/css/lede-brand-font.css"
FONT_SRC="$FILES_ROOT/www/luci-static/argon/font/DuanNingMaoBiXingShuWanZhengBan-2.ttf"
DEST="$ROOT/package/luci-theme-argon/ucode/template/themes/argon"
CSS_DEST="$ROOT/package/luci-theme-argon/htdocs/luci-static/argon/css/lede-brand-font.css"
FONT_DEST="$ROOT/package/luci-theme-argon/htdocs/luci-static/argon/font/DuanNingMaoBiXingShuWanZhengBan-2.ttf"
SHARE_OVERLAY="$FILES_ROOT/usr/share/ucode/luci/template/themes/argon"

[ -d "$DEST" ] || { echo "argon theme: skip (package not cloned yet)"; exit 0; }

if [ ! -f "$CSS_SRC" ] || [ ! -f "$FONT_SRC" ]; then
	echo "argon theme: ERROR missing brand css/font under $FILES_ROOT/www/luci-static/argon/"
	exit 1
fi

mkdir -p "$SHARE_OVERLAY"
for f in sysauth.ut header.ut header_login.ut; do
	[ -f "$SRC/$f" ] || continue
	install -D -m 0644 "$SRC/$f" "$DEST/$f"
	install -D -m 0644 "$SRC/$f" "$SHARE_OVERLAY/$f"
	echo "argon theme: overlay $f -> package + files/usr/share"
done

install -D -m 0644 "$CSS_SRC" "$CSS_DEST"
install -D -m 0644 "$FONT_SRC" "$FONT_DEST"
echo "argon theme: overlay lede-brand-font.css + font -> package"

# CI moves overlay to openwrt/files; drop wrong /ucode path from image only.
case "$FILES_ROOT" in
	*/openwrt/files)
		rm -rf "$FILES_ROOT/ucode" 2>/dev/null || true
		;;
esac
