#!/usr/bin/env python3
"""Local admin API for portal site registry (127.0.0.1 only)."""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

HOST = "127.0.0.1"
PORT = 8765
SITES_PATH = Path("/var/www/center-portal/sites.json")
SYNC_CMD = Path("/opt/center-portal/center-portal-sync.sh")
TOKEN_FILE = Path("/etc/frp/frps.token")
FRPS_TOML = Path("/etc/frp/frps.toml")
CA_ROOT_CRT = Path("/etc/lede-center-ca/root-ca.crt")
CA_PUB_CRT = Path("/var/www/center-portal/ca/root-ca.crt")
ID_RE = re.compile(r"^[a-zA-Z0-9_-]{2,32}$")
DEFAULT_SERVER = "center.123.gd.cn"
DEFAULT_FRPS_PORT = 18007
TOKEN_RE = re.compile(r'^auth\.token\s*=\s*"([^"]+)"', re.M)
AUTHELIA_CFG = Path("/etc/authelia/configuration.yml")
AUTHELIA_INTERNAL = os.environ.get(
    "AUTHELIA_INTERNAL_URL", "http://127.0.0.1:9091/authelia"
)
DEFAULT_USERS_DB = Path("/etc/authelia/users_database.yml")
_authelia_bin: Path | None = None


def authelia_bin_path() -> Path:
    global _authelia_bin
    if _authelia_bin is not None:
        return _authelia_bin
    env = os.environ.get("AUTHELIA_BIN", "").strip()
    if env:
        p = Path(env)
        if p.is_file():
            _authelia_bin = p
            return p
    found = shutil.which("authelia")
    if found:
        _authelia_bin = Path(found)
        return _authelia_bin
    for candidate in (Path("/usr/local/bin/authelia"), Path("/usr/bin/authelia")):
        if candidate.is_file():
            _authelia_bin = candidate
            return candidate
    _authelia_bin = Path("/usr/local/bin/authelia")
    return _authelia_bin

# Ports bound by center OS / Baota / portal — must not be used for frp tunnel remotePort
RESERVED_CENTER_PORTS = frozenset({
    22, 80, 443, 8000, 8080, 8443, 8888, 9090, 9091, 8765, 18007, 18443, 7400, 7500,
})
TUNNEL_PORT_MIN = 19100
TUNNEL_PORT_MAX = 19999


def validate_tunnel_center_port(tport: int, sid: str, tname: str) -> None:
    if tport in RESERVED_CENTER_PORTS:
        raise ValueError(
            f"站点 {sid} 隧道 {tname}：中心端口 {tport} 已被中心机占用（如宝塔/Nginx），"
            f"请改用 {TUNNEL_PORT_MIN}–{TUNNEL_PORT_MAX}"
        )
    if tport < TUNNEL_PORT_MIN or tport > TUNNEL_PORT_MAX:
        raise ValueError(
            f"站点 {sid} 隧道 {tname}：中心端口 {tport} 不在建议范围 "
            f"{TUNNEL_PORT_MIN}–{TUNNEL_PORT_MAX}（19001–19099 留给 LuCI/SSH）"
        )


def read_registry() -> dict[str, Any]:
    if not SITES_PATH.is_file():
        return {"version": 1, "sites": []}
    with SITES_PATH.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("invalid registry root")
    sites = data.get("sites")
    if not isinstance(sites, list):
        data["sites"] = []
    data.setdefault("version", 1)
    return data


def validate_registry(data: dict[str, Any]) -> dict[str, Any]:
    if not isinstance(data, dict):
        raise ValueError("body must be an object")
    sites_in = data.get("sites")
    if not isinstance(sites_in, list):
        raise ValueError("sites must be an array")

    sites: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    seen_frp_ports: set[int] = set()

    for i, raw in enumerate(sites_in):
        if not isinstance(raw, dict):
            raise ValueError(f"sites[{i}] must be an object")
        sid = str(raw.get("id", "")).strip()
        name = str(raw.get("name", "")).strip()
        if not ID_RE.match(sid):
            raise ValueError(f"站点 ID 无效: {sid!r}（2–32 位字母数字 _ -）")
        if sid in seen_ids:
            raise ValueError(f"重复的站点 ID: {sid}")
        seen_ids.add(sid)
        if not name:
            raise ValueError(f"站点 {sid} 缺少名称")

        try:
            luci_port = int(raw.get("luci_port"))
        except (TypeError, ValueError) as e:
            raise ValueError(f"站点 {sid} 的 LuCI 端口无效") from e
        if not (1024 <= luci_port <= 65535):
            raise ValueError(f"站点 {sid} 的 LuCI 端口须在 1024–65535")
        if luci_port in seen_frp_ports:
            raise ValueError(f"LuCI 端口 {luci_port} 已被占用")
        seen_frp_ports.add(luci_port)

        ssh_raw = raw.get("ssh_port", 0)
        try:
            ssh_port = int(ssh_raw) if ssh_raw not in (None, "") else 0
        except (TypeError, ValueError) as e:
            raise ValueError(f"站点 {sid} 的 SSH 端口无效") from e
        if ssh_port != 0:
            if not (1024 <= ssh_port <= 65535):
                raise ValueError(f"站点 {sid} 的 SSH 端口须在 1024–65535 或 0")
            if ssh_port in seen_frp_ports:
                raise ValueError(f"SSH 端口 {ssh_port} 已被占用")
            seen_frp_ports.add(ssh_port)

        tags_raw = raw.get("tags") or []
        if isinstance(tags_raw, str):
            tags = [t.strip() for t in tags_raw.split(",") if t.strip()]
        elif isinstance(tags_raw, list):
            tags = [str(t).strip() for t in tags_raw if str(t).strip()]
        else:
            tags = []

        site = {
            "id": sid,
            "name": name,
            "region": str(raw.get("region") or "").strip(),
            "luci_port": luci_port,
            "ssh_port": ssh_port,
            "tags": tags,
        }
        luci_host = str(raw.get("luci_host") or "").strip()
        if luci_host:
            site["luci_host"] = luci_host
        note = str(raw.get("note") or "").strip()
        if note:
            site["note"] = note

        tunnels_in = raw.get("tunnels") or []
        if not isinstance(tunnels_in, list):
            raise ValueError(f"站点 {sid} 的 tunnels 须为数组")
        tunnels: list[dict[str, Any]] = []
        seen_tnames: set[str] = set()
        for j, tr in enumerate(tunnels_in):
            if not isinstance(tr, dict):
                raise ValueError(f"站点 {sid} tunnels[{j}] 须为对象")
            tname = str(tr.get("name", "")).strip()
            if not ID_RE.match(tname):
                raise ValueError(
                    f"站点 {sid} 隧道代理名无效: {tname!r}（2–32 位字母数字 _ -）"
                )
            if tname in seen_tnames:
                raise ValueError(f"站点 {sid} 重复的隧道代理名: {tname}")
            seen_tnames.add(tname)
            try:
                tport = int(tr.get("port"))
            except (TypeError, ValueError) as e:
                raise ValueError(f"站点 {sid} 隧道 {tname} 的中心端口无效") from e
            if not (1024 <= tport <= 65535):
                raise ValueError(f"站点 {sid} 隧道 {tname} 的中心端口须在 1024–65535")
            validate_tunnel_center_port(tport, sid, tname)
            if tport in seen_frp_ports:
                raise ValueError(f"中心端口 {tport} 已被占用（隧道 {sid}-{tname}）")
            seen_frp_ports.add(tport)
            tunnel: dict[str, Any] = {"name": tname, "port": tport}
            remark = str(tr.get("remark") or "").strip()
            if remark:
                tunnel["remark"] = remark
            local = str(tr.get("local") or "").strip()
            if local:
                tunnel["local"] = local
            tunnels.append(tunnel)
        if tunnels:
            site["tunnels"] = tunnels

        sites.append(site)

    return {"version": int(data.get("version") or 1), "sites": sites}


def write_registry(data: dict[str, Any]) -> None:
    SITES_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = SITES_PATH.with_suffix(".json.tmp")
    text = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(SITES_PATH)


def run_sync() -> None:
    if not SYNC_CMD.is_file():
        return
    proc = subprocess.run(
        [str(SYNC_CMD)],
        check=False,
        timeout=120,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip() or f"exit {proc.returncode}"
        raise RuntimeError(detail)


def authelia_public_host() -> str:
    env = os.environ.get("CENTER_PUBLIC_HOST", "").strip()
    if env:
        return env
    if AUTHELIA_CFG.is_file():
        text = AUTHELIA_CFG.read_text(encoding="utf-8")
        m = re.search(
            r"cookies:\s*\n(?:[^\n]*\n)*?\s*-\s*domain:\s*(\S+)",
            text,
        )
        if m:
            return m.group(1)
        m = re.search(r"^\s*domain:\s*(\S+)\s*$", text, re.M)
        if m:
            return m.group(1)
    return DEFAULT_SERVER


def center_frp_server() -> str:
    host = authelia_public_host()
    if not host or host.endswith(".example.com"):
        return DEFAULT_SERVER
    return host


def authelia_public_port() -> str:
    return os.environ.get("CENTER_PUBLIC_PORT", "18443").strip() or "18443"


def authelia_proxy(
    method: str, api_path: str, cookie_header: str, body: bytes | None = None
) -> tuple[int, bytes, str]:
    if not cookie_header or "authelia_session=" not in cookie_header:
        return 401, b'{"status":"KO","message":"not authenticated"}', "application/json"
    if not api_path.startswith("/api/"):
        return 400, b'{"status":"KO","message":"bad authelia path"}', "application/json"
    host = authelia_public_host()
    port = authelia_public_port()
    fwd_host = f"{host}:{port}"
    url = f"{AUTHELIA_INTERNAL.rstrip('/')}{api_path}"
    fwd_uri = f"/authelia{api_path}"
    headers = {
        "Host": fwd_host,
        "X-Forwarded-Proto": "https",
        "X-Forwarded-Host": fwd_host,
        "X-Forwarded-Uri": fwd_uri,
        "X-Original-URL": f"https://{fwd_host}{fwd_uri}",
        "Cookie": cookie_header,
    }
    if body is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return resp.status, resp.read(), resp.headers.get("Content-Type", "application/json")
    except urllib.error.HTTPError as e:
        return e.code, e.read(), e.headers.get("Content-Type", "application/json")


def authelia_parse_json(payload: bytes) -> Any:
    if not payload:
        return None
    try:
        return json.loads(payload.decode("utf-8"))
    except json.JSONDecodeError:
        return None


def authelia_user_from_response(payload: bytes) -> dict[str, str] | None:
    data = authelia_parse_json(payload)
    if not isinstance(data, dict):
        return None
    info = data.get("data") if data.get("status") == "OK" else data
    if not isinstance(info, dict):
        return None
    username = ""
    for key in ("username", "name", "login", "preferred_username"):
        if info.get(key):
            username = str(info[key]).strip()
            break
    display = str(info.get("display_name") or info.get("displayname") or username).strip()
    if not username and not display:
        return None
    return {"username": username, "display_name": display or username}


def authelia_session_ok(cookie_header: str) -> bool:
    code, _, _ = authelia_proxy("GET", "/api/user/info", cookie_header)
    return code == 200


def authelia_users_db_path() -> Path:
    if AUTHELIA_CFG.is_file():
        text = AUTHELIA_CFG.read_text(encoding="utf-8")
        m = re.search(
            r"authentication_backend:\s*\n\s*file:\s*\n\s*path:\s*(\S+)",
            text,
        )
        if m:
            return Path(m.group(1).strip("\"'"))
    return DEFAULT_USERS_DB


def read_file_backend_users() -> dict[str, dict[str, str]]:
    path = authelia_users_db_path()
    if not path.is_file():
        return {}
    text = path.read_text(encoding="utf-8")
    users: dict[str, dict[str, str]] = {}
    block = re.split(r"^users:\s*$", text, maxsplit=1, flags=re.M)
    if len(block) < 2:
        return users
    for m in re.finditer(
        r"^  ([a-zA-Z0-9_.-]+):\s*\n((?:    .+\n)*)",
        block[1],
        flags=re.M,
    ):
        uname = m.group(1)
        body = m.group(2)
        entry: dict[str, str] = {}
        for line in body.splitlines():
            kv = re.match(r"^\s{4}(\w+):\s*(.+)$", line)
            if kv:
                entry[kv.group(1)] = kv.group(2).strip().strip("\"'")
        users[uname] = entry
    return users


def portal_session_present(cookie_header: str) -> bool:
    return bool(cookie_header and "authelia_session=" in cookie_header)


def resolve_session_username(cookie_header: str, info_payload: bytes | None = None) -> str:
    users = read_file_backend_users()
    if not users:
        return ""
    if len(users) == 1:
        return next(iter(users))
    if info_payload is None:
        code, info_payload, _ = authelia_proxy("GET", "/api/user/info", cookie_header)
        if code != 200:
            return ""
    parsed = authelia_user_from_response(info_payload) or {}
    display = str(parsed.get("display_name") or "").strip()
    disp_l = display.lower()
    for uname, meta in users.items():
        dn = str(meta.get("displayname") or meta.get("display_name") or "").strip()
        if dn and dn.lower() == disp_l:
            return uname
        if uname.lower() == disp_l:
            return uname
    return ""


def authelia_verify_password(username: str, password: str) -> bool:
    """Same check Authelia uses at login (first factor)."""
    host = authelia_public_host()
    port = authelia_public_port()
    fwd_host = f"{host}:{port}"
    url = f"{AUTHELIA_INTERNAL.rstrip('/')}/api/firstfactor"
    fwd_uri = "/authelia/api/firstfactor"
    body = json.dumps(
        {
            "username": username,
            "password": password,
            "requestMethod": "GET",
            "keepMeLoggedIn": False,
        }
    ).encode("utf-8")
    headers = {
        "Host": fwd_host,
        "Content-Type": "application/json",
        "X-Forwarded-Proto": "https",
        "X-Forwarded-Host": fwd_host,
        "X-Forwarded-Uri": fwd_uri,
        "X-Original-URL": f"https://{fwd_host}{fwd_uri}",
    }
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = authelia_parse_json(resp.read())
            return (
                resp.status == 200
                and isinstance(data, dict)
                and data.get("status") == "OK"
            )
    except urllib.error.HTTPError:
        return False


def authelia_hash_validate(password: str, digest: str) -> bool:
    bin_path = authelia_bin_path()
    if not bin_path.is_file():
        return False
    cp = subprocess.run(
        [
            str(bin_path),
            "crypto",
            "hash",
            "validate",
            "--password",
            password,
            "--",
            digest,
        ],
        capture_output=True,
        text=True,
        timeout=60,
    )
    return cp.returncode == 0


def authelia_hash_generate(password: str) -> str:
    bin_path = authelia_bin_path()
    if not bin_path.is_file():
        raise RuntimeError(
            f"未找到 authelia 可执行文件（已查找 PATH 与 /usr/local/bin、/usr/bin），"
            f"请设置环境变量 AUTHELIA_BIN"
        )
    cp = subprocess.run(
        [
            str(bin_path),
            "crypto",
            "hash",
            "generate",
            "argon2",
            "--password",
            password,
        ],
        capture_output=True,
        text=True,
        timeout=60,
    )
    if cp.returncode != 0:
        raise RuntimeError((cp.stderr or cp.stdout or "生成密码哈希失败").strip())
    for line in (cp.stdout or "").splitlines():
        if line.startswith("Digest:"):
            return line.split(":", 1)[1].strip()
    digest = (cp.stdout or "").strip()
    if digest.startswith("$argon2"):
        return digest
    raise RuntimeError("无法解析 authelia 生成的密码哈希")


def file_backend_set_password(username: str, new_digest: str) -> None:
    path = authelia_users_db_path()
    text = path.read_text(encoding="utf-8")
    pattern = re.compile(
        rf"(^  {re.escape(username)}:\n(?:    .+\n)*?    password:\s*)(\"[^\"]+\"|\S+)",
        re.M,
    )
    if not pattern.search(text):
        raise ValueError(f"用户 {username} 不存在")
    quoted = json.dumps(new_digest)
    new_text = pattern.sub(rf"\1{quoted}", text, count=1)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(new_text, encoding="utf-8")
    tmp.replace(path)


def file_backend_change_password(cookie_header: str, old_p: str, new_p: str) -> tuple[int, str]:
    if not portal_session_present(cookie_header):
        return 401, "未登录或会话已过期"
    username = resolve_session_username(cookie_header)
    if not username:
        return 400, "无法识别当前登录用户，请联系管理员"
    users = read_file_backend_users()
    meta = users.get(username)
    if not meta:
        return 400, f"用户 {username} 不存在"
    if not authelia_verify_password(username, old_p):
        digest = meta.get("password") or ""
        if not digest or not authelia_hash_validate(old_p, digest):
            return 401, "当前密码不正确"
    if len(new_p) < 8:
        return 400, "新密码至少 8 位"
    try:
        new_digest = authelia_hash_generate(new_p)
        file_backend_set_password(username, new_digest)
    except ValueError as e:
        return 400, str(e)
    except OSError as e:
        return 500, f"写入用户数据库失败: {e}"
    except RuntimeError as e:
        return 500, str(e)
    subprocess.run(
        ["systemctl", "try-restart", "authelia"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    return 200, ""


def authelia_current_user(cookie_header: str) -> dict[str, str] | None:
    if not portal_session_present(cookie_header):
        return None
    username = resolve_session_username(cookie_header)
    display = ""
    code, payload, _ = authelia_proxy("GET", "/api/user/info", cookie_header)
    if code == 200:
        info = authelia_user_from_response(payload)
        if info:
            display = str(info.get("display_name") or "").strip()
            if not username and info.get("username"):
                username = str(info["username"]).strip()
    if not username:
        return None
    if not display:
        users = read_file_backend_users()
        meta = users.get(username) or {}
        display = str(meta.get("displayname") or meta.get("display_name") or username).strip()
    return {"username": username, "display_name": display or username}


def read_frp_token() -> str:
    if TOKEN_FILE.is_file():
        line = TOKEN_FILE.read_text(encoding="utf-8").strip().splitlines()[0].strip()
        if line:
            return line
    if FRPS_TOML.is_file():
        text = FRPS_TOML.read_text(encoding="utf-8")
        m = TOKEN_RE.search(text)
        if m:
            return m.group(1)
    return ""


def read_ca_bootstrap(pub: str, pub_port: str) -> dict[str, Any]:
    path = CA_ROOT_CRT if CA_ROOT_CRT.is_file() else CA_PUB_CRT
    if not path.is_file():
        return {
            "ca_available": False,
            "ca_cert_url": "",
            "ca_cert_sha256": "",
        }
    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    return {
        "ca_available": True,
        "ca_cert_url": f"https://{pub}:{pub_port}/home/ca/root-ca.crt",
        "ca_cert_sha256": digest,
        "ca_gateway_path": "/etc/lede-center/frps-ca.crt",
    }


def read_bootstrap() -> dict[str, Any]:
    token = read_frp_token()
    if not token:
        raise ValueError("未找到 frps 认证 Token，请检查 /etc/frp/frps.token")
    pub = center_frp_server()
    pub_port = authelia_public_port()
    return {
        "server": pub,
        "port": DEFAULT_FRPS_PORT,
        "token": token,
        "tls": True,
        "portal_url": f"https://{pub}:{pub_port}/",
        "tunnel_port_min": TUNNEL_PORT_MIN,
        "tunnel_port_max": TUNNEL_PORT_MAX,
        "reserved_center_ports": sorted(RESERVED_CENTER_PORTS),
        **read_ca_bootstrap(pub, pub_port),
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "center-portal-admin/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _json(self, code: int, payload: Any) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> Any:
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            raise ValueError("empty body")
        if length > 256 * 1024:
            raise ValueError("body too large")
        raw = self.rfile.read(length)
        return json.loads(raw.decode("utf-8"))

    def _proxy_authelia(self, method: str, api_path: str, body: bytes | None = None) -> None:
        cookie = self.headers.get("Cookie", "")
        code, payload, ctype = authelia_proxy(method, api_path, cookie, body)
        self.send_response(code)
        self.send_header("Content-Type", ctype.split(";")[0])
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def _account_me(self) -> None:
        cookie = self.headers.get("Cookie", "")
        user = authelia_current_user(cookie)
        if not user:
            self._json(401, {"ok": False, "error": "未登录或会话已过期"})
            return
        disabled = False
        code, cfg_body, _ = authelia_proxy("GET", "/api/configuration", cookie)
        if code == 200:
            cfg = authelia_parse_json(cfg_body)
            if isinstance(cfg, dict):
                inner = cfg.get("data") if cfg.get("status") == "OK" else cfg
                if isinstance(inner, dict):
                    disabled = bool(inner.get("password_change_disabled"))
        self._json(200, {"ok": True, **user, "password_change_disabled": disabled})

    def _account_change_password(self, body: dict[str, Any]) -> None:
        cookie = self.headers.get("Cookie", "")
        if not portal_session_present(cookie):
            self._json(401, {"ok": False, "error": "未登录或会话已过期"})
            return
        user = authelia_current_user(cookie) or {"username": "", "display_name": ""}
        username = str(body.get("username") or user.get("username") or "").strip()
        old_p = str(body.get("old_password") or body.get("password") or "")
        new_p = str(body.get("new_password") or "")
        otc = str(body.get("otc") or "").replace(" ", "")
        if not old_p or not new_p:
            raise ValueError("请填写当前密码和新密码")
        if otc:
            vcode, vbody, _ = authelia_proxy(
                "PUT",
                "/api/user/session/elevation",
                cookie,
                json.dumps({"otc": otc}).encode("utf-8"),
            )
            vdata = authelia_parse_json(vbody)
            if vcode != 200 or not isinstance(vdata, dict) or vdata.get("status") != "OK":
                self._json(400, {"ok": False, "error": "邮箱验证码错误或已失效"})
                return
        payload = json.dumps(
            {
                "username": username,
                "old_password": old_p,
                "new_password": new_p,
            }
        ).encode("utf-8")
        code, resp, _ = authelia_proxy("POST", "/api/change-password", cookie, payload)
        # Authelia < 4.39 has no /api/change-password — use user portal API.
        if code in (404, 405):
            legacy = json.dumps({"password": old_p, "new_password": new_p}).encode("utf-8")
            code, resp, _ = authelia_proxy("PUT", "/api/user/password", cookie, legacy)
        if code in (404, 405):
            fb_code, fb_err = file_backend_change_password(cookie, old_p, new_p)
            if fb_code == 200:
                self._json(200, {"ok": True})
                return
            self._json(fb_code, {"ok": False, "error": fb_err})
            return
        if not username:
            username = resolve_session_username(cookie)
        if code == 200:
            self._json(200, {"ok": True})
            return
        data = authelia_parse_json(resp)
        if isinstance(data, dict) and data.get("elevation") is True and not otc:
            authelia_proxy("POST", "/api/user/session/elevation", cookie)
            otc_delivery = "filesystem"
            if AUTHELIA_CFG.is_file():
                txt = AUTHELIA_CFG.read_text(encoding="utf-8")
                if re.search(r"^\s*smtp:", txt, re.M):
                    otc_delivery = "email"
            self._json(
                202,
                {"ok": False, "need_otc": True, "otc_delivery": otc_delivery},
            )
            return
        if code == 401:
            self._json(401, {"ok": False, "error": "当前密码不正确"})
            return
        if code == 400:
            self._json(400, {"ok": False, "error": "新密码不符合策略要求"})
            return
        msg = "修改密码失败"
        if isinstance(data, dict) and data.get("message"):
            msg = str(data["message"])
        self._json(code if 400 <= code < 600 else 500, {"ok": False, "error": msg})

    def do_GET(self) -> None:
        if self.path.rstrip("/") == "/account/me":
            try:
                self._account_me()
            except Exception as e:
                self._json(500, {"ok": False, "error": str(e)})
            return
        if self.path.startswith("/account/authelia/"):
            api_path = "/" + self.path.split("/account/authelia/", 1)[1].split("?", 1)[0]
            self._proxy_authelia("GET", api_path)
            return
        if self.path.rstrip("/") == "/sites":
            try:
                self._json(200, read_registry())
            except Exception as e:
                self._json(500, {"ok": False, "error": str(e)})
            return
        if self.path.rstrip("/") == "/bootstrap":
            try:
                self._json(200, {"ok": True, **read_bootstrap()})
            except Exception as e:
                self._json(500, {"ok": False, "error": str(e)})
            return
        if self.path.rstrip("/") == "/health":
            self._json(200, {"ok": True})
            return
        self._json(404, {"ok": False, "error": "not found"})

    def do_POST(self) -> None:
        if self.path.rstrip("/") == "/account/password":
            try:
                body = self._read_json()
                if not isinstance(body, dict):
                    raise ValueError("invalid body")
                self._account_change_password(body)
            except ValueError as e:
                self._json(400, {"ok": False, "error": str(e)})
            except Exception as e:
                self._json(500, {"ok": False, "error": str(e)})
            return
        if self.path.startswith("/account/authelia/"):
            api_path = "/" + self.path.split("/account/authelia/", 1)[1].split("?", 1)[0]
            try:
                body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            except (TypeError, ValueError):
                body = b""
            self._proxy_authelia("POST", api_path, body or None)
            return
        self._json(404, {"ok": False, "error": "not found"})

    def do_PUT(self) -> None:
        if self.path.startswith("/account/authelia/"):
            api_path = "/" + self.path.split("/account/authelia/", 1)[1].split("?", 1)[0]
            try:
                body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            except (TypeError, ValueError):
                body = b""
            self._proxy_authelia("PUT", api_path, body or None)
            return
        if self.path.rstrip("/") != "/sites":
            self._json(404, {"ok": False, "error": "not found"})
            return
        try:
            body = self._read_json()
            reg = validate_registry(body)
            write_registry(reg)
            run_sync()
            self._json(200, {"ok": True, "registry": reg})
        except ValueError as e:
            self._json(400, {"ok": False, "error": str(e)})
        except RuntimeError as e:
            self._json(500, {"ok": False, "error": "nginx sync failed", "detail": str(e)})
        except Exception as e:
            self._json(500, {"ok": False, "error": str(e)})

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self.end_headers()


def main() -> None:
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"center-portal-admin listening on {HOST}:{PORT}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
