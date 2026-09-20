#!/bin/sh
# Post-process combined x86 image: ensure GPT LEDEDATA placeholder exists.
# Primary path is ptgen in gen_image_generic.sh; this is a safety net.
set -eu

IMG="$1"
LABEL=LEDEDATA

[ -f "$IMG" ] || {
	echo "ERROR: image not found: $IMG" >&2
	exit 1
}

if command -v sgdisk >/dev/null 2>&1; then
	if sgdisk -p "$IMG" 2>/dev/null | grep -q "$LABEL"; then
		exit 0
	fi
	sgdisk -e "$IMG" >/dev/null 2>&1 || true
	sgdisk -n 0:0 -c 0:"$LABEL" -t 0:8300 "$IMG"
	exit 0
fi

echo "WARN: sgdisk missing, relying on ptgen LEDEDATA partition" >&2
exit 0
