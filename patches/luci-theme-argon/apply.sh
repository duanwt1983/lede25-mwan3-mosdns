#!/bin/bash
# Argon: description as brand text + fixed brand fonts.

set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/files/ucode/template/themes/argon"
DEST="$ROOT/package/luci-theme-argon/ucode/template/themes/argon"
CSS_SRC="$ROOT/files/www/luci-static/argon/css/lede-brand-font.css"
CSS_DEST="$ROOT/package/luci-theme-argon/htdocs/luci-static/argon/css/lede-brand-font.css"
FONT_SRC="$ROOT/files/www/luci-static/argon/font/DuanNingMaoBiXingShuWanZhengBan-2.ttf"
FONT_DEST="$ROOT/package/luci-theme-argon/htdocs/luci-static/argon/font/DuanNingMaoBiXingShuWanZhengBan-2.ttf"

[ -d "$DEST" ] || { echo "argon theme: skip (package not cloned yet)"; exit 0; }

for f in sysauth.ut header.ut header_login.ut; do
	[ -f "$SRC/$f" ] || continue
	install -D -m 0644 "$SRC/$f" "$DEST/$f"
	echo "argon theme: overlay $f"
done

if [ -f "$CSS_SRC" ]; then
	install -D -m 0644 "$CSS_SRC" "$CSS_DEST"
	echo "argon theme: overlay lede-brand-font.css"
fi

if [ -f "$FONT_SRC" ]; then
	install -D -m 0644 "$FONT_SRC" "$FONT_DEST"
	echo "argon theme: overlay DuanNingMaoBiXingShuWanZhengBan-2.ttf"
fi
