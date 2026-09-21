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
$loginBody = '{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"' + ($Password -replace '\\','\\' -replace '"','\"') + '","timeout":600}]}'
$token = (Invoke-UbusRaw $loginBody)[1].ubus_rpc_session
Write-Output "LOGIN_OK"

$check = @'
echo === flags ===
echo pushplus_enabled=$(uci -q get wanalert.main.pushplus_enabled)
echo pushplus_wechat=$(uci -q get wanalert.main.pushplus_wechat)
echo pushplus_app=$(uci -q get wanalert.main.pushplus_app)
echo ding_enabled=$(uci -q get wanalert.main.enabled)
tok=$(uci -q get wanalert.main.pushplus_token)
if [ -n "$tok" ]; then
  echo token_len=${#tok}
  echo token_ok=yes
else
  echo token_len=0
  echo token_ok=no
fi
'@
$check = $check -replace "`r`n", "`n" -replace "`r", "`n"
$c = Invoke-ExecSimple $token '/bin/sh' @('-c', $check)
Write-Output ('CHECK code=' + $c.code)
if ($c.stdout) { Write-Output $c.stdout }
if ($c.stderr) { Write-Output $c.stderr }

Write-Output '=== send test ==='
$t = Invoke-ExecSimple $token '/usr/sbin/wan-alert' @('test', 'manual')
Write-Output ('TEST code=' + $t.code)
if ($t.stdout) { Write-Output $t.stdout }
if ($t.stderr) { Write-Output $t.stderr }

$last = @'
echo === last ===
if [ -f /tmp/wan-alert.pp.last ]; then
  sed -E "s/\"token\"[[:space:]]*:[[:space:]]*\"[^\"]+\"/\"token\":\"***\"/g" /tmp/wan-alert.pp.last
else
  echo no_pp_last
fi
if [ -f /tmp/wan-alert.last ]; then
  echo --- dingtalk ---
  cat /tmp/wan-alert.last
fi
'@
$last = $last -replace "`r`n", "`n" -replace "`r", "`n"
$l = Invoke-ExecSimple $token '/bin/sh' @('-c', $last)
Write-Output ('LAST code=' + $l.code)
if ($l.stdout) { Write-Output $l.stdout }
if ($l.stderr) { Write-Output $l.stderr }
