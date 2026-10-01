local session = ngx.var.cookie_authelia_session
if session == nil or session == "" then
    local host = ngx.var.http_host or ngx.var.host
    local rd = "https://" .. host .. ngx.var.request_uri
    return ngx.redirect("https://" .. host .. "/authelia/?rd=" .. ngx.escape_uri(rd))
end

local function resolve_site_id()
    local id = ngx.var.gw_site_id
    if id and id ~= "" then
        return id
    end
    id = ngx.var.cookie_center_gw
    if id and id ~= "" then
        return id
    end
    local referer = ngx.var.http_referer or ""
    id = referer:match("/home/gw/([a-zA-Z0-9_-]+)/")
    if id then
        return id
    end
    return nil
end

local routes = dofile("/etc/nginx/lua/center-gw-routes.lua")
local id = resolve_site_id()
if id == nil or id == "" then
    ngx.header.content_type = "text/html; charset=utf-8"
    ngx.status = ngx.HTTP_FORBIDDEN
    ngx.say([[
<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8"><title>无法打开网关 LuCI</title></head>
<body style="font-family:sans-serif;max-width:36em;margin:2em auto;line-height:1.5">
<h1>无法打开网关 LuCI</h1>
<p>请从门户点击「打开 LuCI」，或访问 <code>/home/gw/&lt;站点ID&gt;/</code>（例如 <a href="/home/gw/t1/">/home/gw/t1/</a>）。</p>
<p>不要直接访问根路径 <code>/cgi-bin/luci/</code>。</p>
</body></html>
]])
    return ngx.exit(ngx.HTTP_FORBIDDEN)
end
local r = routes[id]
if not r then
    return ngx.exit(ngx.HTTP_NOT_FOUND)
end
ngx.var.gw_port = tostring(r.port)
ngx.var.gw_host = r.host or "192.168.9.1"
ngx.var.gw_pub_prefix = "/home/gw/" .. id .. "/"
