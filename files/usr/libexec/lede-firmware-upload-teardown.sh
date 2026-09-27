#!/bin/sh
# Drop temporary cgi upload bind; firmware flow calls this when done or on cancel.
set -eu
export PATH=/usr/sbin:/sbin:/usr/bin:/bin

if grep -q ' /dat ' /proc/mounts 2>/dev/null; then
	umount /dat 2>/dev/null || umount -l /dat 2>/dev/null || true
fi
exit 0
