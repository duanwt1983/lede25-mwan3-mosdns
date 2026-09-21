param([string]$RouterIp = '192.168.6.1', [string]$Password = 'password')
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
add-type @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy { public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; } }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$mountB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot 'files\usr\libexec\lede-data-mount'))))
$base = "https://$RouterIp/ubus"
function U($b) {
    $r = Invoke-RestMethod -Uri $base -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($b)) -TimeoutSec 120
    if ($r.error) { throw ($r.error | ConvertTo-Json -Compress) }
    return $r.result
}
function Exec($token, $cmd) {
    $esc = $cmd -replace '\\','\\' -replace '"','\"'
    $body = '{"jsonrpc":"2.0","id":2,"method":"call","params":["' + $token + '","file","exec",{"command":"/bin/sh","params":["-c","' + $esc + '"]}]}'
    return (U $body)[1]
}
$token = (U ('{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"' + ($Password -replace '\\','\\' -replace '"','\"') + '","timeout":600}]}'))[1].ubus_rpc_session
$cmd = "mkdir -p /usr/libexec; echo '$mountB64' | base64 -d > /usr/libexec/lede-data-mount; chmod +x /usr/libexec/lede-data-mount; grep -n 'mkdir -p /usr/share/xray' /usr/libexec/lede-data-mount"
Write-Output (Exec $token $cmd).stdout
