# Hot-deploy MosDNS LuCI-consistent update/apply fixes to 6.1.
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

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$base = "https://$RouterIp/ubus"

function Invoke-UbusRaw($body) {
    $r = Invoke-RestMethod -Uri $base -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 180
    if ($r.error) { throw ($r.error | ConvertTo-Json -Compress) }
    return $r.result
}
function Invoke-Exec($token, $cmd) {
    $esc = $cmd -replace '\\','\\' -replace '"','\"'
    $body = '{"jsonrpc":"2.0","id":2,"method":"call","params":["' + $token + '","file","exec",{"command":"/bin/sh","params":["-c","' + $esc + '"]}]}'
    return (Invoke-UbusRaw $body)[1]
}
function Upload-File($token, $localPath, $remotePath) {
    $text = [IO.File]::ReadAllText($localPath) -replace "`r`n","`n" -replace "`r","`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $dir = ($remotePath -replace '/[^/]+$','')
    $tmp = '/tmp/.lede-upload.bin'
    $part = '/tmp/.lede-upload.part'
    Invoke-Exec $token "mkdir -p '$dir'; rm -f '$tmp' '$part'" | Out-Null
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
            Invoke-Exec $token "mv -f '$part' '$tmp'" | Out-Null
        } else {
            Invoke-Exec $token "cat '$part' >> '$tmp'; rm -f '$part'" | Out-Null
        }
    }
    Invoke-Exec $token "mv -f '$tmp' '$remotePath'" | Out-Null
    Write-Host "UPLOADED $remotePath ($($bytes.Length) bytes)" -ForegroundColor Green
}

$token = (Invoke-UbusRaw ('{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"' + ($Password -replace '\\','\\' -replace '"','\"') + '","timeout":600}]}'))[1].ubus_rpc_session

$map = @{
    'package\mosdns-mwan\files\usr\libexec\mosdns-gen' = '/usr/libexec/mosdns-gen'
    'package\mosdns-mwan\files\usr\libexec\mosdns-apply-luci' = '/usr/libexec/mosdns-apply-luci'
}
foreach ($rel in $map.Keys) {
    $local = Join-Path $repoRoot ($rel -replace '\\','/')
    Upload-File $token $local $map[$rel]
    Invoke-Exec $token "chmod +x '$($map[$rel])'" | Out-Null
}

$patchPy = @'
from pathlib import Path
p = Path('/usr/share/mosdns/mosdns.uc')
t = p.read_text(encoding='utf-8')
apply_fn = """
function apply_luci_config() {
	let r = exec_sys('/usr/libexec/mosdns-apply-luci');
	if (r.code != 0)
		print('apply_luci_config: ' + r.stdout + '\\n');
	stdout.flush();
}

"""
if 'function apply_luci_config(' not in t:
	t = t.replace('let action = ARGV[0];', apply_fn + 'let action = ARGV[0];', 1)
old = '\t\tupdate_geodat();\n\t\tupdate_adlist();\n\t\tv2dat_dump();\n\t\tprint("UPDATE_FINISHED\\n");'
new = '\t\tupdate_geodat();\n\t\tupdate_adlist();\n\t\tv2dat_dump();\n\t\tapply_luci_config();\n\t\tprint("UPDATE_FINISHED\\n");'
if old in t:
	t = t.replace(old, new, 1)
old_else = "\t} else {\n\t\texec_sys(`geo2txt geoip -f ${v2dat_dir}/geoip.dat -e cn -o /var/mosdns`);\n\t\texec_sys(`geo2txt geosite -f ${v2dat_dir}/geosite.dat -e cn -e 'geolocation-!cn' -o /var/mosdns`);\n\n\t\tlet geoip_tags"
new_else = "\t} else {\n\t\texec_sys(`geo2txt geoip -f ${v2dat_dir}/geoip.dat -e cn -o /var/mosdns`);\n\t\texec_sys(`geo2txt geosite -f ${v2dat_dir}/geosite.dat -e cn -e 'geolocation-!cn' -o /var/mosdns`);\n\t\tif (adblock === '1' && index(ad_source, 'geosite.dat') !== -1) {\n\t\t\texec_sys(`geo2txt geosite -f ${v2dat_dir}/geosite.dat -e category-ads-all -o /var/mosdns`);\n\t\t}\n\n\t\tlet geoip_tags"
if old_else in t:
	t = t.replace(old_else, new_else, 1)
p.write_text(t, encoding='utf-8')
print('patched mosdns.uc')
'@
$patchB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($patchPy))
Invoke-Exec $token "echo '$patchB64' | base64 -d > /tmp/patch-mosdns-uc.py; python3 /tmp/patch-mosdns-uc.py; rm -f /tmp/patch-mosdns-uc.py" | Out-Null

Write-Host "`n=== UCI (LuCI choices) ===" -ForegroundColor Cyan
$r = Invoke-Exec $token @'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
echo "adblock=$(uci -q get mosdns.config.adblock)"
echo "ad_source:"
uci -q get mosdns.config.ad_source 2>/dev/null
echo "enabled=$(uci -q get mosdns.config.enabled)"
'@
Write-Output $r.stdout

Write-Host "`n=== apply from UCI ===" -ForegroundColor Cyan
$r2 = Invoke-Exec $token '/usr/libexec/mosdns-apply-luci; echo apply_exit=$?'
Write-Output $r2.stdout

Write-Host "`n=== verify blocklist in yaml ===" -ForegroundColor Cyan
$r3 = Invoke-Exec $token @'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
grep -A20 'tag: blocklist' /var/etc/mosdns.yaml 2>/dev/null | head -25
ls -la /etc/mosdns/rule/adlist/ 2>/dev/null | head -8
ls -la /var/mosdns/geosite_category-ads-all.txt 2>/dev/null
'@
Write-Output $r3.stdout
Write-Host "Done." -ForegroundColor Green
