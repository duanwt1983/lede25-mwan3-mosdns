# Deploy lede-data-setup GPT fix to 192.168.9.1 and run partition setup.
param(
    [string]$RouterIp = '192.168.9.1',
    [string]$Password = 'password'
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
$src = Join-Path $repoRoot 'files\usr\libexec\lede-data-setup'
if (-not (Test-Path $src)) { throw "missing $src" }
$content = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content -Raw -Encoding UTF8 $src)))

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

$token = (U ('{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"' + ($Password -replace '\\','\\' -replace '"','\"') + '","timeout":600}]}'))[1].ubus_rpc_session

Write-Host "Uploading lede-data-setup..."
$upload = @"
echo '$content' | base64 -d > /usr/libexec/lede-data-setup
chmod +x /usr/libexec/lede-data-setup
"@
$r = Exec $token $upload
if ($r.code -ne 0) { throw "upload failed: $($r.stderr)" }

Write-Host "Running lede-data-setup..."
$run = @'
/usr/libexec/lede-data-setup; echo setup-exit=$?
echo "=== log ==="
tail -20 /tmp/lede-data-setup.log
echo "=== lsblk ==="
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
echo "=== mount ==="
mount | grep " /data " || echo "/data not mounted"
'@
$r2 = Exec $token $run
Write-Output $r2.stdout
if ($r2.stderr) { Write-Output $r2.stderr }
