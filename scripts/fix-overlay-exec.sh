#!/bin/sh
# Mark overlay scripts executable in git index and working tree.
# Run from repo root after adding new init/hotplug/libexec scripts.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

is_exec_target() {
	case "$1" in
		files/etc/init.d/*|\
		files/etc/hotplug.d/*/*|\
		files/usr/libexec/*|\
		files/usr/libexec/rpcd/*|\
		files/usr/sbin/*|\
		package/mosdns-mwan/files/etc/hotplug.d/*/*|\
		package/mosdns-mwan/files/usr/libexec/*|\
		package/mosdns-mwan/files/usr/sbin/*|\
		package/mosdns-mwan/files/usr/share/mosdns/*)
			return 0
			;;
	esac
	return 1
}

has_shebang() {
	[ -f "$1" ] && head -c 2 "$1" 2>/dev/null | grep -q '^#.'
}

fixed=0
skipped=0
while IFS= read -r -d '' f; do
	is_exec_target "$f" || continue
	has_shebang "$f" || continue
	mode="$(git ls-files -s -- "$f" 2>/dev/null | awk '{print $1}')"
	[ -n "$mode" ] || continue
	chmod 755 "$f" 2>/dev/null || true
	if [ "$mode" = "100644" ]; then
		git update-index --chmod=+x -- "$f"
		echo "EXEC $f"
		fixed=$((fixed + 1))
	else
		skipped=$((skipped + 1))
	fi
done < <(git ls-files -z -- files package/mosdns-mwan/files)

echo "fix-overlay-exec: +x set for $fixed file(s), already executable: $skipped"
