# Hot-deploy mwan3 quality, MosDNS LuCI apply, Samba dedupe, lede-diag to 8.1.
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

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$filesRoot = Join-Path $repoRoot 'files'
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
    if (-not (Test-Path $localPath)) { throw "Missing: $localPath" }
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
Write-Host "LOGIN_OK $RouterIp" -ForegroundColor Cyan

$fileMap = [ordered]@{
    'usr/share/rpcd/ucode/mwan3.uc' = '/usr/share/rpcd/ucode/mwan3.uc'
    'usr/libexec/lede-mwan3-setup' = '/usr/libexec/lede-mwan3-setup'
    'usr/share/ucode/lede-diag.uc' = '/usr/share/ucode/lede-diag.uc'
    'usr/libexec/lede-samba-dedupe' = '/usr/libexec/lede-samba-dedupe'
    'etc/init.d/lede-samba-dedupe' = '/etc/init.d/lede-samba-dedupe'
}
foreach ($rel in $fileMap.Keys) {
    Upload-File $token (Join-Path $filesRoot $rel) $fileMap[$rel]
}

$pkgMap = @{
    'package\mosdns-mwan\files\usr\libexec\mosdns-gen' = '/usr/libexec/mosdns-gen'
    'package\mosdns-mwan\files\usr\libexec\mosdns-apply-luci' = '/usr/libexec/mosdns-apply-luci'
}
foreach ($rel in $pkgMap.Keys) {
    $local = Join-Path $repoRoot ($rel -replace '\\','/')
    Upload-File $token $local $pkgMap[$rel]
    Invoke-Exec $token "chmod +x '$($pkgMap[$rel])'" | Out-Null
}

$detailJs = Join-Path $repoRoot 'patches/luci-app-mwan3/detail.js'
if (Test-Path $detailJs) {
    Upload-File $token $detailJs '/www/luci-static/resources/view/mwan3/status/detail.js'
}

$patchPy = @'
from pathlib import Path
p = Path('/usr/share/mosdns/mosdns.uc')
if not p.is_file():
    print('skip mosdns.uc patch (missing)')
    raise SystemExit(0)
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

$prep = @'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
chmod 755 /usr/libexec/lede-samba-dedupe /etc/init.d/lede-samba-dedupe 2>/dev/null || true
for f in /usr/share/rpcd/ucode/mwan3.uc /usr/share/ucode/lede-diag.uc; do
  [ -f "$f" ] && sed -i "s/\r$//" "$f"
done
# mwan3 check_quality backfill (same as 44-lede-mwan3-quality)
[ -f /etc/config/mwan3 ] && for sid in $(uci -q show mwan3 2>/dev/null | sed -n "s/^mwan3\.\([^=]*\)=interface$/\1/p"); do
  [ "$(uci -q get mwan3.$sid.lede_auto)" = "1" ] || continue
  [ "$(uci -q get mwan3.$sid.enabled)" = "0" ] && continue
  case "$(uci -q get mwan3.$sid.check_quality 2>/dev/null)" in 1|yes|on|true) continue ;; esac
  uci -q set "mwan3.$sid.check_quality=1"
  uci -q set "mwan3.$sid.failure_latency=2000"
  uci -q set "mwan3.$sid.failure_loss=40"
  uci -q set "mwan3.$sid.recovery_latency=1000"
  uci -q set "mwan3.$sid.recovery_loss=10"
done
uci -q commit mwan3 2>/dev/null || true
/etc/init.d/lede-samba-dedupe enable 2>/dev/null || true
/etc/init.d/lede-samba-dedupe start 2>/dev/null || /usr/libexec/lede-samba-dedupe 2>/dev/null || true
/etc/init.d/rpcd restart
sleep 2
/etc/init.d/mwan3 restart
echo PREP_OK
'@
$prep = $prep -replace "`r`n", "`n" -replace "`r", "`n"
$r = Invoke-Exec $token $prep
Write-Output $r.stdout
if ($r.stderr) { Write-Output $r.stderr }

Write-Host "`n=== verify ===" -ForegroundColor Cyan
$v = Invoke-Exec $token @'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
grep -c "for (let tf in track_files)" /usr/share/rpcd/ucode/mwan3.uc 2>/dev/null || echo mwan3_uc=0
grep -c "check_quality" /www/luci-static/resources/view/mwan3/status/detail.js 2>/dev/null || echo detail_js=0
test -x /usr/libexec/mosdns-apply-luci && echo mosdns_apply=ok
grep -c "sda128" /usr/share/ucode/lede-diag.uc 2>/dev/null || true
ubus list 2>/dev/null | grep -w mwan3 || true
uci -q show mwan3 | grep check_quality | head -5
'@
Write-Output $v.stdout
Write-Host "Done." -ForegroundColor Green
