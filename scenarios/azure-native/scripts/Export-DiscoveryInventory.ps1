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

$ErrorActionPreference = 'Stop'
$serverNames = @('dc01', 'web01', 'web02', 'sql01')
if ([string]::IsNullOrWhiteSpace($BulkOutputPath)) {
    $BulkOutputPath = Join-Path (Split-Path $OutputPath) 'azure-migrate-discovery-sources.txt'
}
$records = foreach ($vmName in $serverNames) {
    $ip = & az vm list-ip-addresses `
        --resource-group $ResourceGroupName `
        --name $vmName `
        --query "[0].virtualMachine.network.privateIpAddresses[0]" `
        --output tsv `
        --only-show-errors
    if (-not $ip) { throw "Could not resolve the private IP for $vmName." }
    [pscustomobject]@{
        'Server name'              = "$vmName.corp.contoso.local"
        'IP address'               = $ip
        'Operating system'         = 'Windows Server'
        'Credentials friendly name' = 'Lab domain discovery'
    }
}
New-Item -Path (Split-Path $OutputPath) -ItemType Directory -Force | Out-Null
$records | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
$records.'Server name' | Set-Content -Path $BulkOutputPath -Encoding UTF8
Write-Host "Azure Migrate bulk-entry sources written to $BulkOutputPath."
Write-Host "Backup CSV source inventory written to $OutputPath. Copy its values into the CSV template downloaded from the current appliance."
