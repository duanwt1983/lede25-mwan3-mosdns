param([string[]]$RouterIps = @('192.168.8.1', '192.168.6.1'), [string]$Password = 'password')
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
add-type @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy { public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; } }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

function Query($ip) {
    $base = "https://$ip/ubus"
    function U($b) {
        $r = Invoke-RestMethod -Uri $base -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($b)) -TimeoutSec 60
        if ($r.error) { throw ($r.error | ConvertTo-Json -Compress) }
        return $r.result
    }
    function Exec($token, $cmd) {
        $esc = $cmd -replace '\\','\\' -replace '"','\"'
        $body = '{"jsonrpc":"2.0","id":2,"method":"call","params":["' + $token + '","file","exec",{"command":"/bin/sh","params":["-c","' + $esc + '"]}]}'
        return (U $body)[1]
    }
    $token = (U ('{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"' + ($Password -replace '\\','\\' -replace '"','\"') + '","timeout":60}]}'))[1].ubus_rpc_session
    $cmd = @'
echo keyword=$(uci -q get wanalert.main.keyword)
echo extra_text=$(uci -q get wanalert.main.extra_text)
echo pushplus_prefix=$(uci -q get wanalert.main.pushplus_prefix)
grep -nE 'SHYX|晋城' /etc/config/wanalert /usr/libexec/wan-alert 2>/dev/null || echo repo-hardcode=not-found-on-device
'@
    $r = Exec $token $cmd
    Write-Output "=== $ip ==="
    Write-Output $r.stdout
}

foreach ($ip in $RouterIps) {
    try { Query $ip } catch { Write-Output "=== $ip FAILED: $($_.Exception.Message) ===" }
}
