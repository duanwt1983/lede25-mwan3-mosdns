# Deploy PushPlus site prefix to 192.168.6.1 gateway.
param(
    [string]$RouterIp = '192.168.6.1',
    [string]$Password = 'password',
    [string]$SitePrefix = '6.1网点'
)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
add-type @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy { public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; } }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

$base = "https://$RouterIp/ubus"
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$filesRoot = Join-Path $repoRoot 'files'

function U($b) {
    $r = Invoke-RestMethod -Uri $base -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($b)) -TimeoutSec 180
    if ($r.error) { throw ($r.error | ConvertTo-Json -Compress) }
    return $r.result
}
function Exec($token, $cmd) {
    $esc = $cmd -replace '\\','\\' -replace '"','\"'
    $body = '{"jsonrpc":"2.0","id":2,"method":"call","params":["' + $token + '","file","exec",{"command":"/bin/sh","params":["-c","' + $esc + '"]}]}'
    return (U $body)[1]
}
function Upload($token, $local, $remote) {
    $text = [IO.File]::ReadAllText($local) -replace "`r`n","`n" -replace "`r","`n"
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))
    $dir = ($remote -replace '/[^/]+$','')
    $prep = "mkdir -p '$dir'; echo '$b64' | base64 -d > '$remote'"
    $r = Exec $token $prep
    if ($r.code -ne 0) { throw "upload failed: $($r.stderr)" }
    Write-Output "UPLOADED $remote"
}

$token = (U ('{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"' + ($Password -replace '\\','\\' -replace '"','\"') + '","timeout":600}]}'))[1].ubus_rpc_session

Upload $token (Join-Path $filesRoot 'usr\libexec\wan-alert') '/usr/libexec/wan-alert'
Upload $token (Join-Path $filesRoot 'www\luci-static\resources\view\status\alertmap.js') '/www/luci-static/resources/view/status/alertmap.js'

$prefixB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($SitePrefix))
$prep = @'
chmod 755 /usr/libexec/wan-alert
sed -i 's/\r$//' /usr/libexec/wan-alert /www/luci-static/resources/view/status/alertmap.js
uci -q get wanalert.main.pushplus_prefix >/dev/null || uci set wanalert.main.pushplus_prefix=
'@ + "uci set wanalert.main.pushplus_prefix=`"$(echo '$prefixB64' | base64 -d)`"`n" + @'
uci commit wanalert
rm -f /tmp/wan-alert.lock
/etc/init.d/wanalert restart
sleep 1
grep -c pushplus_prefix /usr/libexec/wan-alert
grep -c pushplus_prefix /www/luci-static/resources/view/status/alertmap.js
uci -q get wanalert.main.pushplus_prefix
/usr/sbin/wan-alert test manual 2>&1 | tail -5
"@
$r = Exec $token $prep
Write-Output $r.stdout
if ($r.stderr) { Write-Output $r.stderr }
