# Deploy topology overview (index.js) to 192.168.6.1.
param(
    [string]$RouterIp = '192.168.6.1',
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
$local = Join-Path $repoRoot 'files\www\luci-static\resources\view\status\index.js'
$remote = '/www/luci-static/resources/view/status/index.js'

function U($b) {
    $r = Invoke-RestMethod -Uri $base -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($b)) -TimeoutSec 300
    if ($r.error) { throw ($r.error | ConvertTo-Json -Compress) }
    return $r.result
}
function Exec($token, $cmd) {
    $esc = $cmd -replace '\\','\\' -replace '"','\"'
    $body = '{"jsonrpc":"2.0","id":2,"method":"call","params":["' + $token + '","file","exec",{"command":"/bin/sh","params":["-c","' + $esc + '"]}]}'
    return (U $body)[1]
}
function Upload($token, $path, $dest) {
    $text = [IO.File]::ReadAllText($path) -replace "`r`n","`n" -replace "`r","`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $dir = ($dest -replace '/[^/]+$','')
    $tmp = '/tmp/.lede-upload.bin'
    $part = '/tmp/.lede-upload.part'
    Exec $token "mkdir -p '$dir'; rm -f '$tmp' '$part'" | Out-Null
    $chunkSize = 48000
    for ($i = 0; $i -lt $bytes.Length; $i += $chunkSize) {
        $n = [Math]::Min($chunkSize, $bytes.Length - $i)
        $slice = New-Object byte[] $n
        [Array]::Copy($bytes, $i, $slice, 0, $n)
        $b64 = [Convert]::ToBase64String($slice)
        $writeObj = @{
            jsonrpc = '2.0'; id = 11; method = 'call'
            params = @($token, 'file', 'write', @{ path = $part; data = $b64; base64 = $true })
        }
        U ($writeObj | ConvertTo-Json -Depth 6 -Compress) | Out-Null
        if ($i -eq 0) { Exec $token "mv -f '$part' '$tmp'" | Out-Null }
        else { Exec $token "cat '$part' >> '$tmp'; rm -f '$part'" | Out-Null }
    }
    $r = Exec $token "mv -f '$tmp' '$dest'"
    if ($r.code -ne 0) { throw "upload failed: $($r.stderr)" }
    Write-Output "UPLOADED $dest ($($bytes.Length) bytes)"
}

$token = (U ('{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"' + ($Password -replace '\\','\\' -replace '"','\"') + '","timeout":600}]}'))[1].ubus_rpc_session
Write-Output "LOGIN_OK $RouterIp"
Upload $token $local $remote
$verify = @'
sed -i "s/\r$//" /www/luci-static/resources/view/status/index.js
grep -c "LINK_IDLE_BPS" /www/luci-static/resources/view/status/index.js
grep -c "flowShouldIdle" /www/luci-static/resources/view/status/index.js
wc -c /www/luci-static/resources/view/status/index.js
ip -4 addr show br-lan 2>/dev/null | awk "/inet /{print \"LAN \" \$2}"
'@
$r = Exec $token $verify
Write-Output $r.stdout
if ($r.stderr) { Write-Output $r.stderr }
