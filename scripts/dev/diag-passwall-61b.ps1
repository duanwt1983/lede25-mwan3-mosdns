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
echo "=== init head ==="
head -30 /etc/init.d/passwall
echo "=== which xray sing-box ==="
command -v xray; command -v sing-box; command -v chinadns-ng
ls -la /usr/bin/xray /usr/sbin/xray 2>&1
echo "=== mosdns ==="
/etc/init.d/mosdns status 2>&1; /etc/init.d/mosdns enabled; echo mosdns-enabled=$?
ps w | grep mosdns | grep -v grep
echo "=== manual start verbose ==="
sh -x /etc/init.d/passwall start 2>&1 | tail -50
sleep 3
ps w | grep -iE 'xray|sing-box|passwall|chinadns' | grep -v grep
echo "=== log tail ==="
logread | tail -30
echo "=== passwall rules bind ==="
mount | grep passwall; ls -la /usr/share/passwall/rules 2>&1 | head -10
ls -la /data/passwall/rules 2>&1 | head -10
'@
Write-Output (Exec $token $cmd).stdout
