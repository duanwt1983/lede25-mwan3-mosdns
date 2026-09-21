# Sync PushPlus WeChat/App alerting to 192.168.8.1.
# Does not overwrite live wanalert config, and does not restart network/mosdns/mwan3.
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
    'usr/libexec/wan-alert' = '/usr/libexec/wan-alert'
    'www/luci-static/resources/view/status/alertmap.js' = '/www/luci-static/resources/view/status/alertmap.js'
    'www/luci-static/resources/view/status/wanalert-layout.js' = '/www/luci-static/resources/view/status/wanalert-layout.js'
    'www/luci-static/resources/view/status/alertlog.js' = '/www/luci-static/resources/view/status/alertlog.js'
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
chmod 755 /usr/libexec/wan-alert
for f in \
  /usr/libexec/wan-alert \
  /www/luci-static/resources/view/status/alertmap.js \
  /www/luci-static/resources/view/status/wanalert-layout.js \
  /www/luci-static/resources/view/status/alertlog.js
do
  [ -f "$f" ] && sed -i "s/\r$//" "$f"
done
uci -q get wanalert.main.pushplus_enabled >/dev/null || uci set wanalert.main.pushplus_enabled=0
uci -q get wanalert.main.pushplus_wechat >/dev/null || uci set wanalert.main.pushplus_wechat=1
uci -q get wanalert.main.pushplus_app >/dev/null || uci set wanalert.main.pushplus_app=1
uci -q get wanalert.main.pushplus_token >/dev/null || uci set wanalert.main.pushplus_token=
uci -q get wanalert.main.pushplus_prefix >/dev/null || uci set wanalert.main.pushplus_prefix=
uci commit wanalert
rmdir /tmp/wan-alert.lock 2>/dev/null || true
/etc/init.d/wanalert restart
sleep 1
echo PREP_OK
ip -4 addr show br-lan 2>/dev/null | awk "/inet /{print \"LAN \" \$2}"
'@
$prep = $prep -replace "`r`n", "`n" -replace "`r", "`n"
$r = Invoke-ExecSimple $token '/bin/sh' @('-c', $prep)
Write-Output ('PREP code=' + $r.code)
if ($r.stdout) { Write-Output $r.stdout }
if ($r.stderr) { Write-Output $r.stderr }

$verify = @'
echo === markers ===
grep -c "function send_pushplus" /usr/libexec/wan-alert
grep -c "batchSend" /usr/libexec/wan-alert
grep -c "pushplus_token" /www/luci-static/resources/view/status/alertmap.js
grep -c "pushplus_prefix" /usr/libexec/wan-alert
grep -c "depends('enabled', '1')" /www/luci-static/resources/view/status/alertmap.js
grep -c "depends('pushplus_enabled', '1')" /www/luci-static/resources/view/status/alertmap.js
grep -c "pushplus_prefix" /usr/libexec/wan-alert
grep -c "depends('enabled', '1')" /www/luci-static/resources/view/status/alertmap.js
grep -c "depends('pushplus_enabled', '1')" /www/luci-static/resources/view/status/alertmap.js
grep -c "optionBox(sec, 'pushplus_token')" /www/luci-static/resources/view/status/wanalert-layout.js
grep -c "PushPlus" /www/luci-static/resources/view/status/alertlog.js
echo === exec ===
ls -l /usr/libexec/wan-alert
head -c 2 /usr/libexec/wan-alert
echo
echo === uci flags ===
uci -q get wanalert.main.pushplus_enabled
uci -q get wanalert.main.pushplus_wechat
uci -q get wanalert.main.pushplus_app
echo token_set=$(uci -q get wanalert.main.pushplus_token >/dev/null && echo yes || echo no)
echo ding_enabled=$(uci -q get wanalert.main.enabled)
echo === service ===
pgrep -af wan-alert || true
/etc/init.d/wanalert enabled; echo enabled=$?
echo === lan ===
ip -4 addr show br-lan 2>/dev/null | awk "/inet /{print}"
'@
$verify = $verify -replace "`r`n", "`n" -replace "`r", "`n"
$v = Invoke-ExecSimple $token '/bin/sh' @('-c', $verify)
Write-Output ('VERIFY code=' + $v.code)
if ($v.stdout) { Write-Output $v.stdout }
if ($v.stderr) { Write-Output $v.stderr }
