# Hotfix WAN interface bandwidth fields: Mbps unit + move to end of general tab
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
add-type @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy { public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; } }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

$ubusUrl = 'https://192.168.9.1/ubus'
$repoRoot = Split-Path $PSScriptRoot -Parent
$root = Join-Path $repoRoot 'files\www\luci-static\resources'

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
    $n = 0
    for ($i = 0; $i -lt $b64.Length; $i += $chunk) {
        $part = $b64.Substring($i, [Math]::Min($chunk, $b64.Length - $i))
        $partEsc = $part -replace '\\', '\\\\' -replace '"', '\"'
        Invoke-Exec ("printf '%s' `"$partEsc`" >> '$tmp'") | Out-Null
        $n++
        if (($n % 10) -eq 0) { Start-Sleep -Milliseconds 150 }
    }
    $dir = ($remotePath -replace '/[^/]+$', '')
    if ($dir) { Invoke-Exec ("mkdir -p '$dir'") | Out-Null }
    return Invoke-Exec ("base64 -d '$tmp' > '$remotePath' && rm -f '$tmp' && wc -c '$remotePath'")
}

$loginBody = '{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"password","timeout":300}]}'
$script:token = (Invoke-UbusRaw $loginBody)[1].ubus_rpc_session
Write-Output 'LOGIN_OK'

# Patch interfaces.js: move bwExtra.attach after renderFormOptions
$ifaceRemote = '/www/luci-static/resources/view/network/interfaces.js'
$ifaceLocal = Join-Path $env:TEMP 'lede-interfaces.js'
$raw = Invoke-Exec "cat '$ifaceRemote'"
[System.IO.File]::WriteAllText($ifaceLocal, $raw, [System.Text.UTF8Encoding]::new($false))

$attachRe = [regex]'if\s*\(\s*typeof\s+bwExtra\s*!=\s*''undefined''\s*&&\s*bwExtra\.attach\s*\)\s*bwExtra\.attach\s*\(\s*s\s*,\s*ifc\s*\)\s*;'
$raw = $attachRe.Replace($raw, '', 1)
$raw = [regex]::Replace($raw, 'ifc\.renderFormOptions\(s\);if\s*\(\s*typeof\s+bwExtra[^;]+;', 'ifc.renderFormOptions(s);', 1)
if ($attachRe.IsMatch($raw)) { throw 'old bwExtra block still present' }
if ($raw -notmatch 'renderFormOptions\(s\);if\(typeof bwExtra') {
    $raw = [regex]::Replace($raw, '(ifc\.renderFormOptions\(s\);)', '$1if(typeof bwExtra!=''undefined''&&bwExtra.attach) bwExtra.attach(s,ifc);', 1)
}
if ($raw -notmatch 'bwExtra\.attach\(s,ifc\)') { throw 'failed to attach bwExtra after renderFormOptions' }
$beforeStatus = ($raw -split '_ifacestat_modal', 2)[0]
if ($beforeStatus -match 'bwExtra\.attach\(s,ifc\)') { throw 'bwExtra still before status block' }
[System.IO.File]::WriteAllText($ifaceLocal, $raw, [System.Text.UTF8Encoding]::new($false))
Write-Output ("PATCHED " + $raw.Length)

$files = @(
    @{ local = Join-Path $root 'view\network\iface-bw-extra.js'; remote = '/www/luci-static/resources/view/network/iface-bw-extra.js' },
    @{ local = Join-Path $root 'view\status\index.js'; remote = '/www/luci-static/resources/view/status/index.js' },
    @{ local = $ifaceLocal; remote = $ifaceRemote }
)

foreach ($f in $files) {
    if (-not (Test-Path $f.local)) { throw "missing: $($f.local)" }
    Write-Output ("DEPLOY " + $f.local + ' -> ' + $f.remote)
    Write-RemoteFile $f.local $f.remote | Write-Output
}

Invoke-Exec "grep -o 'bwExtra.attach(s,ifc)' '$ifaceRemote' | wc -l" | ForEach-Object { Write-Output ("VERIFY bwExtra.attach call count: $_") }
Invoke-Exec "grep -o 'renderFormOptions(s);if(typeof bwExtra' '$ifaceRemote' | wc -l" | ForEach-Object { Write-Output ("VERIFY attach after renderFormOptions: $_") }
Invoke-Exec "grep -o 'Mbit' '$ifaceRemote' /www/luci-static/resources/view/network/iface-bw-extra.js 2>/dev/null | wc -l" | ForEach-Object { Write-Output ("VERIFY Mbit refs in deployed iface files: $_") }
Invoke-Exec "rm -rf /tmp/luci-*" | Out-Null
Write-Output 'CACHE_CLEARED'
Write-Output 'HOTFIX_DONE'
