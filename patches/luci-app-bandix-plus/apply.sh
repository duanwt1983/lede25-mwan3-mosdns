#!/bin/bash
# Patch luci-app-bandix-plus index.js at build time (search, pagination, topo embed).

set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PKG="package/luci-app-bandix-plus/luci-app-bandix-plus/htdocs/luci-static/resources/view/bandix_plus/index.js"
SRC="$ROOT/tmp-bandix-index.js"
OUT="$ROOT/files/www/luci-static/resources/view/bandix_plus/index.js"
PATCH="$ROOT/patches/luci-app-bandix-plus/patch-index.py"

if [ ! -f "$OUT" ]; then
  if [ -f "$PKG" ]; then
    cp "$PKG" "$SRC"
    python3 "$PATCH" "$SRC" "$OUT" || python "$PATCH" "$SRC" "$OUT"
    echo "bandix-plus: patched index.js -> files overlay"
  elif [ -f "$OUT" ]; then
    echo "bandix-plus: using prebuilt overlay index.js"
  else
    echo "bandix-plus: skip patch (no source index.js)"
  fi
else
  echo "bandix-plus: overlay index.js already present"
fi

if [ -f "$PKG" ] && [ -f "$OUT" ]; then
  install -D -m 0644 "$OUT" "$PKG"
  echo "bandix-plus: synced patch into package tree"
fi
