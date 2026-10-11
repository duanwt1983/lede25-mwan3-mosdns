#!/bin/bash
# Point frps.toml at issued TLS certs (single certFile/keyFile) and restart frps.
set -euo pipefail

export FRPS_TOML="${FRPS_TOML:-/etc/frp/frps.toml}"
export LEDE_CA_DIR="${LEDE_CA_DIR:-/etc/lede-center-ca}"
SERVICE="${FRPS_SERVICE:-frps}"
FRPS_BIN="${FRPS_INSTALL:-/opt/frp/frps}"

[ -f "$LEDE_CA_DIR/frps.crt" ] && [ -f "$LEDE_CA_DIR/frps.key" ] || {
  echo "missing $LEDE_CA_DIR/frps.crt — run center-portal-ca-init first" >&2
  exit 1
}

python3 <<'PY'
import os
import re
from pathlib import Path

toml = Path(os.environ["FRPS_TOML"])
ca = Path(os.environ["LEDE_CA_DIR"])
cert = ca / "frps.crt"
key = ca / "frps.key"
if not toml.is_file():
    print("skip: no frps.toml")
    raise SystemExit(0)
text = toml.read_text(encoding="utf-8")
begin = "# >>> center-portal frps tls (managed) >>>"
end = "# <<< center-portal frps tls (managed) <<<"
# Remove prior managed block and standalone tls cert lines (avoid duplicate TOML keys).
text = re.sub(re.escape(begin) + r".*?" + re.escape(end) + r"\n?", "", text, flags=re.S)
text = re.sub(r'(?m)^\s*transport\.tls\.[^\n]+\n', "", text)
block = (
    begin + "\n"
    + "transport.tls.force = true\n"
    + f'transport.tls.certFile = "{cert}"\n'
    + f'transport.tls.keyFile = "{key}"\n'
    + end + "\n"
)
if not text.endswith("\n"):
    text += "\n"
text += "\n" + block
toml.write_text(text, encoding="utf-8")
print("patched", toml)
PY

if [ -x /usr/local/bin/frps ]; then
  install -m 0755 /usr/local/bin/frps "$FRPS_BIN" 2>/dev/null || cp -a /usr/local/bin/frps "$FRPS_BIN"
fi
if [ -x "$FRPS_BIN" ]; then
  "$FRPS_BIN" verify -c "$FRPS_TOML"
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SERVICE" 2>/dev/null || true
fi
