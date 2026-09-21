param([string]$RouterIp = '192.168.9.1', [string]$Password = 'password')
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
add-type @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy { public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) { return true; } }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
$url = "https://$RouterIp/ubus"
function U($b) {
    $r = Invoke-RestMethod -Uri $url -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($b)) -TimeoutSec 120
    if ($r.error) { throw ($r.error | ConvertTo-Json -Compress) }
    return $r.result
}
function Exec($token, $cmd) {
    $esc = $cmd -replace '\\','\\' -replace '"','\"'
    $body = '{"jsonrpc":"2.0","id":2,"method":"call","params":["' + $token + '","file","exec",{"command":"/bin/sh","params":["-c","' + $esc + '"]}]}'
    return (U $body)[1]
}
$token = (U ('{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"' + ($Password -replace '\\','\\' -replace '"','\"') + '","timeout":600}]}'))[1].ubus_rpc_session
$cmd = @'
echo "=== mounts ==="
mount
echo "=== lsblk ==="
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT
echo "=== blkid ==="
blkid
echo "=== proc mounts root ==="
awk '$2=="/"{print}' /proc/mounts
echo "=== mountinfo root ==="
awk '$5=="/"{print}' /proc/self/mountinfo
echo "=== scripts ==="
ls -la /usr/libexec/lede-data-setup /etc/init.d/lede-data /etc/uci-defaults/10-lede-data-enable 2>&1
echo "=== setup log ==="
cat /tmp/lede-data-setup.log 2>&1
echo "=== logread ==="
logread | grep lede-data || true
echo "=== tools ==="
command -v parted; command -v blkid; command -v mkfs.ext4; command -v partprobe; command -v partx
echo "=== parted free ==="
parted -m -s /dev/sda unit MiB print free 2>&1
echo "=== fstab ==="
uci show fstab 2>&1
echo "=== lede-data enabled ==="
/etc/init.d/lede-data enabled; echo exit=$?
'@
$r = Exec $token $cmd
Write-Output $r.stdout
if ($r.stderr) { Write-Output $r.stderr }
