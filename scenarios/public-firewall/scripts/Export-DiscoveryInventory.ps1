[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [string]$OutputPath = (
        Join-Path (
            Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
        ) 'artifacts\azure-migrate-source-inventory.csv'
    ),
    [string]$BulkOutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Lab.Common.psm1" -Force

$serverNames = @('dc01', 'web01', 'web02', 'sql01')
if ([string]::IsNullOrWhiteSpace($BulkOutputPath)) {
    $BulkOutputPath = Join-Path (Split-Path $OutputPath) 'azure-migrate-discovery-sources.txt'
}

$privateIpMap = Get-LabVmPrivateIpMap `
    -ResourceGroupName $ResourceGroupName `
    -VmNames $serverNames

$records = foreach ($vmName in $serverNames) {
    [pscustomobject]@{
        'Server name'               = "$vmName.corp.contoso.local"
        'IP address'                = $privateIpMap[$vmName]
        'Operating system'          = 'Windows Server'
        'Credentials friendly name' = 'Lab domain discovery'
    }
}

New-Item -Path (Split-Path $OutputPath) -ItemType Directory -Force | Out-Null
$records | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
$records.'Server name' | Set-Content -Path $BulkOutputPath -Encoding UTF8

try {
    $allPrivateIps = Get-LabVmPrivateIpMap `
        -ResourceGroupName $ResourceGroupName `
        -VmNames (Get-LabScenarioVmNames)
    $firewallData = Get-LabFirewallEndpointMap `
        -ResourceGroupName $ResourceGroupName `
        -VmPrivateIpMap $allPrivateIps
    Write-Host (Format-LabEndpointSummary -FirewallData $firewallData)
} catch {
    Write-Warning "Could not resolve the Azure Firewall endpoint summary. $($_.Exception.Message)"
}

Write-Host "Azure Migrate bulk-entry sources written to $BulkOutputPath."
Write-Host "Backup CSV source inventory written to $OutputPath. Copy its values into the CSV template downloaded from the current appliance."
