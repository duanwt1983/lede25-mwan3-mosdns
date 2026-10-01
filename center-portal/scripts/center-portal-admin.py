#!/usr/bin/env python3
"""Local admin API for portal site registry (127.0.0.1 only)."""
from __future__ import annotations

import json
import os
import re
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
ID_RE = re.compile(r"^[a-zA-Z0-9_-]{2,32}$")
DEFAULT_SERVER = "center.123.gd.cn"
DEFAULT_FRPS_PORT = 18007
TOKEN_RE = re.compile(r'^auth\.token\s*=\s*"([^"]+)"', re.M)
AUTHELIA_CFG = Path("/etc/authelia/configuration.yml")
AUTHELIA_INTERNAL = os.environ.get(
    "AUTHELIA_INTERNAL_URL", "http://127.0.0.1:9091/authelia"
)

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
    url = f"{AUTHELIA_INTERNAL.rstrip('/')}{api_path}"
    fwd_uri = f"/authelia{api_path}"
    headers = {
        "Host": host,
        "X-Forwarded-Proto": "https",
        "X-Forwarded-Host": f"{host}:{port}",
        "X-Forwarded-Uri": fwd_uri,
        "X-Original-URL": f"https://{host}:{port}{fwd_uri}",
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
    username = str(info.get("username") or "").strip()
    if not username:
        return None
    display = str(info.get("display_name") or username).strip()
    return {"username": username, "display_name": display}


def authelia_current_user(cookie_header: str) -> dict[str, str] | None:
    code, payload, _ = authelia_proxy("GET", "/api/user/info", cookie_header)
    if code != 200:
        return None
    return authelia_user_from_response(payload)


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
        user = authelia_current_user(cookie)
        if not user:
            self._json(401, {"ok": False, "error": "未登录或会话已过期"})
            return
        old_p = str(body.get("old_password") or "")
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
                "username": user["username"],
                "old_password": old_p,
                "new_password": new_p,
            }
        ).encode("utf-8")
        code, resp, _ = authelia_proxy("POST", "/api/change-password", cookie, payload)
        if code == 200:
            self._json(200, {"ok": True})
            return
        data = authelia_parse_json(resp)
        if isinstance(data, dict) and data.get("elevation") is True and not otc:
            authelia_proxy("POST", "/api/user/session/elevation", cookie)
            self._json(202, {"ok": False, "need_otc": True})
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
