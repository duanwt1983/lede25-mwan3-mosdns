#!/bin/sh
# LuCI ubus client for macOS (and other Unix hosts).
# Sourced by scripts/dev/*.sh. Needs curl, jq, and python3.
#
#   router_open IP PASSWORD
#   router_sh 'remote shell'
#   router_print [label]
#   router_put LOCAL REMOTE

router__need() {
	command -v curl >/dev/null 2>&1 || { echo "ubus.sh: curl is required" >&2; return 1; }
	command -v jq >/dev/null 2>&1 || { echo "ubus.sh: jq is required" >&2; return 1; }
	command -v python3 >/dev/null 2>&1 || { echo "ubus.sh: python3 is required" >&2; return 1; }
}

router__post() {
	_ubus_body=$(cat)
	_ubus_resp=$(curl -fsS -k --max-time "${UBUS_TIMEOUT:-180}" \
		-H 'Content-Type: application/json; charset=utf-8' \
		--data-binary "$_ubus_body" "$UBUS_URL") || return 1
	printf '%s' "$_ubus_resp" | jq -e 'if .error then error(.error | tostring) else .result end'
}

router_open() {
	router__need || return 1
	ROUTER_IP=$1
	ROUTER_PASS=${2:-password}
	UBUS_URL="https://${ROUTER_IP}/ubus"
	ROUTER_LAST=${TMPDIR:-/tmp}/lede-ubus-last.$$
	UBUS_TOKEN=$(
		jq -n --arg pass "$ROUTER_PASS" \
			'{jsonrpc:"2.0",id:1,method:"call",params:["00000000000000000000000000000000","session","login",{username:"root",password:$pass,timeout:600}]}' \
		| router__post \
		| jq -er 'if type=="array" then (.[1].ubus_rpc_session // .[1].data.ubus_rpc_session) else (.ubus_rpc_session // .data.ubus_rpc_session) end'
	) || return 1
	[ -n "$UBUS_TOKEN" ] && [ "$UBUS_TOKEN" != "null" ]
}

router_sh() {
	jq -n --arg token "$UBUS_TOKEN" --arg cmd "$1" \
		'{jsonrpc:"2.0",id:2,method:"call",params:[$token,"file","exec",{command:"/bin/sh",params:["-c",$cmd]}]}' \
	| router__post \
	| jq -c 'if type=="array" then .[1] else . end' > "$ROUTER_LAST"
}

router_stdout() {
	jq -r '.stdout // empty' "$ROUTER_LAST"
}

router_stderr() {
	jq -r '.stderr // empty' "$ROUTER_LAST"
}

router_code() {
	jq -r '.code // empty' "$ROUTER_LAST"
}

router_print() {
	_label=${1-}
	if [ -n "$_label" ]; then
		printf '=== %s ===\n' "$_label"
	fi
	printf 'code=%s\n' "$(router_code)"
	router_stdout
	_err=$(router_stderr)
	if [ -n "$_err" ]; then
		printf '%s\n' "$_err" >&2
	fi
}

# Copy a local file onto the router via ubus file.write (chunked).
# Text files lose CR. A third argument is a chmod mode such as 755.
router_put() {
	python3 - "$UBUS_URL" "$UBUS_TOKEN" "$1" "$2" "${UBUS_TIMEOUT:-180}" "${3-}" << 'PY'
import base64, json, ssl, sys, urllib.request
url, token, src, dest, timeout, mode = sys.argv[1:7]
timeout = int(timeout)
ctx = ssl._create_unverified_context()
data = open(src, "rb").read()
if b"\0" not in data:
    data = data.replace(b"\r\n", b"\n").replace(b"\r", b"\n")

def call(payload):
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, context=ctx, timeout=timeout) as resp:
        body = json.load(resp)
    if body.get("error"):
        raise SystemExit("ubus error: %s" % body["error"])
    return body["result"]

def sh(cmd):
    res = call({
        "jsonrpc": "2.0", "id": 2, "method": "call",
        "params": [token, "file", "exec", {"command": "/bin/sh", "params": ["-c", cmd]}],
    })
    info = res[1] if isinstance(res, list) and len(res) > 1 else res
    if not isinstance(info, dict):
        raise SystemExit("unexpected exec result: %s" % info)
    if info.get("code") not in (0, None):
        raise SystemExit("remote failed (%s): %s" % (info.get("code"), info.get("stderr") or info.get("stdout") or ""))

parent = dest.rsplit("/", 1)[0] or "/"
tmp, part = "/tmp/.lede-upload.bin", "/tmp/.lede-upload.part"
sh("mkdir -p '%s'; rm -f '%s' '%s'" % (parent.replace("'", "'\\''"), tmp, part))
chunk = 36000
if not data:
    pieces = [b""]
else:
    pieces = [data[i:i + chunk] for i in range(0, len(data), chunk)]
first = True
for piece in pieces:
    b64 = base64.b64encode(piece).decode("ascii")
    call({
        "jsonrpc": "2.0", "id": 11, "method": "call",
        "params": [token, "file", "write", {"path": part, "data": b64, "base64": True}],
    })
    if first:
        sh("mv -f '%s' '%s'" % (part, tmp))
        first = False
    else:
        sh("cat '%s' >> '%s'; rm -f '%s'" % (part, tmp, part))
sh("mv -f '%s' '%s'" % (tmp, dest.replace("'", "'\\''")))
if not mode and data.startswith(b"#!"):
    mode = "755"
if mode:
    sh("chmod %s '%s'" % (mode, dest.replace("'", "'\\''")))
print("UPLOADED %s (%d bytes)" % (dest, len(data)))
PY
}

# LuCI cgi-upload, with the same fallback paths the old Windows script used.
router_cgi_put() {
	python3 - "$ROUTER_IP" "$UBUS_TOKEN" "$1" "$2" "${UBUS_TIMEOUT:-180}" << 'PY'
import json, os, ssl, subprocess, sys, tempfile
ip, token, src, dest, timeout = sys.argv[1:6]
raw = open(src, "rb").read()
if b"\0" not in raw:
    raw = raw.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
mode = "0755" if (dest.startswith("/usr/libexec/") or dest.startswith("/etc/init.d/")) else "0644"
base = os.path.basename(dest)
candidates = [dest, "/overlay/upper" + dest, "/etc/luci-uploads/" + base]
fd, tmp = tempfile.mkstemp(prefix="lede-cgi-")
os.write(fd, raw)
os.close(fd)
last = ""
try:
    for cand in candidates:
        proc = subprocess.run(
            [
                "curl", "-fsS", "-k", "--max-time", timeout,
                "-F", "sessionid=" + token,
                "-F", "filename=" + cand,
                "-F", "filemode=" + mode,
                "-F", "filedata=@" + tmp + ";filename=blob",
                "https://%s/cgi-bin/cgi-upload" % ip,
            ],
            capture_output=True, text=True,
        )
        out = (proc.stdout or "") + (proc.stderr or "")
        bad = proc.returncode != 0 or (
            ("denied" in out or "failure" in out) and '"failure":[0' not in out.replace(" ", "")
        )
        if bad:
            last = out.strip() or ("curl exit %s" % proc.returncode)
            print("CGI_FAIL %s %s" % (cand, last))
            continue
        print("UPLOADED %s (%d bytes) %s" % (cand, len(raw), out.strip()))
        sys.exit(0)
    raise SystemExit("upload failed for %s : %s" % (dest, last))
finally:
    os.unlink(tmp)
PY
}
