#!/bin/bash
# Build every scripts/component-manifests/*.list component pack into dist/
set -euo pipefail
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/.." && pwd)
MANIFESTS=$ROOT/scripts/component-manifests
BUILD=$HERE/build-lede-component-pack.sh

shopt -s nullglob
lists=("$MANIFESTS"/*.list)
if [ ${#lists[@]} -eq 0 ]; then
	echo "no *.list in $MANIFESTS" >&2
	exit 1
fi

for f in "${lists[@]}"; do
	name=$(basename "$f" .list)
	echo "==> $name"
	bash "$BUILD" "$name"
done

echo "All packs in $ROOT/dist/"
