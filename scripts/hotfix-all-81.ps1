# Hotfix: theme pages + mwan3 + brand title/font -> 192.168.8.1
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

$ubusUrl = "https://$RouterIp/ubus"
$repoRoot = Split-Path $PSScriptRoot -Parent
$tmpDir = Join-Path $repoRoot 'tmp-hotfix-81'
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

function Invoke-UbusRaw($body) {
    $r = Invoke-RestMethod -Uri $ubusUrl -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 300
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
        if (($n % 10) -eq 0) { Start-Sleep -Milliseconds 120 }
    }
    $dir = ($remotePath -replace '/[^/]+$', '')
    if ($dir) { Invoke-Exec ("mkdir -p '$dir'") | Out-Null }
    return Invoke-Exec ("base64 -d '$tmp' > '$remotePath' && rm -f '$tmp' && wc -c '$remotePath'")
}

function Utf8([byte[]]$b) { [Text.Encoding]::UTF8.GetString($b) }

function Patch-SystemJs($path) {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    $text = [System.IO.File]::ReadAllText($path, $utf8)
    $title = Utf8 @(0xE6, 0xA0, 0x87, 0xE9, 0xA2, 0x98)
    $hint = Utf8 @(0xE7, 0x99, 0xBB, 0xE5, 0xBD, 0x95, 0xE9, 0xA1, 0xB5, 0xE4, 0xB8, 0x8E, 0xE4, 0xBE, 0xA7, 0xE6, 0xA0, 0x8F, 0xE6, 0x98, 0xBE, 0xE7, 0xA4, 0xBA, 0xE7, 0x9A, 0x84, 0xE5, 0x93, 0x81, 0xE7, 0x89, 0x8C, 0xE6, 0xA0, 0x87, 0xE9, 0xA2, 0x98, 0xEF, 0xBC, 0x8C, 0xE7, 0x95, 0x99, 0xE7, 0xA9, 0xBA, 0xE5, 0x88, 0x99, 0xE6, 0x98, 0xBE, 0xE7, 0xA4, 0xBA, 0xE4, 0xB8, 0xBB, 0xE6, 0x9C, 0xBA, 0xE5, 0x90, 0x8D)
    $needle = "form.Value,'description',_('" + $title + "')"
    if ($text.Contains($needle)) { return $false }
    $repl = "s.taboption('general',form.Value,'description',_('" + $title + "'),_('" + $hint + "'));"
    $patterns = @(
        "s\.taboption\('general',form\.Value,'description',_\('[^']*'\),_\('[^']*'\)\);",
        "s\.taboption\('general', form\.Value, 'description', _\('[^']*'\), _\('[^']*'\)\);"
    )
    $text2 = $text
    foreach ($pat in $patterns) {
        $next = [regex]::Replace($text2, $pat, $repl, 1)
        if ($next -ne $text2) { $text2 = $next; break }
    }
    if ($text2 -eq $text -or -not $text2.Contains($needle)) {
        throw 'failed to patch system.js description label'
    }
    [System.IO.File]::WriteAllText($path, $text2, $utf8)
    return $true
}

$loginBody = '{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"password","timeout":300}]}'
$script:token = (Invoke-UbusRaw $loginBody)[1].ubus_rpc_session
Write-Output ("LOGIN_OK $RouterIp")

$templateDir = Join-Path $repoRoot 'files\usr\share\ucode\luci\template\themes\argon'
if (-not (Test-Path (Join-Path $templateDir 'header.ut'))) {
    $templateDir = Join-Path $repoRoot 'files\ucode\template\themes\argon'
}

$deployments = @(
    @{ Local = Join-Path $repoRoot 'files\www\luci-static\resources\lede-fullwidth.js'; Remote = '/www/luci-static/resources/lede-fullwidth.js'; Mode = '644' },
    @{ Local = Join-Path $repoRoot 'files\www\luci-static\resources\lede-theme-page.js'; Remote = '/www/luci-static/resources/lede-theme-page.js'; Mode = '644' },
    @{ Local = Join-Path $repoRoot 'files\www\luci-static\resources\view\status\index.js'; Remote = '/www/luci-static/resources/view/status/index.js'; Mode = '644' },
    @{ Local = Join-Path $repoRoot 'files\www\luci-static\resources\view\mwan3\network\globals.js'; Remote = '/www/luci-static/resources/view/mwan3/network/globals.js'; Mode = '644' },
    @{ Local = Join-Path $repoRoot 'files\www\luci-static\resources\view\status\wanalert-page.js'; Remote = '/www/luci-static/resources/view/status/wanalert-page.js'; Mode = '644' },
    @{ Local = Join-Path $repoRoot 'files\www\luci-static\resources\view\status\wanalert-layout.js'; Remote = '/www/luci-static/resources/view/status/wanalert-layout.js'; Mode = '644' },
    @{ Local = Join-Path $repoRoot 'files\usr\libexec\lede-mwan3-setup'; Remote = '/usr/libexec/lede-mwan3-setup'; Mode = '755' },
    @{ Local = Join-Path $repoRoot 'files\lib\functions\lede-mwan3.sh'; Remote = '/lib/functions/lede-mwan3.sh'; Mode = '644' },
    @{ Local = Join-Path $repoRoot 'files\usr\share\luci\menu.d\zzz-luci-mwan3-tab.json'; Remote = '/usr/share/luci/menu.d/zzz-luci-mwan3-tab.json'; Mode = '644' },
    @{ Local = Join-Path $repoRoot 'files\www\luci-static\argon\css\lede-brand-font.css'; Remote = '/www/luci-static/argon/css/lede-brand-font.css'; Mode = '644' },
    @{ Local = Join-Path $repoRoot 'files\www\luci-static\argon\font\DuanNingMaoBiXingShuWanZhengBan-2.ttf'; Remote = '/www/luci-static/argon/font/DuanNingMaoBiXingShuWanZhengBan-2.ttf'; Mode = '644' },
    @{ Local = Join-Path $templateDir 'header.ut'; Remote = '/usr/share/ucode/luci/template/themes/argon/header.ut'; Mode = '644' },
    @{ Local = Join-Path $templateDir 'header_login.ut'; Remote = '/usr/share/ucode/luci/template/themes/argon/header_login.ut'; Mode = '644' },
    @{ Local = Join-Path $templateDir 'sysauth.ut'; Remote = '/usr/share/ucode/luci/template/themes/argon/sysauth.ut'; Mode = '644' },
    @{ Local = Join-Path $templateDir 'header.ut'; Remote = '/usr/lib/luci/ucode/template/themes/argon/header.ut'; Mode = '644' },
    @{ Local = Join-Path $templateDir 'header_login.ut'; Remote = '/usr/lib/luci/ucode/template/themes/argon/header_login.ut'; Mode = '644' },
    @{ Local = Join-Path $templateDir 'sysauth.ut'; Remote = '/usr/lib/luci/ucode/template/themes/argon/sysauth.ut'; Mode = '644' }
)

foreach ($item in $deployments) {
    if (-not (Test-Path $item.Local)) { throw ("missing: " + $item.Local) }
    Write-Output ("DEPLOY " + $item.Local + " -> " + $item.Remote)
    Write-RemoteFile $item.Local $item.Remote | Write-Output
    if ($item.Mode) { Invoke-Exec ("chmod " + $item.Mode + " '" + $item.Remote + "'") | Out-Null }
}

$sysLocal = Join-Path $tmpDir 'system.js'
$sysRemote = '/www/luci-static/resources/view/system/system.js'
$readBody = '{"jsonrpc":"2.0","id":2,"method":"call","params":["' + $token + '","file","read",{"path":"' + $sysRemote + '","base64":true}]}'
$read = Invoke-UbusRaw $readBody
[System.IO.File]::WriteAllBytes($sysLocal, [Convert]::FromBase64String($read[1].data))
if (Patch-SystemJs $sysLocal) {
    Write-Output 'DEPLOY system.js (patched)'
    Write-RemoteFile $sysLocal $sysRemote | Write-Output
    Invoke-Exec ("chmod 644 '$sysRemote'") | Out-Null
} else {
    Write-Output 'SKIP system.js (already patched)'
}

Invoke-Exec "rm -f /www/luci-static/argon/font/DuanNingXingShuTianGongTi-2.ttf" | Out-Null
Invoke-Exec "rm -rf /tmp/luci-*" | Out-Null

$checks = @(
    'grep -c Deprecated /www/luci-static/resources/lede-fullwidth.js',
    'grep -c lede-themed-page /www/luci-static/resources/lede-theme-page.js',
    'grep -c commitDisableToUci /www/luci-static/resources/view/mwan3/network/globals.js',
    'grep -c mwan3_force_stop /usr/libexec/lede-mwan3-setup',
    'grep -c lede_lb_paused /lib/functions/lede-mwan3.sh',
    'grep -c displayName /usr/share/ucode/luci/template/themes/argon/header.ut',
    'test -f /www/luci-static/argon/font/DuanNingMaoBiXingShuWanZhengBan-2.ttf && wc -c /www/luci-static/argon/font/DuanNingMaoBiXingShuWanZhengBan-2.ttf',
    '/usr/libexec/lede-mwan3-setup status',
    'uci -q get system.@system[0].description'
)
foreach ($c in $checks) {
    Write-Output ("=== $c ===")
    Write-Output (Invoke-Exec $c)
}

Write-Output 'HOTFIX_DONE'
