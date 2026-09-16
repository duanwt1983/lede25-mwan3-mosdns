# Deploy themed custom pages + mwan3 globals to 192.168.9.1
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
add-type @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy { public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; } }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

$ubusUrl = 'https://192.168.9.1/ubus'
$repoRoot = Split-Path $PSScriptRoot -Parent

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

$loginBody = '{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"password","timeout":300}]}'
$script:token = (Invoke-UbusRaw $loginBody)[1].ubus_rpc_session
Write-Output 'LOGIN_OK'

$deployments = @(
    @{
        Local  = Join-Path $repoRoot 'files\www\luci-static\resources\lede-fullwidth.js'
        Remote = '/www/luci-static/resources/lede-fullwidth.js'
        Mode   = '644'
    },
    @{
        Local  = Join-Path $repoRoot 'files\www\luci-static\resources\lede-theme-page.js'
        Remote = '/www/luci-static/resources/lede-theme-page.js'
        Mode   = '644'
    },
    @{
        Local  = Join-Path $repoRoot 'files\www\luci-static\resources\view\status\index.js'
        Remote = '/www/luci-static/resources/view/status/index.js'
        Mode   = '644'
    },
    @{
        Local  = Join-Path $repoRoot 'files\www\luci-static\resources\view\mwan3\network\globals.js'
        Remote = '/www/luci-static/resources/view/mwan3/network/globals.js'
        Mode   = '644'
    },
    @{
        Local  = Join-Path $repoRoot 'files\www\luci-static\resources\view\status\wanalert-page.js'
        Remote = '/www/luci-static/resources/view/status/wanalert-page.js'
        Mode   = '644'
    },
    @{
        Local  = Join-Path $repoRoot 'files\www\luci-static\resources\view\status\wanalert-layout.js'
        Remote = '/www/luci-static/resources/view/status/wanalert-layout.js'
        Mode   = '644'
    },
    @{
        Local  = Join-Path $repoRoot 'files\usr\libexec\lede-mwan3-setup'
        Remote = '/usr/libexec/lede-mwan3-setup'
        Mode   = '755'
    },
    @{
        Local  = Join-Path $repoRoot 'files\lib\functions\lede-mwan3.sh'
        Remote = '/lib/functions/lede-mwan3.sh'
        Mode   = '644'
    }
)

foreach ($item in $deployments) {
    if (-not (Test-Path $item.Local)) { throw ("missing: " + $item.Local) }
    Write-Output ("DEPLOY " + $item.Local + " -> " + $item.Remote)
    Write-RemoteFile $item.Local $item.Remote | Write-Output
    if ($item.Mode) {
        Invoke-Exec ("chmod " + $item.Mode + " '" + $item.Remote + "'") | Out-Null
    }
}

Invoke-Exec "grep -c Deprecated /www/luci-static/resources/lede-fullwidth.js" | ForEach-Object { Write-Output ("VERIFY fullwidth-disabled: $_") }
Invoke-Exec "grep -c lede-themed-page /www/luci-static/resources/lede-theme-page.js" | ForEach-Object { Write-Output ("VERIFY theme-page: $_") }
Invoke-Exec "grep -c resolveBackendAction /www/luci-static/resources/view/mwan3/network/globals.js" | ForEach-Object { Write-Output ("VERIFY globals: $_") }
Invoke-Exec "rm -rf /tmp/luci-*" | Out-Null
Write-Output 'CACHE_CLEARED'
Write-Output 'HOTFIX_DONE'
