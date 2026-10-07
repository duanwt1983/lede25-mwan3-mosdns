#!/bin/sh
export PATH=/usr/sbin:/sbin:/usr/bin:/bin

# Must not abort mid-way: old images often lack /data mount until bootstrap runs.
if [ -x /usr/libexec/lede-firmware-bootstrap.sh ]; then
	/usr/libexec/lede-firmware-bootstrap.sh full >> /tmp/lede-component-apply.log 2>&1 || true
fi

if [ -x /usr/libexec/lede-firmware-upload-env.sh ]; then
	/usr/libexec/lede-firmware-upload-env.sh >> /tmp/lede-component-apply.log 2>&1 || true
fi

if [ -x /usr/libexec/lede-firmware-upload-check.sh ]; then
	/usr/libexec/lede-firmware-upload-check.sh >> /tmp/lede-component-apply.log 2>&1 || true
fi

exit 0
