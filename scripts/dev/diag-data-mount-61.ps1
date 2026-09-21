param([string]$RouterIp = '192.168.6.1', [string]$Password = 'password')
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
echo "=== df -h ==="
df -h
echo "=== mount /data ==="
mount | grep -E ' /data |sda3'
echo "=== mountpoint ==="
mountpoint /data 2>&1
echo "=== ls -la /data ==="
ls -la /data | head -15
echo "=== overlay data ==="
ls -la /overlay/upper/data 2>&1 | head -10
echo "=== blkid sda3 ==="
blkid /dev/sda3 2>&1
echo "=== lsblk ==="
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
echo "=== fstab ==="
uci show fstab
echo "=== fstab enabled ==="
/etc/init.d/fstab enabled; echo exit=$?
echo "=== lede-log paths ==="
uci show lede-log 2>/dev/null | grep path
echo "=== marker ==="
ls -la /data/.lede-data /etc/.lede-data-init.done 2>&1
echo "=== block mount ==="
block info 2>&1
'@
Write-Output (Exec $token $cmd).stdout
