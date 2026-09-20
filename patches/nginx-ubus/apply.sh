#!/bin/sh
set -eu

ROOT="${1:-.}"
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PKG="$ROOT/feeds/packages/net/nginx"
MK="$PKG/Makefile"

[ -f "$MK" ] || {
	echo "ERROR: nginx package Makefile not found: $MK" >&2
	exit 1
}

mkdir -p "$PKG/patches/ubus-nginx"
cp "$SELF/100-request-body-null-guard.patch" \
	"$PKG/patches/ubus-nginx/100-request-body-null-guard.patch"

python3 - "$MK" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = """ifeq ($(CONFIG_NGINX_UBUS),y)
 $(eval $(call Download,nginx-ubus-module))
 $(Prepare/nginx-ubus-module)
endif
"""
replacement = """ifeq ($(CONFIG_NGINX_UBUS),y)
 $(eval $(call Download,nginx-ubus-module))
 $(Prepare/nginx-ubus-module)
 $(call PatchDir,$(PKG_BUILD_DIR),$(PATCH_DIR)/ubus-nginx,nginx-ubus-module/)
endif
"""

if replacement not in text:
    if needle not in text:
        raise SystemExit("ERROR: nginx ubus prepare block not found")
    text = text.replace(needle, replacement, 1)
    path.write_text(text)
PY

grep -q 'PATCH_DIR)/ubus-nginx,nginx-ubus-module/' "$MK"
echo "nginx ubus request-body guard installed"
