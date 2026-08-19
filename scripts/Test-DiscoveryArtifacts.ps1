[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$failures = [Collections.Generic.List[string]]::new()

foreach ($scenario in 'azure-native', 'public-firewall') {
    $path = Join-Path $root "scenarios\$scenario\scripts\Export-DiscoveryInventory.ps1"
    $content = Get-Content $path -Raw

    foreach ($server in 'dc01', 'web01', 'web02', 'sql01') {
        if ($content -notmatch "'$server'") {
            $failures.Add("$scenario discovery exporter does not include $server.")
        }
    }
    if ($content -match '\$serverNames\s*=\s*@\([^\)]*''migrate01''') {
        $failures.Add("$scenario discovery exporter includes migrate01 as a source.")
    }
    if ($content -notmatch 'azure-migrate-discovery-sources\.txt') {
        $failures.Add("$scenario discovery exporter does not create the bulk-entry artifact.")
    }
    if ($content -notmatch 'azure-migrate-source-inventory\.csv') {
        $failures.Add("$scenario discovery exporter does not retain the CSV backup.")
    }
}

if ($failures.Count) {
    throw ($failures -join [Environment]::NewLine)
}

Write-Host 'Azure Migrate discovery artifact contracts passed.'
