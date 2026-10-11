#!/bin/bash
# Install or upgrade frps to match firmware frpc (default 0.71.0). Run on center host (6.251).
set -euo pipefail

FRP_VERSION="${FRP_VERSION:-0.71.0}"
ARCH="${FRP_ARCH:-linux_amd64}"
INSTALL_DIR="${FRP_INSTALL_DIR:-/usr/local/bin}"
TOML="${FRPS_TOML:-/etc/frp/frps.toml}"
TOKEN_FILE="${FRP_TOKEN_FILE:-/etc/frp/frps.token}"
SERVICE="${FRPS_SERVICE:-frps}"

case "$ARCH" in
  linux_amd64)
    HASH="84f27e39f11169f7adcef8e8b70c9329de17747b1f14dad9fb95eef5682ea716"
    ;;
  linux_arm64)
    HASH="f33c293c275d8fc68c654b6fba8f10b2551d6463d09a9fc9cffb7227eae82266"
    ;;
  *)
    echo "unsupported FRP_ARCH=$ARCH" >&2
    exit 1
    ;;
esac

TARBALL="frp_${FRP_VERSION}_${ARCH}.tar.gz"
URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${TARBALL}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "Downloading frp ${FRP_VERSION} (${ARCH})…"
curl -sfL "$URL" -o "$WORKDIR/$TARBALL"
echo "$HASH  $WORKDIR/$TARBALL" | sha256sum -c -

tar -xzf "$WORKDIR/$TARBALL" -C "$WORKDIR"
SRC="$WORKDIR/frp_${FRP_VERSION}_${ARCH}/frps"
[ -x "$SRC" ] || { echo "frps binary missing in tarball" >&2; exit 1; }

if [ -x "${INSTALL_DIR}/frps" ]; then
  cp -a "${INSTALL_DIR}/frps" "${INSTALL_DIR}/frps.bak.$(date +%Y%m%d%H%M%S)"
fi
install -m 0755 "$SRC" "${INSTALL_DIR}/frps"
mkdir -p /opt/frp
install -m 0755 "$SRC" /opt/frp/frps
"${INSTALL_DIR}/frps" --version || true
/opt/frp/frps --version || true

mkdir -p "$(dirname "$TOML")"
if [ ! -f "$TOML" ]; then
  echo "WARN: $TOML missing — install from center-portal/config/frps.toml.example" >&2
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
if [ -x "$SCRIPT_DIR/center-portal-ensure-frps-dashboard.sh" ]; then
  "$SCRIPT_DIR/center-portal-ensure-frps-dashboard.sh" || true
fi

if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files "$SERVICE.service" >/dev/null 2>&1; then
  systemctl restart "$SERVICE"
  systemctl --no-pager --full status "$SERVICE" || true
else
  echo "No systemd unit $SERVICE — restart frps manually." >&2
fi

if [ -x /opt/center-portal/center-portal-status.sh ]; then
  /opt/center-portal/center-portal-status.sh
fi

echo "frps upgraded to ${FRP_VERSION}. Gateways need firmware with matching frpc."
