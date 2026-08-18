[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$required = 'RESOURCE_GROUP_NAME','LOCATION','VM_NAME','NIC_ID','DATA_DISK_ID',
    'HOST_VM_SIZE','HOST_IMAGE_PUBLISHER','HOST_IMAGE_OFFER','HOST_IMAGE_SKU',
    'HOST_IMAGE_VERSION','ADMIN_USERNAME','ADMIN_PASSWORD'
foreach ($name in $required) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
        throw "Missing required environment variable $name."
    }
}

foreach ($module in 'Az.Accounts','Az.Compute') {
    Import-Module $module -ErrorAction Stop
}
if (-not (Get-AzContext)) {
    throw 'Authenticate with Connect-AzAccount before terraform apply.'
}

$vm = Get-AzVM -ResourceGroupName $env:RESOURCE_GROUP_NAME -Name $env:VM_NAME -ErrorAction SilentlyContinue
if (-not $vm) {
    $securePassword = ConvertTo-SecureString $env:ADMIN_PASSWORD -AsPlainText -Force
    $credential = [pscredential]::new($env:ADMIN_USERNAME, $securePassword)
    $diskName = ($env:DATA_DISK_ID -split '/')[-1]
    $vmConfig = New-AzVMConfig -VMName $env:VM_NAME -VMSize $env:HOST_VM_SIZE
    $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Windows -ComputerName 'hyperv01' -Credential $credential -ProvisionVMAgent -EnableAutoUpdate
    $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName $env:HOST_IMAGE_PUBLISHER -Offer $env:HOST_IMAGE_OFFER -Skus $env:HOST_IMAGE_SKU -Version $env:HOST_IMAGE_VERSION
    $vmConfig = Set-AzVMOSDisk -VM $vmConfig -CreateOption FromImage -StorageAccountType Premium_LRS
    $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $env:NIC_ID -Primary
    $vmConfig = Add-AzVMDataDisk -VM $vmConfig -Name $diskName -ManagedDiskId $env:DATA_DISK_ID -Lun 0 -CreateOption Attach
    $vmConfig = Set-AzVMIdentity -VM $vmConfig -Type SystemAssigned
    try {
        New-AzVM -ResourceGroupName $env:RESOURCE_GROUP_NAME -Location $env:LOCATION -VM $vmConfig -DisableBginfoExtension | Out-Null
    } finally {
        $securePassword = $null
        $credential = $null
        Remove-Item Env:\ADMIN_PASSWORD -ErrorAction SilentlyContinue
    }
}
