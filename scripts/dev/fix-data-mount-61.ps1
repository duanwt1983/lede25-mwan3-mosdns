# Deploy lede-data-mount, fix fstab, mount /data on 6.1.
param([string]$RouterIp = '192.168.6.1', [string]$Password = 'password')
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
add-type @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy { public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; } }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$mountSrc = Join-Path $repoRoot 'files\usr\libexec\lede-data-mount'
$initSrc = Join-Path $repoRoot 'files\etc\init.d\lede-data-mount'
$mountB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content -Raw -Encoding UTF8 $mountSrc)))
$initB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content -Raw -Encoding UTF8 $initSrc)))

$base = "https://$RouterIp/ubus"
function U($b) {
    $r = Invoke-RestMethod -Uri $base -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($b)) -TimeoutSec 180
    if ($r.error) { throw ($r.error | ConvertTo-Json -Compress) }
    return $r.result
}
function Exec($token, $cmd) {
    $esc = $cmd -replace '\\','\\' -replace '"','\"'
    $body = '{"jsonrpc":"2.0","id":2,"method":"call","params":["' + $token + '","file","exec",{"command":"/bin/sh","params":["-c","' + $esc + '"]}]}'
    return (U $body)[1]
}

$token = (U ('{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"' + ($Password -replace '\\','\\' -replace '"','\"') + '","timeout":600}]}'))[1].ubus_rpc_session

Write-Host "Deploying lede-data-mount..." -ForegroundColor Cyan
$deploy = @"
mkdir -p /usr/libexec /etc/init.d
echo '$mountB64' | base64 -d > /usr/libexec/lede-data-mount
echo '$initB64' | base64 -d > /etc/init.d/lede-data-mount
chmod +x /usr/libexec/lede-data-mount /etc/init.d/lede-data-mount
/etc/init.d/lede-data-mount enable
"@
Exec $token $deploy | Out-Null

Write-Host "Fixing fstab and mounting /data..." -ForegroundColor Cyan
$run = @'
export PATH=/usr/sbin:/sbin:/usr/bin:/bin
rm -f /tmp/lede-data-mount.log

UUID=$(blkid -o value -s UUID /dev/sda3 2>/dev/null || echo 95defcea-e708-485f-8633-80097aaae94e)
echo uuid=$UUID

# remove stale auto-detect entries for this UUID
for sid in $(uci -q show fstab 2>/dev/null | awk -F"[.=]" "/uuid='${UUID}'/{print \$2}"); do
  tgt=$(uci -q get fstab.$sid.target)
  [ "$tgt" = "/data" ] && continue
  echo "delete stale fstab.$sid target=$tgt"
  uci -q delete fstab.$sid
done

sid=$(uci -q show fstab 2>/dev/null | awk -F"[.=]" "/target='\\/data'/{print \$2; exit}")
if [ -z "$sid" ]; then
  uci add fstab mount >/dev/null
  sid=$(uci -q show fstab 2>/dev/null | awk -F"[.=]" "/target='\\/data'/{print \$2; exit}")
  [ -z "$sid" ] && sid=$(uci -q show fstab | awk -F"[.=]" '/=mount$/{print $2}' | tail -1)
fi
uci set fstab.$sid.uuid="$UUID"
uci set fstab.$sid.target=/data
uci set fstab.$sid.fstype=ext4
uci delete fstab.$sid.options 2>/dev/null || true
uci set fstab.$sid.enabled=1
uci commit fstab
echo "=== fstab /data ==="
uci show fstab | grep -E "target=|uuid=|fstype=|options=|enabled="

partprobe /dev/sda 2>/dev/null || true
blockdev --rereadpt /dev/sda 2>/dev/null || true
partx -a /dev/sda 2>/dev/null || true
partx -u /dev/sda 2>/dev/null || true
block detect 2>/dev/null || true
sleep 2
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT /dev/sda 2>&1

if [ -b /dev/sda3 ]; then
  e2fsck -f -y /dev/sda3 2>&1 | tail -3
fi

/usr/libexec/lede-data-mount mount
echo mount-exit=$?

echo "=== df /data ==="
df -h /data
echo "=== mount ==="
mount | grep -E ' /data |sda3'
echo "=== fstab enabled ==="
/etc/init.d/fstab enabled; echo fstab-enabled=$?
echo "=== marker ==="
ls -la /data/.lede-data 2>&1
echo "=== lede-log paths ==="
uci show lede-log 2>/dev/null | grep path
echo "=== mount log tail ==="
tail -15 /tmp/lede-data-mount.log 2>&1
'@
$out = (Exec $token $run).stdout
Write-Output $out

$ok = ($out -match 'mount-exit=0') -and
      ($out -match '/dev/sda3') -and
      ($out -match '56\.[0-9]G|57\.[0-9]G|55\.[0-9]G')
if ($ok) {
    Write-Host "SUCCESS: /data is on block device" -ForegroundColor Green
    exit 0
}
Write-Host "Check output above" -ForegroundColor Yellow
exit 1
