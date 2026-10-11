#!/bin/bash
# Create (or keep) regional center PKI and frps server cert. Safe to re-run.
set -euo pipefail

CA_DIR="${LEDE_CA_DIR:-/etc/lede-center-ca}"
FRP_DIR="${FRP_TLS_DIR:-/etc/frp}"
PUB_DIR="${CA_PUB_DIR:-/var/www/center-portal/ca}"
DAYS_CA="${LEDE_CA_DAYS:-3650}"
DAYS_SERVER="${LEDE_FRPS_CERT_DAYS:-825}"
FORCE="${LEDE_CA_FORCE:-0}"

DOMAIN="${CENTER_SERVER_NAME:-center.123.gd.cn}"
if [ -f /etc/frp/frps.toml ]; then
  m="$(grep -E '^[[:space:]]*#?[[:space:]]*center-portal domain:' /etc/frp/frps.toml 2>/dev/null | head -1 || true)"
  [ -n "$m" ] && DOMAIN="${m##*:}" && DOMAIN="${DOMAIN// /}"
fi

need_openssl() {
  command -v openssl >/dev/null 2>&1 || { echo "openssl required" >&2; exit 1; }
}

need_openssl
mkdir -p "$CA_DIR" "$FRP_DIR" "$PUB_DIR"
chmod 700 "$CA_DIR"

if [ -f "$CA_DIR/root-ca.crt" ] && [ -f "$CA_DIR/frps.crt" ] && [ "$FORCE" != "1" ]; then
  echo "CA already exists at $CA_DIR (set LEDE_CA_FORCE=1 to regenerate)"
else
  echo "Generating regional center CA and frps certificate for $DOMAIN …"
  rm -f "$CA_DIR/root-ca.key" "$CA_DIR/root-ca.crt" "$CA_DIR/frps.key" "$CA_DIR/frps.crt" "$CA_DIR/frps.csr"
  openssl genrsa -out "$CA_DIR/root-ca.key" 4096
  chmod 600 "$CA_DIR/root-ca.key"
  openssl req -x509 -new -nodes -key "$CA_DIR/root-ca.key" -sha256 -days "$DAYS_CA" \
    -out "$CA_DIR/root-ca.crt" \
    -subj "/CN=LEDE Regional Center CA/O=Regional Access Center/C=CN"
  openssl genrsa -out "$CA_DIR/frps.key" 2048
  chmod 600 "$CA_DIR/frps.key"
  openssl req -new -key "$CA_DIR/frps.key" -out "$CA_DIR/frps.csr" \
    -subj "/CN=${DOMAIN}/O=Regional Access Center/C=CN"
  ext="$(mktemp)"
  cat >"$ext" <<EOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:${DOMAIN},DNS:center.example.com,IP:192.168.6.251
EOF
  openssl x509 -req -in "$CA_DIR/frps.csr" -CA "$CA_DIR/root-ca.crt" -CAkey "$CA_DIR/root-ca.key" \
    -CAcreateserial -out "$CA_DIR/frps.crt" -days "$DAYS_SERVER" -sha256 -extfile "$ext"
  rm -f "$ext" "$CA_DIR/frps.csr" "$CA_DIR/root-ca.srl"
fi

install -m 0644 "$CA_DIR/root-ca.crt" "$PUB_DIR/root-ca.crt"
ln -sf "$CA_DIR/frps.crt" "$FRP_DIR/frps.crt"
ln -sf "$CA_DIR/frps.key" "$FRP_DIR/frps.key"
chmod 644 "$FRP_DIR/frps.crt" 2>/dev/null || true

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
if [ -x "$SCRIPT_DIR/center-portal-ca-apply-frps.sh" ]; then
  "$SCRIPT_DIR/center-portal-ca-apply-frps.sh"
fi

echo "CA ready: $CA_DIR/root-ca.crt (portal: /home/ca/root-ca.crt)"
