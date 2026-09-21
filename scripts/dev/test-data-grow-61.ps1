# Simulate new-firmware first boot: small prebuilt LEDEDATA + grow to disk end.
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
$setupSrc = Join-Path $repoRoot 'files\usr\libexec\lede-data-setup'
$initSrc = Join-Path $repoRoot 'files\etc\init.d\lede-data'
$setupB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content -Raw -Encoding UTF8 $setupSrc)))
$initB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content -Raw -Encoding UTF8 $initSrc)))

$base = "https://$RouterIp/ubus"
function U($b) {
    $r = Invoke-RestMethod -Uri $base -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($b)) -TimeoutSec 300
    if ($r.error) { throw ($r.error | ConvertTo-Json -Compress) }
    return $r.result
}
function Exec($token, $cmd) {
    $esc = $cmd -replace '\\','\\' -replace '"','\"'
    $body = '{"jsonrpc":"2.0","id":2,"method":"call","params":["' + $token + '","file","exec",{"command":"/bin/sh","params":["-c","' + $esc + '"]}]}'
    return (U $body)[1]
}

$token = (U ('{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"' + ($Password -replace '\\','\\' -replace '"','\"') + '","timeout":600}]}'))[1].ubus_rpc_session

Write-Host "=== GROW TEST: recreate small LEDEDATA placeholder ===" -ForegroundColor Cyan
$prep = @'
set -e
rm -f /etc/.lede-data-init.done /tmp/lede-data-setup.log
for mp in /data /usr/share/xray /usr/share/passwall/rules /etc/mosdns/rule/adlist /usr/share/v2ray; do
  umount "$mp" 2>/dev/null || true
done
n=$(sgdisk -p /dev/sda 2>/dev/null | awk "/LEDEDATA/{print \$1}" | head -1)
[ -n "$n" ] && sgdisk -d "$n" /dev/sda
sgdisk -n 0:0:+512M -c 0:LEDEDATA -t 0:8300 /dev/sda
partprobe /dev/sda 2>/dev/null || true
partx -u /dev/sda 2>/dev/null || true
block detect 2>/dev/null || true
sleep 3
p=$(blkid -t LABEL=LEDEDATA -o device 2>/dev/null | head -1)
[ -n "$p" ] || p=/dev/sda3
i=0
while [ ! -b "$p" ] && [ "$i" -lt 10 ]; do sleep 1; block detect; i=$((i+1)); done
mkfs.ext4 -F -L LEDEDATA -m 0 "$p"
echo placeholder=$p
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT
find /data -mindepth 1 -delete 2>/dev/null || true
while uci -q show fstab 2>/dev/null | grep -q "target='/data'"; do
  sid=$(uci -q show fstab | awk -F"[.=]" "/target='\\/data'/{print \$2; exit}")
  [ -n "$sid" ] || break
  uci -q delete "fstab.$sid"
done
uci -q commit fstab
echo prep-ok
'@
$r0 = Exec $token $prep
Write-Output $r0.stdout

Write-Host "=== DEPLOY + RUN grow path ===" -ForegroundColor Cyan
$run = "mkdir -p /usr/libexec /etc/init.d`n" +
    "echo '$setupB64' | base64 -d > /usr/libexec/lede-data-setup`n" +
    "echo '$initB64' | base64 -d > /etc/init.d/lede-data`n" +
    "chmod +x /usr/libexec/lede-data-setup /etc/init.d/lede-data`n" +
    '/usr/libexec/lede-data-setup; echo setup-exit=$?' + "`n" +
    @'
echo === log ===
cat /tmp/lede-data-setup.log
echo === lsblk ===
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT
echo === mount ===
mount | grep ' /data ' || echo '/data NOT mounted'
echo === df ===
df -h /data
echo === marker ===
ls -la /data/.lede-data /etc/.lede-data-init.done 2>&1
'@
$r1 = Exec $token $run
Write-Output $r1.stdout

$ok = ($r1.stdout -match 'setup-exit=0') -and
      ($r1.stdout -notmatch 'setup-exit=True') -and
      ($r1.stdout -match 'growing LEDEDATA') -and
      ($r1.stdout -match 'mounted LEDEDATA') -and
      ($r1.stdout -notmatch '/data NOT mounted') -and
      ($r1.stdout -match '56\.[0-9]G|57\.[0-9]G|55\.[0-9]G')
if ($ok) {
    Write-Host "SUCCESS: LEDEDATA grow + mount completed" -ForegroundColor Green
    exit 0
}
Write-Host "FAILED: grow path test" -ForegroundColor Red
exit 1
