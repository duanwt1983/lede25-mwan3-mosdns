# Test lede-data-setup on 192.168.9.1 (offline gdisk install + one-shot run).
param(
    [string]$RouterIp = '192.168.9.1',
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
$src = Join-Path $repoRoot 'files\usr\libexec\lede-data-setup'
if (-not (Test-Path $src)) { throw "missing $src" }
$setupB64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content -Raw -Encoding UTF8 $src)))

$ipkDir = Join-Path $env:TEMP 'gdisk-search'
New-Item -ItemType Directory -Force -Path $ipkDir | Out-Null
$ipkPath = Join-Path $ipkDir 'gdisk_1.0.10-r1_x86_64.ipk'
if (-not (Test-Path $ipkPath)) {
    curl.exe -sL -o $ipkPath 'https://mirrors.tencent.com/lede/releases/24.10.5/packages/x86_64/packages/gdisk_1.0.10-r1_x86_64.ipk'
}
if (-not (Test-Path $ipkPath)) { throw "failed to download gdisk ipk" }
$ipkB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($ipkPath))

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

Write-Host "=== PREP: offline gdisk install, clear init marker ==="
$prep = @'
rm -f /etc/.lede-data-init.done
rm -f /var/lock/opkg.lock
killall -9 opkg 2>/dev/null || true
'@ + "echo '$ipkB64' | base64 -d > /tmp/gdisk.ipk`n" + @'
opkg install /tmp/gdisk.ipk >/tmp/opkg-install.log 2>&1
echo opkg-install-exit=$?
tail -10 /tmp/opkg-install.log
command -v sgdisk || echo sgdisk=MISSING
'@
$r0 = Exec $token $prep
Write-Output $r0.stdout
if ($r0.stderr) { Write-Output $r0.stderr }
if ($r0.stdout -notmatch '/sgdisk') {
    Write-Host "ERROR: sgdisk not installed" -ForegroundColor Red
    exit 1
}

Write-Host "=== UPLOAD lede-data-setup ==="
$upload = @"
echo '$setupB64' | base64 -d > /usr/libexec/lede-data-setup
chmod +x /usr/libexec/lede-data-setup
wc -c /usr/libexec/lede-data-setup
"@
$r1 = Exec $token $upload
Write-Output $r1.stdout

Write-Host "=== RUN lede-data-setup (one-shot) ==="
$run = @'
/usr/libexec/lede-data-setup; echo setup-exit=$?
echo "=== init done marker ==="
ls -la /etc/.lede-data-init.done 2>&1
echo "=== script retired? ==="
ls -la /usr/libexec/lede-data-setup 2>&1
echo "=== log ==="
cat /tmp/lede-data-setup.log 2>&1
echo "=== lsblk ==="
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
echo "=== df /data ==="
df -h /data 2>&1 || echo no-data
echo "=== fstab data ==="
uci show fstab | grep -E 'target=.*/data|uuid=.*' || uci show fstab
echo "=== marker ==="
ls -la /data/.lede-data 2>&1
'@
$r2 = Exec $token $run
Write-Output $r2.stdout
if ($r2.stderr) { Write-Output $r2.stderr }

$ok = ($r2.stdout -match 'setup-exit=0') -and ($r2.stdout -match 'Mounted on.*\n/data' -or $r2.stdout -match '/data\s')
if ($ok) {
    Write-Host "SUCCESS: /data setup completed" -ForegroundColor Green
    exit 0
}
Write-Host "FAILED: setup did not complete successfully" -ForegroundColor Red
exit 1
