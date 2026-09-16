# Pull topology layout + index.js from a live router into the local repo (dev only).
param(
    [string]$RouterIp = '192.168.8.1'
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
$outDir = Join-Path $repoRoot 'tmp-topo-pull'

function Invoke-UbusRaw($body) {
	$r = Invoke-RestMethod -Uri $base -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 120
	if ($r.error) { throw ($r.error | ConvertTo-Json -Compress) }
	return $r.result
}

function Invoke-Exec($token, $cmd) {
	$cmdEsc = $cmd -replace '\\','\\\\' -replace '"','\"'
	$body = "{`"jsonrpc`":`"2.0`",`"id`":3,`"method`":`"call`",`"params`":[`"$token`",`"file`",`"exec`",{`"command`":`"/bin/sh`",`"params`":[`"-c`",`"$cmdEsc`"]}]}"
	$r = Invoke-UbusRaw $body
	if ($r[1].code -ne 0) { throw ('exec failed: ' + ($r[1] | ConvertTo-Json -Compress)) }
	return $r[1].stdout
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$loginBody = '{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"password","timeout":300}]}'
$token = (Invoke-UbusRaw $loginBody)[1].ubus_rpc_session
Write-Output ("LOGIN_OK $RouterIp")

$layoutBody = "{`"jsonrpc`":`"2.0`",`"id`":2,`"method`":`"call`",`"params`":[`"$token`",`"wanmonitor`",`"layout_get`",{}]}"
$layout = (Invoke-UbusRaw $layoutBody)[1]
$layout | ConvertTo-Json -Depth 30 | Set-Content -Path (Join-Path $outDir 'layout.json') -Encoding UTF8

$rawLayout = Invoke-Exec $token 'cat /etc/lede-topo.json 2>/dev/null || echo {}'
$defaultPath = Join-Path $repoRoot 'files\etc\lede-topo.default.json'
$obj = $rawLayout | ConvertFrom-Json
$obj.lock = '0'
$obj | ConvertTo-Json -Depth 30 | Set-Content -Path $defaultPath -Encoding UTF8
Write-Output ("SYNC_LAYOUT " + $defaultPath)

$remoteIndex = Invoke-Exec $token 'cat /www/luci-static/resources/view/status/index.js'
$indexPath = Join-Path $repoRoot 'files\www\luci-static\resources\view\status\index.js'
Set-Content -Path $indexPath -Value $remoteIndex -Encoding UTF8
Write-Output ("SYNC_INDEX " + $indexPath + ' bytes=' + $remoteIndex.Length)

Write-Output 'SYNC_DONE'
