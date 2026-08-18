[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Compute -ErrorAction Stop
if (-not (Get-AzContext)) {
    throw 'Authenticate with Connect-AzAccount before terraform destroy.'
}

$vm = Get-AzVM -ResourceGroupName $env:RESOURCE_GROUP_NAME -Name $env:VM_NAME -ErrorAction SilentlyContinue
if ($vm) {
    $osDiskName = $vm.StorageProfile.OsDisk.Name
    Remove-AzVM -ResourceGroupName $env:RESOURCE_GROUP_NAME -Name $env:VM_NAME -Force | Out-Null
    if ($osDiskName) {
        Remove-AzDisk -ResourceGroupName $env:RESOURCE_GROUP_NAME -DiskName $osDiskName -Force -ErrorAction SilentlyContinue
    }
}
