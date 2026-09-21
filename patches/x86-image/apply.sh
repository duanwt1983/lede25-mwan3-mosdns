#!/bin/sh
set -eu

ROOT="${1:-.}"
SELF="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
GEN="$ROOT/scripts/gen_image_generic.sh"
IMG_MK="$ROOT/target/linux/x86/image/Makefile"

[ -f "$GEN" ] || {
	echo "ERROR: gen_image_generic.sh not found: $GEN" >&2
	exit 1
}
[ -f "$IMG_MK" ] || {
	echo "ERROR: x86 image Makefile not found: $IMG_MK" >&2
	exit 1
}

python3 - "$GEN" "$IMG_MK" <<'PY'
from pathlib import Path
import sys

gen_path, mk_path = map(Path, sys.argv[1:3])
text = gen_path.read_text()

if 'DATAPARTSIZE' in text and '-N LEDEDATA' in text:
    print('gen_image_generic.sh already has LEDEDATA partition')
else:
    if 'DATAPARTSIZE=' not in text:
        text = text.replace(
            'ROOTFSIMAGE="$5"\n',
            'ROOTFSIMAGE="$5"\nDATAPARTSIZE="${DATAPARTSIZE:-64}m"\n',
            1,
        )

    text = text.replace(
        '-p "${ROOTFSSIZE}m" ${ALIGN:+-l $ALIGN} -G "$GUID")',
        '-p "${ROOTFSSIZE}m" -N LEDEDATA -p "${DATAPARTSIZE}" ${ALIGN:+-l $ALIGN} -G "$GUID")',
    )
    text = text.replace(
        'GPT_DISK_SIZE=$((($3 + $4 + 1023) / 1024 + ${GPT_PADDING_KB:-1024}))',
        'GPT_DISK_SIZE=$((($5 + $6 + 1023) / 1024 + ${GPT_PADDING_KB:-1024}))',
    )
    text = text.replace(
        '-p "${ROOTFSSIZE}m" ${ALIGN:+-l $ALIGN} ${SIGNATURE:+-S 0x$SIGNATURE} ${GUID:+-G $GUID})',
        '-p "${ROOTFSSIZE}m" -N LEDEDATA -p "${DATAPARTSIZE}" ${ALIGN:+-l $ALIGN} ${SIGNATURE:+-S 0x$SIGNATURE} ${GUID:+-G $GUID})',
    )
    if 'DATAPARTSIZE' not in text or '-N LEDEDATA' not in text:
        raise SystemExit('ERROR: failed to patch gen_image_generic.sh for LEDEDATA')
    gen_path.write_text(text)
    print('patched gen_image_generic.sh: LEDEDATA placeholder partition')

# Older patch revisions wired a post-build lede-data-part hook that failed to
# receive $@ from OpenWrt's Build/* call context. ptgen already creates the
# partition; strip any leftover hook/pipeline entries from re-runs.
mk = mk_path.read_text()
if 'Build/lede-data-part' in mk or 'lede-data-part |' in mk:
    mk = mk.replace(
        """define Build/lede-data-part
\tPATH=\"$(STAGING_DIR_HOST)/bin:$$PATH\" $(SCRIPT_DIR)/lede_gen_data_part.sh $$@
endef

""",
        '',
    )
    mk = mk.replace(' | lede-data-part', '')
    mk_path.write_text(mk)
    print('removed obsolete lede-data-part image hook')
PY

grep -q 'DATAPARTSIZE' "$GEN"
grep -q -- '-N LEDEDATA' "$GEN"
echo "x86 LEDEDATA image partition installed"
