param([string]$RouterIp = '192.168.6.1', [string]$Password = 'password')
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
add-type @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy { public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; } }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
$url = "https://$RouterIp/ubus"
function U($b) {
    $r = Invoke-RestMethod -Uri $url -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($b)) -TimeoutSec 120
    if ($r.error) { throw ($r.error | ConvertTo-Json -Compress) }
    return $r.result
}
function Exec($token, $cmd) {
    $esc = $cmd -replace '\\','\\' -replace '"','\"'
    $body = '{"jsonrpc":"2.0","id":2,"method":"call","params":["' + $token + '","file","exec",{"command":"/bin/sh","params":["-c","' + $esc + '"]}]}'
    return (U $body)[1]
}
$token = (U ('{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"' + ($Password -replace '\\','\\' -replace '"','\"') + '","timeout":600}]}'))[1].ubus_rpc_session
$cmd = @'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
echo "=== passwall status ==="
/etc/init.d/passwall status 2>&1
echo "=== processes ==="
ps w | grep -iE 'xray|passwall|sing-box|chinadns' | grep -v grep
echo "=== geodata bind ==="
ls -la /usr/share/xray 2>&1 | head -5
mount | grep xray
echo "=== nft passwall ==="
nft list table inet passwall 2>&1 | head -10
echo "=== curl test ==="
curl -4 -sS -m 10 -o /dev/null -w "google http=%{http_code} time=%{time_total}\n" https://www.google.com 2>&1 || echo curl_failed
'@
Write-Output (Exec $token $cmd).stdout
