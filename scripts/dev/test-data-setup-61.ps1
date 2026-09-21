# Full first-boot simulation for lede-data-setup on 6.1 (or any router).
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
if (-not (Test-Path $setupSrc)) { throw "missing $setupSrc" }
if (-not (Test-Path $initSrc)) { throw "missing $initSrc" }
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

Write-Host "=== PRE: disk and mount state ===" -ForegroundColor Cyan
$pre = @'
echo "=== mounts ==="
mount | grep -E " /data | /$ " || true
echo "=== lsblk ==="
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT
echo "=== parted ==="
parted -m -s /dev/sda unit MiB print free 2>&1
echo "=== blkid LEDEDATA ==="
blkid | grep -iE "LEDEDATA|sda3" || blkid
echo "=== fstab data ==="
uci show fstab 2>/dev/null | grep -E "target=|uuid=|enabled=" || true
echo "=== markers ==="
ls -la /etc/.lede-data-init.done /data/.lede-data 2>&1
echo "=== overlay /data ==="
ls -la /overlay/upper/data 2>&1 | head -5
'@
$r0 = Exec $token $pre
Write-Output $r0.stdout
if ($r0.stderr) { Write-Output $r0.stderr }

Write-Host "=== RESET: first-boot state ===" -ForegroundColor Cyan
$reset = @'
set -e
umount /data 2>/dev/null || true
n=$(sgdisk -p /dev/sda 2>/dev/null | awk "/LEDEDATA/{print \$1}" | head -1)
if [ -n "$n" ]; then
  sgdisk -d "$n" /dev/sda
  partprobe /dev/sda 2>/dev/null || true
  block detect 2>/dev/null || true
  sleep 2
  echo "deleted LEDEDATA partition $n"
fi
rm -f /etc/.lede-data-init.done
rm -f /tmp/lede-data-setup.log
if [ -d /data ] && ! mountpoint -q /data 2>/dev/null; then
  find /data -mindepth 1 -delete 2>/dev/null || true
fi
sid=$(uci -q show fstab 2>/dev/null | awk -F"[.=]" "/target='\\/data'/{print \$2; exit}")
if [ -n "$sid" ]; then
  uci -q delete "fstab.$sid"
  uci -q commit fstab
  echo "removed fstab data entry $sid"
fi
echo reset-ok
'@
$r1 = Exec $token $reset
Write-Output $r1.stdout
if ($r1.stderr) { Write-Output $r1.stderr }

Write-Host "=== DEPLOY: lede-data-setup + init ===" -ForegroundColor Cyan
$deploy = @"
mkdir -p /usr/libexec /etc/init.d
echo '$setupB64' | base64 -d > /usr/libexec/lede-data-setup
echo '$initB64' | base64 -d > /etc/init.d/lede-data
chmod +x /usr/libexec/lede-data-setup /etc/init.d/lede-data
wc -c /usr/libexec/lede-data-setup /etc/init.d/lede-data
grep -c RETIRE_OK /usr/libexec/lede-data-setup
"@
$r2 = Exec $token $deploy
Write-Output $r2.stdout
if ($r2.stderr) { Write-Output $r2.stderr }

Write-Host "=== RUN: lede-data-setup (first boot) ===" -ForegroundColor Cyan
$run = @'
/usr/libexec/lede-data-setup
echo setup-exit=$?
echo "=== init marker ==="
ls -la /etc/.lede-data-init.done 2>&1
echo "=== script retired? ==="
ls -la /usr/libexec/lede-data-setup 2>&1
echo "=== data marker ==="
ls -la /data/.lede-data 2>&1
echo "=== log ==="
cat /tmp/lede-data-setup.log 2>&1
echo "=== lsblk ==="
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINT
echo "=== mount /data ==="
mount | grep " /data " || echo "/data NOT mounted"
echo "=== df /data ==="
df -h /data 2>&1
echo "=== fstab ==="
uci show fstab | grep -E "target=|uuid=|fstype=|enabled=" || uci show fstab
echo "=== logread ==="
logread | grep lede-data | tail -15
'@
$r3 = Exec $token $run
Write-Output $r3.stdout
if ($r3.stderr) { Write-Output $r3.stderr }

$ok = ($r3.stdout -match 'setup-exit=0') -and
      ($r3.stdout -match '/data') -and
      ($r3.stdout -notmatch '/data NOT mounted') -and
      ($r3.stdout -match 'mounted')
if ($ok) {
    Write-Host "SUCCESS: first-boot /data setup completed" -ForegroundColor Green
    exit 0
}
Write-Host "FAILED: first-boot /data setup did not complete" -ForegroundColor Red
exit 1
