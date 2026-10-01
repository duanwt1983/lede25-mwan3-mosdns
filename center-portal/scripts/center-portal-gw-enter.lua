local session = ngx.var.cookie_authelia_session
if session == nil or session == "" then
    local host = ngx.var.http_host or ngx.var.host
    local rd = "https://" .. host .. ngx.var.request_uri
    return ngx.redirect("https://" .. host .. "/authelia/?rd=" .. ngx.escape_uri(rd))
end

local routes = dofile("/etc/nginx/lua/center-gw-routes.lua")
local id = ngx.var.gw_site_id
if not id or not routes[id] then
    return ngx.exit(404)
end
ngx.header["Set-Cookie"] = "center_gw=" .. id .. "; Path=/; Max-Age=86400; SameSite=Lax; Secure"
return ngx.redirect("/home/gw/" .. id .. "/cgi-bin/luci/")
