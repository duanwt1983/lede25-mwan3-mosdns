# Sync display/accounting/safety fixes to 192.168.8.1.
# Does not restart network, firewall, mosdns, or mwan3.
param(
    [string]$RouterIp = '192.168.8.1',
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
$filesRoot = Join-Path $repoRoot 'files'

$deployMap = [ordered]@{
    'usr/share/ucode/lede-bandix.uc' = '/usr/share/ucode/lede-bandix.uc'
    'usr/libexec/rpcd/wanmonitor' = '/usr/libexec/rpcd/wanmonitor'
    'usr/share/ucode/lede-autolimit.uc' = '/usr/share/ucode/lede-autolimit.uc'
    'usr/share/ucode/lede-watch.uc' = '/usr/share/ucode/lede-watch.uc'
    'usr/libexec/wan-alert' = '/usr/libexec/wan-alert'
    'www/luci-static/resources/view/status/wanalert-page.js' = '/www/luci-static/resources/view/status/wanalert-page.js'
    'usr/libexec/packet-cap' = '/usr/libexec/packet-cap'
    'www/luci-static/resources/view/network/packetcap.js' = '/www/luci-static/resources/view/network/packetcap.js'
    'www/luci-static/resources/view/status/index.js' = '/www/luci-static/resources/view/status/index.js'
}

function Invoke-UbusRaw($body) {
    $r = Invoke-RestMethod -Uri $base -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 180
    if ($r.error) { throw ($r.error | ConvertTo-Json -Compress) }
    return $r.result
}

function Invoke-ExecSimple($token, $command, $params) {
    $paramJson = ($params | ForEach-Object { '"' + ($_ -replace '\\','\\' -replace '"','\"') + '"' }) -join ','
    $body = '{"jsonrpc":"2.0","id":9,"method":"call","params":["' + $token + '","file","exec",{"command":"' + $command + '","params":[' + $paramJson + ']}]}'
    return (Invoke-UbusRaw $body)[1]
}

function Login-Router {
    $loginBody = '{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"' + ($Password -replace '\\','\\' -replace '"','\"') + '","timeout":600}]}'
    return (Invoke-UbusRaw $loginBody)[1].ubus_rpc_session
}

function Upload-File($token, $localPath, $remotePath) {
    if (-not (Test-Path $localPath)) { throw "Missing local file: $localPath" }
    $text = [IO.File]::ReadAllText($localPath) -replace "`r`n","`n" -replace "`r","`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $dir = ($remotePath -replace '/[^/]+$','')
    $tmp = '/tmp/.lede-upload.bin'
    $part = '/tmp/.lede-upload.part'
    Invoke-ExecSimple $token '/bin/mkdir' @('-p', $dir) | Out-Null
    Invoke-ExecSimple $token '/bin/rm' @('-f', $tmp, $part) | Out-Null
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
        Invoke-UbusRaw ($writeObj | ConvertTo-Json -Depth 6 -Compress) | Out-Null
        if ($i -eq 0) {
            Invoke-ExecSimple $token '/bin/mv' @('-f', $part, $tmp) | Out-Null
        } else {
            Invoke-ExecSimple $token '/bin/sh' @('-c', "cat '$part' >> '$tmp'; rm -f '$part'") | Out-Null
        }
    }
    $mv = Invoke-ExecSimple $token '/bin/mv' @('-f', $tmp, $remotePath)
    if ($mv.code -ne 0) { throw "mv failed for $remotePath : $($mv.stderr)" }
    Write-Output ("UPLOADED $remotePath ($($bytes.Length) bytes)")
}

$token = Login-Router
Write-Output "LOGIN_OK $RouterIp"

foreach ($rel in $deployMap.Keys) {
    $local = Join-Path $filesRoot ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    Upload-File $token $local $deployMap[$rel]
}

$prep = @'
chmod 755 /usr/libexec/rpcd/wanmonitor /usr/libexec/wan-alert /usr/libexec/packet-cap
for f in \
  /usr/share/ucode/lede-bandix.uc \
  /usr/libexec/rpcd/wanmonitor \
  /usr/share/ucode/lede-autolimit.uc \
  /usr/share/ucode/lede-watch.uc \
  /usr/libexec/wan-alert \
  /www/luci-static/resources/view/status/wanalert-page.js \
  /usr/libexec/packet-cap \
  /www/luci-static/resources/view/network/packetcap.js \
  /www/luci-static/resources/view/status/index.js
do
  [ -f "$f" ] && sed -i "s/\r$//" "$f"
done
rmdir /tmp/wan-alert.lock 2>/dev/null || true
/etc/init.d/lede-autolimit reload >/dev/null 2>&1 || /etc/init.d/lede-autolimit restart >/dev/null 2>&1 || true
/etc/init.d/wanalert restart
echo PREP_OK
ip -4 addr show br-lan 2>/dev/null | awk "/inet /{print \"LAN \" \$2}"
'@
$prep = $prep -replace "`r`n", "`n" -replace "`r", "`n"
$r = Invoke-ExecSimple $token '/bin/sh' @('-c', $prep)
Write-Output ('PREP code=' + $r.code)
if ($r.stdout) { Write-Output $r.stdout }
if ($r.stderr) { Write-Output $r.stderr }

$rp = Invoke-ExecSimple $token '/etc/init.d/rpcd' @('restart')
Write-Output ('RPCD code=' + $rp.code)
if ($rp.stdout) { Write-Output $rp.stdout }
if ($rp.stderr) { Write-Output $rp.stderr }
Start-Sleep -Seconds 3

$token = Login-Router
Write-Output "RELOGIN_OK"

$verify = @'
echo === markers ===
grep -c "bplus_iface_is_lan" /usr/share/ucode/lede-bandix.uc
grep -c "all_down_sent" /usr/share/ucode/lede-watch.uc
grep -c "overlay_hit" /usr/share/ucode/lede-watch.uc
grep -c "function alert_log_path" /usr/libexec/wan-alert
grep -c "MAX_CAP_SEC" /usr/libexec/packet-cap
grep -c "_pollIv" /www/luci-static/resources/view/status/index.js
grep -c "lede-log" /www/luci-static/resources/view/status/wanalert-page.js
grep -c "bandix_list_schedules" /usr/share/ucode/lede-autolimit.uc
echo === sizes ===
wc -c /usr/share/ucode/lede-bandix.uc /usr/libexec/rpcd/wanmonitor /usr/share/ucode/lede-autolimit.uc /usr/share/ucode/lede-watch.uc /usr/libexec/wan-alert /usr/libexec/packet-cap /www/luci-static/resources/view/status/index.js /www/luci-static/resources/view/status/wanalert-page.js /www/luci-static/resources/view/network/packetcap.js
echo === services ===
pgrep -af "wan-alert|lede-autolimit" || true
ubus list 2>/dev/null | grep -E "wanmonitor|lede-autolimit" || true
echo === lan ===
ip -4 addr show br-lan 2>/dev/null | awk "/inet /{print}"
ubus call network.interface.lan status 2>/dev/null | grep -E "\"up\"|\"address\"" | head -n 8 || true
echo === pulse ===
ubus call wanmonitor pulse 2>/dev/null | head -c 400; echo
'@
$verify = $verify -replace "`r`n", "`n" -replace "`r", "`n"
$v = Invoke-ExecSimple $token '/bin/sh' @('-c', $verify)
Write-Output ('VERIFY code=' + $v.code)
if ($v.stdout) { Write-Output $v.stdout }
if ($v.stderr) { Write-Output $v.stderr }
