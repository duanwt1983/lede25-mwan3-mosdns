local uri = ngx.var.uri or ""
local id, tail = uri:match("^/home/gw/([a-zA-Z0-9_-]+)/?(.*)$")
if not id then
    return ngx.exit(ngx.HTTP_NOT_FOUND)
end

local routes = dofile("/etc/nginx/lua/center-gw-routes.lua")
local r = routes[id]
if not r then
    return ngx.exit(ngx.HTTP_NOT_FOUND)
end

ngx.var.gw_port = tostring(r.port)
ngx.var.gw_host = r.host or "192.168.9.1"
ngx.var.gw_pub_prefix = "/home/gw/" .. id .. "/"
ngx.header["Set-Cookie"] = "center_gw=" .. id .. "; Path=/; Max-Age=86400; SameSite=Lax; Secure"

if tail == nil or tail == "" then
    return ngx.redirect("/home/gw/" .. id .. "/cgi-bin/luci/")
end

local backend = tail
if backend:sub(1, 1) ~= "/" then
    backend = "/" .. backend
end
ngx.var.gw_backend_path = backend
