#!/bin/sh
# Apply QoSmate Simplified Chinese i18n patch at build time.
set -e

ROOT="${1:-.}"
SRC="$(cd "$(dirname "$0")" && pwd)"
PKG="$ROOT/package/luci-app-qosmate"

if [ ! -d "$PKG" ]; then
	echo "luci-app-qosmate package not found at $PKG" >&2
	exit 1
fi

PYTHON=python3
command -v python3 >/dev/null 2>&1 || PYTHON=python
command -v "$PYTHON" >/dev/null 2>&1 || {
	echo "python3/python not found" >&2
	exit 1
}

"$PYTHON" "$SRC/generate-po.py" "$PKG"

MAKEFILE="$PKG/Makefile"
if [ -f "$MAKEFILE" ]; then
	if grep -q '^PO_LANG:=zh_Hans' "$MAKEFILE"; then
		echo "Makefile: PO_LANG already zh_Hans"
	elif grep -q '^PO_LANG:=' "$MAKEFILE"; then
		sed -i 's/^PO_LANG:=.*/PO_LANG:=zh_Hans/' "$MAKEFILE"
		echo "Makefile: PO_LANG -> zh_Hans"
	elif grep -q 'include $(TOPDIR)/feeds/luci/luci.mk' "$MAKEFILE"; then
		sed -i 's/include $(TOPDIR)\/feeds\/luci\/luci.mk/PO_LANG:=zh_Hans\ninclude $(TOPDIR)\/feeds\/luci\/luci.mk/' "$MAKEFILE"
		echo "Makefile: inserted PO_LANG:=zh_Hans"
	else
		printf '\nPO_LANG:=zh_Hans\n' >> "$MAKEFILE"
		echo "Makefile: appended PO_LANG:=zh_Hans"
	fi
else
	echo "Makefile not found, skipped PO_LANG patch" >&2
fi

echo "luci-app-qosmate i18n patch applied"
