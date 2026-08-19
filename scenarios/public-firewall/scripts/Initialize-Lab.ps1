[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$StorageAccountName,
    [Parameter(Mandatory)][string]$KeyVaultName,
    [ValidateSet('Storage', 'Local')][string]$ArtifactSource = 'Storage',
    [string]$DomainControllerIp = '10.50.2.4'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scenarioRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path (Split-Path $scenarioRoot -Parent) -Parent
Set-Location $repoRoot
Import-Module "$PSScriptRoot\Lab.Common.psm1" -Force

if (-not $PSCmdlet.ShouldProcess($ResourceGroupName, 'Configure Windows guests')) {
    return
}

Invoke-LabBootstrap `
    -ResourceGroupName $ResourceGroupName `
    -VmName dc01 `
    -Role DomainController `
    -StorageAccountName $StorageAccountName `
    -KeyVaultName $KeyVaultName `
    -ArtifactSource $ArtifactSource `
    -DomainControllerIp $DomainControllerIp
& az vm restart --resource-group $ResourceGroupName --name dc01 --only-show-errors
Wait-LabVmReady -ResourceGroupName $ResourceGroupName -VmName dc01

Invoke-LabBootstrap `
    -ResourceGroupName $ResourceGroupName `
    -VmName dc01 `
    -Role CertificateAuthority `
    -StorageAccountName $StorageAccountName `
    -KeyVaultName $KeyVaultName `
    -ArtifactSource $ArtifactSource `
    -DomainControllerIp $DomainControllerIp
Invoke-LabBootstrap `
    -ResourceGroupName $ResourceGroupName `
    -VmName dc01 `
    -Role DomainAccounts `
    -StorageAccountName $StorageAccountName `
    -KeyVaultName $KeyVaultName `
    -ArtifactSource $ArtifactSource `
    -DomainControllerIp $DomainControllerIp

foreach ($vmName in 'web01', 'web02', 'sql01', 'migrate01') {
    Invoke-LabBootstrap `
        -ResourceGroupName $ResourceGroupName `
        -VmName $vmName `
        -Role DomainMember `
        -StorageAccountName $StorageAccountName `
        -KeyVaultName $KeyVaultName `
        -ArtifactSource $ArtifactSource `
        -DomainControllerIp $DomainControllerIp
    & az vm restart --resource-group $ResourceGroupName --name $vmName --only-show-errors
    Wait-LabVmReady -ResourceGroupName $ResourceGroupName -VmName $vmName
}

Invoke-LabBootstrap `
    -ResourceGroupName $ResourceGroupName `
    -VmName sql01 `
    -Role Sql `
    -StorageAccountName $StorageAccountName `
    -KeyVaultName $KeyVaultName `
    -ArtifactSource $ArtifactSource `
    -DomainControllerIp $DomainControllerIp
Invoke-LabBootstrap `
    -ResourceGroupName $ResourceGroupName `
    -VmName sql01 `
    -Role SqlDiscovery `
    -StorageAccountName $StorageAccountName `
    -KeyVaultName $KeyVaultName `
    -ArtifactSource $ArtifactSource `
    -DomainControllerIp $DomainControllerIp

foreach ($vmName in 'web01', 'web02') {
    Invoke-LabBootstrap `
        -ResourceGroupName $ResourceGroupName `
        -VmName $vmName `
        -Role Web `
        -StorageAccountName $StorageAccountName `
        -KeyVaultName $KeyVaultName `
        -ArtifactSource $ArtifactSource `
        -DomainControllerIp $DomainControllerIp
}

Invoke-LabBootstrap `
    -ResourceGroupName $ResourceGroupName `
    -VmName dc01 `
    -Role DiscoveryAccess `
    -StorageAccountName $StorageAccountName `
    -KeyVaultName $KeyVaultName `
    -ArtifactSource $ArtifactSource `
    -ComputerName @('web01.corp.contoso.local', 'web02.corp.contoso.local', 'sql01.corp.contoso.local') `
    -DomainControllerIp $DomainControllerIp
Invoke-LabBootstrap `
    -ResourceGroupName $ResourceGroupName `
    -VmName dc01 `
    -Role Traffic `
    -StorageAccountName $StorageAccountName `
    -KeyVaultName $KeyVaultName `
    -ArtifactSource $ArtifactSource `
    -DomainControllerIp $DomainControllerIp
