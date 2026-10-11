#!/bin/bash
# Ensure frps.toml has local Dashboard (API v2) + optional Prometheus for the portal.
set -euo pipefail

TOML="${FRPS_TOML:-/etc/frp/frps.toml}"
MARK_BEGIN="# >>> center-portal dashboard (managed) >>>"
MARK_END="# <<< center-portal dashboard (managed) <<<"

[ -f "$TOML" ] || {
  echo "skip: $TOML not found" >&2
  exit 0
}

export FRPS_TOML="$TOML"
python3 <<'PY'
import os
import re
import secrets
from pathlib import Path

toml = Path(os.environ["FRPS_TOML"])
text = toml.read_text(encoding="utf-8")
begin = "# >>> center-portal dashboard (managed) >>>"
end = "# <<< center-portal dashboard (managed) <<<"

def has_key(key: str) -> bool:
    return re.search(rf"^\s*{re.escape(key)}\s*=", text, re.M) is not None

block = []
if not has_key("webServer.addr"):
    block.append('webServer.addr = "127.0.0.1"')
if not has_key("webServer.port"):
    block.append("webServer.port = 7500")
if not has_key("webServer.user"):
    block.append('webServer.user = "portal"')
if not has_key("webServer.password"):
    block.append(f'webServer.password = "{secrets.token_urlsafe(16)}"')
if not has_key("enablePrometheus"):
    block.append("enablePrometheus = true")

if not block:
    print("dashboard keys already present in frps.toml")
    raise SystemExit(0)

managed = begin + "\n" + "\n".join(block) + "\n" + end + "\n"
if begin in text:
    text = re.sub(re.escape(begin) + r".*?" + re.escape(end) + r"\n?", managed, text, flags=re.S)
else:
    if not text.endswith("\n"):
        text += "\n"
    text += "\n" + managed

toml.write_text(text, encoding="utf-8")
print("patched", toml, "with dashboard block")
PY
