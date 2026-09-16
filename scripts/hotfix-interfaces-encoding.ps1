# Fix mojibake in luci-mod-network interfaces.js on router
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
add-type @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy { public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; } }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

$ubusUrl = 'https://192.168.9.1/ubus'
$remote = '/www/luci-static/resources/view/network/interfaces.js'
$repoRoot = Split-Path $PSScriptRoot -Parent
$fixPy = Join-Path $repoRoot 'patches\luci-mod-network\fix-encoding.py'
$local = Join-Path $repoRoot 'tmp-hotfix-interfaces.js'

function Invoke-UbusRaw($body) {
    $r = Invoke-RestMethod -Uri $ubusUrl -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 120
    if ($r.error) { throw ($r.error | ConvertTo-Json -Compress) }
    return $r.result
}

function Invoke-Exec($cmd) {
    $cmdEsc = $cmd -replace '\\', '\\\\' -replace '"', '\"'
    $body = "{`"jsonrpc`":`"2.0`",`"id`":3,`"method`":`"call`",`"params`":[`"$token`",`"file`",`"exec`",{`"command`":`"/bin/sh`",`"params`":[`"-c`",`"$cmdEsc`"]}]}"
    $r = Invoke-UbusRaw $body
    if ($r[1].code -ne 0) { throw ('exec failed: ' + ($r[1] | ConvertTo-Json -Compress)) }
    return $r[1].stdout
}

function Write-RemoteFile($localPath, $remotePath) {
    $bytes = [System.IO.File]::ReadAllBytes($localPath)
    $b64 = [Convert]::ToBase64String($bytes)
    $tmp = '/tmp/lede-deploy-' + [System.IO.Path]::GetFileName($localPath) + '.b64'
    Invoke-Exec ("rm -f '$tmp' '$remotePath'") | Out-Null
    $chunk = 3000
    for ($i = 0; $i -lt $b64.Length; $i += $chunk) {
        $part = $b64.Substring($i, [Math]::Min($chunk, $b64.Length - $i))
        $partEsc = $part -replace '\\', '\\\\' -replace '"', '\"'
        Invoke-Exec ("printf '%s' `"$partEsc`" >> '$tmp'") | Out-Null
    }
    $dir = ($remotePath -replace '/[^/]+$', '')
    if ($dir) { Invoke-Exec ("mkdir -p '$dir'") | Out-Null }
    Invoke-Exec ("base64 -d '$tmp' > '$remotePath' && rm -f '$tmp' && wc -c '$remotePath'")
}

$loginBody = '{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"password","timeout":300}]}'
$script:token = (Invoke-UbusRaw $loginBody)[1].ubus_rpc_session
Write-Output 'LOGIN_OK'

$readBody = '{"jsonrpc":"2.0","id":2,"method":"call","params":["' + $token + '","file","read",{"path":"' + $remote + '","base64":true}]}'
$read = Invoke-UbusRaw $readBody
[System.IO.File]::WriteAllBytes($local, [Convert]::FromBase64String($read[1].data))
Write-Output ('FETCHED ' + (Get-Item $local).Length)

$fixed = $false
if (Test-Path $fixPy) {
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { $py = Get-Command python3 -ErrorAction SilentlyContinue }
    if ($py) {
        & $py.Source $fixPy $local
        $fixed = $true
    }
}
if (-not $fixed) {
    throw 'python not found; install Python to run patches/luci-mod-network/fix-encoding.py'
}

Write-Output 'DEPLOY'
Write-RemoteFile $local $remote | Write-Output
Invoke-Exec "grep -F 'Add device configuration...' '$remote' | wc -l" | ForEach-Object { Write-Output ("VERIFY addbtn: $_") }
Invoke-Exec "grep -F \"return _('Interfaces')+' / '+section_id\" '$remote' | wc -l" | ForEach-Object { Write-Output ("VERIFY title: $_") }
Invoke-Exec "rm -rf /tmp/luci-*" | Out-Null
Write-Output 'CACHE_CLEARED'
Write-Output 'HOTFIX_DONE'
