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

cp "$SELF/lede_gen_data_part.sh" "$ROOT/scripts/lede_gen_data_part.sh"
chmod +x "$ROOT/scripts/lede_gen_data_part.sh"

python3 - "$GEN" "$IMG_MK" <<'PY'
from pathlib import Path
import re
import sys

gen_path, mk_path = map(Path, sys.argv[1:3])
text = gen_path.read_text()

if 'DATAPARTSIZE' in text and 'LEDEDATA' in text:
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
        '-p "${ROOTFSSIZE}m" -p "${DATAPARTSIZE}" -l LEDEDATA ${ALIGN:+-l $ALIGN} -G "$GUID")',
    )
    text = text.replace(
        'GPT_DISK_SIZE=$((($3 + $4 + 1023) / 1024 + ${GPT_PADDING_KB:-1024}))',
        'GPT_DISK_SIZE=$((($5 + $6 + 1023) / 1024 + ${GPT_PADDING_KB:-1024}))',
    )
    text = text.replace(
        '-p "${ROOTFSSIZE}m" ${ALIGN:+-l $ALIGN} ${SIGNATURE:+-S 0x$SIGNATURE} ${GUID:+-G $GUID})',
        '-p "${ROOTFSSIZE}m" -p "${DATAPARTSIZE}" -l LEDEDATA ${ALIGN:+-l $ALIGN} ${SIGNATURE:+-S 0x$SIGNATURE} ${GUID:+-G $GUID})',
    )
    if 'DATAPARTSIZE' not in text or 'LEDEDATA' not in text:
        raise SystemExit('ERROR: failed to patch gen_image_generic.sh for LEDEDATA')
    gen_path.write_text(text)
    print('patched gen_image_generic.sh: LEDEDATA placeholder partition')

mk = mk_path.read_text()
hook = """
define Build/lede-data-part
\tPATH=\"$(STAGING_DIR_HOST)/bin:$$PATH\" $(SCRIPT_DIR)/lede_gen_data_part.sh $$@
endef

"""

if 'Build/lede-data-part' not in mk:
    anchor = 'define Build/grub-config\n'
    if anchor not in mk:
        raise SystemExit('ERROR: Build/grub-config anchor not found in x86 image Makefile')
    mk = mk.replace(anchor, hook + anchor, 1)

repls = [
    (
        'IMAGE/combined-efi.img := grub-config efi | combined efi | grub-install efi | append-metadata',
        'IMAGE/combined-efi.img := grub-config efi | combined efi | lede-data-part | grub-install efi | append-metadata',
    ),
    (
        'IMAGE/combined-efi.img.gz := grub-config efi | combined efi | grub-install efi | gzip | append-metadata',
        'IMAGE/combined-efi.img.gz := grub-config efi | combined efi | lede-data-part | grub-install efi | gzip | append-metadata',
    ),
    (
        'IMAGE/combined-efi.vmdk := grub-config efi | combined efi | grub-install efi | qemu-image vmdk',
        'IMAGE/combined-efi.vmdk := grub-config efi | combined efi | lede-data-part | grub-install efi | qemu-image vmdk',
    ),
    (
        'IMAGE/combined-efi.qcow2 := grub-config efi | combined efi | grub-install efi | qemu-image qcow2',
        'IMAGE/combined-efi.qcow2 := grub-config efi | combined efi | lede-data-part | grub-install efi | qemu-image qcow2',
    ),
    (
        'IMAGE/combined-efi.vdi := grub-config efi | combined efi | grub-install efi | qemu-image vdi',
        'IMAGE/combined-efi.vdi := grub-config efi | combined efi | lede-data-part | grub-install efi | qemu-image vdi',
    ),
    (
        'IMAGE/combined-efi.vhdx := grub-config efi | combined efi | grub-install efi | qemu-image vhdx -o subformat=dynamic',
        'IMAGE/combined-efi.vhdx := grub-config efi | combined efi | lede-data-part | grub-install efi | qemu-image vhdx -o subformat=dynamic',
    ),
]
for old, new in repls:
    if old in mk and new not in mk:
        mk = mk.replace(old, new, 1)

if 'lede-data-part' not in mk:
    raise SystemExit('ERROR: failed to wire lede-data-part into x86 image Makefile')

mk_path.write_text(mk)
print('patched x86 image Makefile: lede-data-part hook')
PY

grep -q 'DATAPARTSIZE' "$GEN"
grep -q 'lede-data-part' "$IMG_MK"
echo "x86 LEDEDATA image partition installed"
