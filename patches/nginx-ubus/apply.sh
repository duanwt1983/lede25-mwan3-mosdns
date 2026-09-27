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

# Current openwrt/packages automatically discovers patches/nginx-mod-<name>
# and applies them after unpacking that module.
if grep -q 'PKG_MOD_PATCHED' "$MK"; then
	mkdir -p "$PKG/patches/nginx-mod-ubus"
	cp "$SELF/100-request-body-null-guard.patch" \
		"$PKG/patches/nginx-mod-ubus/100-request-body-null-guard.patch"
	echo "nginx ubus request-body guard installed (nginx-mod-ubus)"
	exit 0
fi

# LEDE/coolsnowwolf nginx 1.21.x: patch ubus module via Build/Patch like dav/lua.
mkdir -p "$PKG/patches/ubus-nginx"
cp "$SELF/100-request-body-null-guard.patch" \
	"$PKG/patches/ubus-nginx/100-request-body-null-guard.patch"

python3 - "$MK" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
hook = (
	'ifneq "$(or $(CONFIG_NGINX_UBUS),$(QUILT))" ""\n'
	'\t$(call PatchDir,$(PKG_BUILD_DIR),$(PATCH_DIR)/ubus-nginx,nginx-ubus-module/)\n'
	'endif\n'
)

if 'PATCH_DIR)/ubus-nginx,nginx-ubus-module/' in text:
    print('nginx ubus patch hook already present')
    sys.exit(0)

# Drop hooks from older apply.sh revisions.
text = re.sub(
    r'\nifneq "\$\(or \$\(CONFIG_NGINX_UBUS\),\$\(QUILT\)\)" ""\n'
    r'\t\$\(call PatchDir,\$\(PKG_BUILD_DIR\),\$\(PATCH_DIR\)/ubus-nginx,nginx-ubus-module/\)\n'
    r'endif\n',
    '\n',
    text,
)
text = re.sub(
    r'^[\t ]+\$\(call PatchDir,\$\(PKG_BUILD_DIR\),\$\(PATCH_DIR\)/ubus-nginx,nginx-ubus-module/\)\n',
    '',
    text,
    flags=re.MULTILINE,
)

# Insert before the quilt marker at the end of Build/Patch. Do not anchor on
# rtmp/lua endif lines: LEDE Makefiles leave "endif" unindented.
pattern = re.compile(
    r'^(\t\$\(if \$\(QUILT\),touch \$\(PKG_BUILD_DIR\)/\.quilt_used\)\n)',
    re.MULTILINE,
)
if not pattern.search(text):
    raise SystemExit('ERROR: nginx Build/Patch quilt marker not found')

text = pattern.sub(hook + r'\1', text, count=1)
path.write_text(text)
PY

grep -q 'PATCH_DIR)/ubus-nginx,nginx-ubus-module/' "$MK"
echo "nginx ubus request-body guard installed"
