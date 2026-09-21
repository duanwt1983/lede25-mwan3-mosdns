# Diagnose and fix PassWall on 6.1 (geodata bind, mosdns, enable/start).
param([string]$RouterIp = '192.168.6.1', [string]$Password = 'password')
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
add-type @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy { public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; } }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
$base = "https://$RouterIp/ubus"
function U($b) {
    $r = Invoke-RestMethod -Uri $base -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($b)) -TimeoutSec 180
    if ($r.error) { throw ($r.error | ConvertTo-Json -Compress) }
    return $r.result
}
function Exec($token, $cmd) {
    $esc = $cmd -replace '\\','\\' -replace '"','\"'
    $body = '{"jsonrpc":"2.0","id":2,"method":"call","params":["' + $token + '","file","exec",{"command":"/bin/sh","params":["-c","' + $esc + '"]}]}'
    $r = (U $body)[1]
    if ($r.code -ne 0) { Write-Host "WARN exit $($r.code)" -ForegroundColor Yellow }
    return $r
}
$token = (U ('{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"' + ($Password -replace '\\','\\' -replace '"','\"') + '","timeout":600}]}'))[1].ubus_rpc_session

function Show($label, $r) {
    Write-Host "`n=== $label ===" -ForegroundColor Cyan
    if ($r.stdout) { Write-Output $r.stdout }
    if ($r.stderr) { Write-Host $r.stderr -ForegroundColor DarkYellow }
}

Show 'before' (Exec $token 'export PATH=/usr/sbin:/sbin:/usr/bin:/bin; df -h /data; ls -la /data/geodata 2>&1 | head -5; ls -la /usr/share/xray 2>&1; mount | grep -E "xray|passwall|/data"; opkg list-installed | grep -iE "xray|passwall|sing-box|chinadns"; ps w | grep -iE "xray|passwall|mosdns|sing-box" | grep -v grep')

Show 'init' (Exec $token 'export PATH=/usr/sbin:/sbin:/usr/bin:/bin; wc -l /etc/init.d/passwall; head -5 /etc/init.d/passwall; file /etc/init.d/passwall 2>/dev/null; /etc/init.d/passwall enabled; echo enabled_exit=$?; ls -la /etc/rc.d/*passwall* 2>&1')

Show 'fix geodata bind' (Exec $token @'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
mkdir -p /data/geodata /usr/share/xray
[ -f /data/geodata/geoip.dat ] || echo "WARN: missing geoip.dat"
[ -f /data/geodata/geosite.dat ] || echo "WARN: missing geosite.dat"
if ! mount | grep -q " /usr/share/xray "; then
  mount --bind /data/geodata /usr/share/xray && echo "bind ok" || echo "bind failed"
fi
ls -la /usr/share/xray 2>&1 | head -5
if [ -x /usr/libexec/lede-data-mount ]; then
  /usr/libexec/lede-data-mount bind
fi
mount | grep -E "xray|passwall"
'@)

Show 'mosdns' (Exec $token 'export PATH=/usr/sbin:/sbin:/usr/bin:/bin; uci get mosdns.config.enabled 2>&1; /etc/init.d/mosdns enabled; echo mosdns_enabled_exit=$?; /etc/init.d/mosdns start 2>&1; sleep 1; netstat -lntp 2>/dev/null | grep 5335 || ss -lntp | grep 5335')

Show 'passwall enable+start' (Exec $token @'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
uci show passwall.@global[0].enabled 2>&1
/etc/init.d/passwall enable
/etc/init.d/passwall enabled; echo enabled_exit=$?
/etc/init.d/passwall stop 2>&1 || true
/etc/init.d/passwall start 2>&1
sleep 5
ps w | grep -iE "xray|passwall|sing-box|chinadns|haproxy" | grep -v grep
[ -f /tmp/log/passwall.log ] && tail -30 /tmp/log/passwall.log
logread | tail -20
'@)

Write-Host "`nDone." -ForegroundColor Green
