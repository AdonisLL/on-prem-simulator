[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$trackedFiles = & git -C $root ls-files --cached --others --exclude-standard
$failures = [Collections.Generic.List[string]]::new()
foreach ($relativePath in $trackedFiles) {
    if (
        $relativePath -match '\.(tfstate|tfplan|pfx|p12|key|iso|vhd|vhdx|avhdx|vmcx|vmrs)$' -or
        $relativePath -match '(^|/)\.env$'
    ) {
        $failures.Add("Sensitive artifact is tracked: $relativePath")
        continue
    }
    $fullPath = Join-Path $root $relativePath
    if (-not (Test-Path $fullPath -PathType Leaf)) { continue }
    $text = Get-Content $fullPath -Raw -ErrorAction SilentlyContinue
    if ($text -match '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----') {
        $failures.Add("Private key marker found in $relativePath")
    }
    if ($text -match '(?i)(client_secret|admin_password|sql_password)\s*[:=]\s*["''][^<${][^"'']{7,}["'']') {
        $failures.Add("Possible hardcoded secret found in $relativePath")
    }
}
if ($failures.Count) {
    throw ($failures -join [Environment]::NewLine)
}
Write-Host 'Tracked files pass repository secret-hygiene checks.'
