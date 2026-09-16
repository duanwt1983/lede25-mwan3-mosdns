param([string]$RouterIp = '192.168.8.1')
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
add-type @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy { public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; } }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
$ubusUrl = "https://$RouterIp/ubus"
$repoRoot = Split-Path $PSScriptRoot -Parent
$localMenu = Join-Path $repoRoot 'files\usr\share\luci\menu.d\zzz-luci-mwan3-tab.json'
$remoteMenu = '/usr/share/luci/menu.d/zzz-luci-mwan3-tab.json'

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
    return Invoke-Exec ("base64 -d '$tmp' > '$remotePath' && rm -f '$tmp' && wc -c '$remotePath'")
}

$token = (Invoke-UbusRaw '{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"password","timeout":300}]}')[1].ubus_rpc_session
Write-Output ("LOGIN_OK $RouterIp")
Write-RemoteFile $localMenu $remoteMenu | Write-Output
Invoke-Exec ("chmod 644 '$remoteMenu'") | Out-Null
Invoke-Exec 'rm -rf /tmp/luci-*' | Out-Null
Write-Output (Invoke-Exec "cat '$remoteMenu'")
Write-Output 'MENU_HOTFIX_DONE'
