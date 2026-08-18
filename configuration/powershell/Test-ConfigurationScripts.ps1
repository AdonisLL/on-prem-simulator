[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$failures = [Collections.Generic.List[string]]::new()
Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1' -Recurse | ForEach-Object {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($errorRecord in $errors) {
        $failures.Add("$($_.FullName): $($errorRecord.Message)")
    }
}
Get-ChildItem -Path $PSScriptRoot -Filter '*.psm1' -Recurse | ForEach-Object {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($errorRecord in $errors) {
        $failures.Add("$($_.FullName): $($errorRecord.Message)")
    }
}
if ($failures.Count -gt 0) {
    throw ($failures -join [Environment]::NewLine)
}
Write-Host 'PowerShell configuration scripts parsed successfully.'
