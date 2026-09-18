# Windows-friendly: set git executable bit for overlay scripts with shebang.
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
Set-Location $Root

$patterns = @(
    'files/etc/init.d/*',
    'files/etc/hotplug.d/*/*',
    'files/usr/libexec/*',
    'files/usr/libexec/rpcd/*',
    'files/usr/sbin/*',
    'package/mosdns-mwan/files/etc/hotplug.d/*/*',
    'package/mosdns-mwan/files/usr/libexec/*',
    'package/mosdns-mwan/files/usr/sbin/*',
    'package/mosdns-mwan/files/usr/share/mosdns/*'
)

function Test-Shebang([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    $bytes = [IO.File]::ReadAllBytes($Path)
    return ($bytes.Length -ge 2 -and $bytes[0] -eq 0x23 -and $bytes[1] -eq 0x21)
}

$fixed = 0
$skipped = 0

function Fix-File([string]$f) {
    if (-not (Test-Shebang $f)) { return }
    $mode = (git ls-files -s -- $f 2>$null | ForEach-Object { ($_ -split '\s+')[0] })
    if ($mode) {
        if ($mode -eq '100644') {
            git update-index --chmod=+x -- $f
            Write-Output "EXEC $f"
            $script:fixed++
        } else {
            $script:skipped++
        }
        return
    }
    if (Test-Path $f) {
        $null = git add --chmod=+x -- $f 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Output "ADD+EXEC $f"
            $script:fixed++
        }
    }
}

foreach ($pat in $patterns) {
    foreach ($f in (git ls-files $pat)) { Fix-File $f }
    Get-ChildItem -File -Path $pat -ErrorAction SilentlyContinue | ForEach-Object {
        $rel = $_.FullName.Substring($Root.Length + 1).Replace('\', '/')
        $tracked = git ls-files -- $rel
        if ($tracked) { return }
        Fix-File $rel
    }
}
Write-Output "fix-overlay-exec: +x set for $fixed file(s), already executable: $skipped"
