[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [securestring]$AdminPassword,
    [switch]$Finalize
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scenarioRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path (Split-Path $scenarioRoot -Parent) -Parent
Set-Location $repoRoot
Import-Module "$PSScriptRoot\Lab.Common.psm1" -Force

Assert-LabCommand az 'Install Azure CLI and run az login.'
$keyVault = & az keyvault list --resource-group $ResourceGroupName --query '[0].name' --output tsv --only-show-errors
$vnet = & az network vnet list --resource-group $ResourceGroupName --query '[0].name' --output tsv --only-show-errors
if (-not $keyVault -or -not $vnet) {
    throw 'Could not resolve the Key Vault or virtual network in the resource group.'
}

$vaultId = & az keyvault show --resource-group $ResourceGroupName --name $keyVault --query id --output tsv --only-show-errors
$dcPrincipalId = & az vm identity show --resource-group $ResourceGroupName --name dc01 --query principalId --output tsv --only-show-errors
if (-not $vaultId -or -not $dcPrincipalId) {
    throw 'Could not resolve the Key Vault or dc01 managed identity.'
}

if ($Finalize) {
    & az role assignment delete --assignee-object-id $dcPrincipalId --role 'Key Vault Secrets Officer' --scope $vaultId --only-show-errors
    & az role assignment create --assignee-object-id $dcPrincipalId --assignee-principal-type ServicePrincipal --role 'Key Vault Secrets User' --scope $vaultId --output none --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'Failed to restore least-privilege Key Vault access for dc01.' }
    Write-Host 'Key Vault recovery finalized. dc01 now has Key Vault Secrets User access.'
    return
}

& az network vnet subnet update `
    --resource-group $ResourceGroupName `
    --vnet-name $vnet `
    --name snet-management `
    --private-endpoint-network-policies Disabled `
    --output none `
    --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Failed to enable private endpoints on snet-management.' }

$zoneName = 'privatelink.vaultcore.azure.net'
& az network private-dns zone create --resource-group $ResourceGroupName --name $zoneName --output none --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Failed to create the Key Vault private DNS zone.' }
& az network private-dns link vnet create `
    --resource-group $ResourceGroupName `
    --zone-name $zoneName `
    --name key-vault-link `
    --virtual-network $vnet `
    --registration-enabled false `
    --output none `
    --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Failed to link the Key Vault private DNS zone to the lab VNet.' }

$privateEndpointName = "pep-$keyVault"
$privateEndpointId = & az network private-endpoint show `
    --resource-group $ResourceGroupName `
    --name $privateEndpointName `
    --query id `
    --output tsv `
    --only-show-errors 2>$null
if (-not $privateEndpointId) {
    & az network private-endpoint create `
        --resource-group $ResourceGroupName `
        --name $privateEndpointName `
        --location (& az group show --name $ResourceGroupName --query location --output tsv) `
        --vnet-name $vnet `
        --subnet snet-management `
        --private-connection-resource-id $vaultId `
        --group-id vault `
        --connection-name key-vault `
        --output none `
        --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'Failed to create the Key Vault private endpoint.' }
}

$dnsZoneGroupId = & az network private-endpoint dns-zone-group show `
    --resource-group $ResourceGroupName `
    --endpoint-name $privateEndpointName `
    --name default `
    --query id `
    --output tsv `
    --only-show-errors 2>$null
if (-not $dnsZoneGroupId) {
    & az network private-endpoint dns-zone-group create `
        --resource-group $ResourceGroupName `
        --endpoint-name $privateEndpointName `
        --name default `
        --private-dns-zone $zoneName `
        --zone-name key-vault `
        --output none `
        --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'Failed to associate private DNS with the Key Vault private endpoint.' }
}

foreach ($vmName in 'web01', 'web02', 'sql01', 'migrate01') {
    $principalId = & az vm identity show --resource-group $ResourceGroupName --name $vmName --query principalId --output tsv --only-show-errors
    & az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal --role 'Key Vault Secrets User' --scope $vaultId --output none --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw "Failed to assign Key Vault Secrets User to $vmName." }
}
& az role assignment create --assignee-object-id $dcPrincipalId --assignee-principal-type ServicePrincipal --role 'Key Vault Secrets Officer' --scope $vaultId --output none --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Failed to assign temporary secret-seeding access to dc01.' }

if (-not $AdminPassword) {
    $AdminPassword = Read-Host 'Enter a new labadmin password to apply to all lab VMs' -AsSecureString
}
$plainAdminPassword = [Net.NetworkCredential]::new('', $AdminPassword).Password
try {
    foreach ($vmName in 'dc01', 'web01', 'web02', 'sql01', 'migrate01') {
        & az vm user update `
            --resource-group $ResourceGroupName `
            --name $vmName `
            --username labadmin `
            --password $plainAdminPassword `
            --output none `
            --only-show-errors
        if ($LASTEXITCODE -ne 0) { throw "Failed to reset the labadmin password on $vmName." }
    }
} finally {
    $plainAdminPassword = $null
}

Write-Host "Private Key Vault access is ready. Copy configuration\powershell\Set-LabKeyVaultSecrets.ps1 to dc01 and run it there as Administrator with -KeyVaultName $keyVault."
Write-Host "Enter the same labadmin password when prompted. After the secrets are created, run: .\scenarios\azure-native\scripts\Repair-KeyVaultAccess.ps1 -ResourceGroupName $ResourceGroupName -Finalize"