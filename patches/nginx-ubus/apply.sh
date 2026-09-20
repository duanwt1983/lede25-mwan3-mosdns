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

# Compatibility with the older nginx package layout used by LEDE snapshots.
mkdir -p "$PKG/patches/ubus-nginx"
cp "$SELF/100-request-body-null-guard.patch" \
	"$PKG/patches/ubus-nginx/100-request-body-null-guard.patch"

python3 - "$MK" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
hook = '\t$(call PatchDir,$(PKG_BUILD_DIR),$(PATCH_DIR)/ubus-nginx,nginx-ubus-module/)\n'

if 'PATCH_DIR)/ubus-nginx,nginx-ubus-module/' in text:
    print('nginx ubus patch hook already present')
    sys.exit(0)

block = (
	'ifneq "$(or $(CONFIG_NGINX_UBUS),$(QUILT))" ""\n'
	'\t$(call PatchDir,$(PKG_BUILD_DIR),$(PATCH_DIR)/ubus-nginx,nginx-ubus-module/)\n'
	'endif\n'
)
anchor = re.search(
	r'\t\$\(if \$\(QUILT\),touch \$\(PKG_BUILD_DIR\)/\.quilt_used\)\nendef',
	text,
)
if anchor:
	text = text[:anchor.start()] + block + text[anchor.start():]
	path.write_text(text)
	sys.exit(0)

pattern = re.compile(
	r'ifeq \(\$\(CONFIG_NGINX_UBUS\),y\)\n'
	r'[\t ]+\$\(eval \$\(call Download,nginx-ubus-module\)\)\n'
	r'[\t ]+\$\(Prepare/nginx-ubus-module\)\n'
	r'endif\n'
)
new, n = pattern.subn(lambda m: m.group(0) + hook, text, count=1)
if n:
	path.write_text(new)
	sys.exit(0)

raise SystemExit('ERROR: nginx ubus patch hook not found')
PY

grep -q 'PATCH_DIR)/ubus-nginx,nginx-ubus-module/' "$MK"
echo "nginx ubus request-body guard installed"
