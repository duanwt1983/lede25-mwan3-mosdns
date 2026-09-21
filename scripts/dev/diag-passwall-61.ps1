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
echo "=== passwall enabled ==="
/etc/init.d/passwall enabled; echo enabled=$?
ls -la /etc/rc.d/*passwall* 2>&1
echo "=== passwall status ==="
/etc/init.d/passwall status 2>&1
echo "=== processes ==="
ps w | grep -iE 'passwall|xray|sing-box|v2ray|haproxy|dnsmasq|chinadns' | grep -v grep
echo "=== uci global ==="
uci show passwall 2>&1 | head -40
echo "=== start try ==="
/etc/init.d/passwall start 2>&1
sleep 2
/etc/init.d/passwall status 2>&1
echo "=== logread passwall ==="
logread | grep -iE 'passwall|xray|sing-box|v2ray|haproxy' | tail -40
echo "=== data mounts ==="
df -h /data /usr/share/passwall 2>&1
mount | grep -E 'passwall|/data'
echo "=== geodata ==="
ls -la /data/geodata /usr/share/xray 2>&1 | head -15
echo "=== opkg passwall ==="
opkg list-installed | grep -i passwall
'@
Write-Output (Exec $token $cmd).stdout
