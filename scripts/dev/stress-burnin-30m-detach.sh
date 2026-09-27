#!/bin/bash
# Detached 30m burn-in (survives closing the launching terminal / IDE shell).
# Usage: ./stress-burnin-30m-detach.sh [router-ip] [password] [minutes]

set -euo pipefail
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../.." && pwd)
ROUTER="${1:-192.168.9.1}"
PASS="${2:-password}"
MINUTES="${3:-30}"
STAMP=$(date +%Y%m%d-%H%M%S)
LOG="$ROOT/stress-logs/detach-${STAMP}.log"
PIDFILE="$ROOT/stress-logs/run-30m.pid"

mkdir -p "$ROOT/stress-logs"
export SKIP_BREW=1

python3 - "$ROOT" "$HERE/stress-burnin-30m.sh" "$ROUTER" "$PASS" "$MINUTES" "$LOG" "$PIDFILE" <<'PY'
import os, subprocess, sys
root, script, router, pw, minutes, log_path, pidfile = sys.argv[1:8]
log = open(log_path, "a", buffering=1)
env = os.environ.copy()
env["SKIP_BREW"] = "1"
p = subprocess.Popen(
    [script, router, pw, minutes],
    cwd=root,
    stdout=log,
    stderr=subprocess.STDOUT,
    start_new_session=True,
)
with open(pidfile, "w") as f:
    f.write(str(p.pid) + "\n")
print(p.pid)
PY

echo "Burn-in PID $(cat "$PIDFILE") — log $LOG"
echo "Sample dir will appear under $ROOT/stress-logs/${ROUTER}_*"
