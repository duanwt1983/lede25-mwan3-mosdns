local session = ngx.var.cookie_authelia_session
if session == nil or session == "" then
    local host = ngx.var.http_host or ngx.var.host
    local rd = "https://" .. host .. ngx.var.request_uri
    return ngx.redirect("https://" .. host .. "/authelia/?rd=" .. ngx.escape_uri(rd))
end
