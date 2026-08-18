[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Bicep', 'Terraform')][string]$Iac = 'Bicep',
    [string]$ResourceGroupName = 'rg-opmlab-nested',
    [string]$Location = 'eastus2',
    [string]$NamePrefix = 'opmlab',
    [securestring]$AdminPassword,
    [switch]$SkipGuestConfiguration,
    [switch]$AutoApprove,
    [string]$GuestMediaManifestPath,
    [string]$HostVmSize = 'Standard_D32s_v5',
    [string]$HostImageUrn = 'MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition:latest',
    [int]$HostDataDiskSizeGb = 1024
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Nested.Common.psm1" -Force

Assert-NestedAzurePreflight -Location $Location -HostVmSize $HostVmSize -HostImageUrn $HostImageUrn
if (-not $SkipGuestConfiguration -and -not $GuestMediaManifestPath) {
    throw 'GuestMediaManifestPath is required unless -SkipGuestConfiguration is specified.'
}
if ($GuestMediaManifestPath) {
    $null = Resolve-NestedMediaManifest -Path $GuestMediaManifestPath
}
if (-not $AdminPassword) {
    $AdminPassword = Read-Host 'Enter the hyperv01 local administrator password' -AsSecureString
}
$plainPassword = [Net.NetworkCredential]::new('', $AdminPassword).Password
$image = $HostImageUrn -split ':'
if ($image.Count -ne 4) {
    throw 'HostImageUrn must use publisher:offer:sku:version.'
}

if (-not $PSCmdlet.ShouldProcess($ResourceGroupName, "Deploy nested virtualization with $Iac")) {
    return
}

$scenarioRoot = Get-NestedScenarioRoot
try {
    if ($Iac -eq 'Bicep') {
        & az group create --name $ResourceGroupName --location $Location `
            --tags scenario=nested-virtualization workload=on-prem-modernization-lab `
            --output none --only-show-errors
        if ($LASTEXITCODE -ne 0) { throw 'Resource group creation failed.' }
        $parameterFile = Join-Path ([IO.Path]::GetTempPath()) "$([Guid]::NewGuid()).parameters.json"
        try {
            @{
                '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
                contentVersion = '1.0.0.0'
                parameters = @{
                    location = @{ value = $Location }
                    namePrefix = @{ value = $NamePrefix }
                    adminPassword = @{ value = $plainPassword }
                    hostVmSize = @{ value = $HostVmSize }
                    hostImage = @{ value = @{
                        publisher = $image[0]; offer = $image[1]; sku = $image[2]; version = $image[3]
                    }}
                    hostDataDiskSizeGb = @{ value = $HostDataDiskSizeGb }
                }
            } | ConvertTo-Json -Depth 8 | Set-Content $parameterFile -Encoding UTF8
            & az deployment group create --resource-group $ResourceGroupName `
                --template-file (Join-Path $scenarioRoot 'infra\bicep\main.bicep') `
                --parameters "@$parameterFile" --output none --only-show-errors
            if ($LASTEXITCODE -ne 0) { throw 'Nested Bicep deployment failed.' }
        } finally {
            Remove-Item $parameterFile -Force -ErrorAction SilentlyContinue
        }
    } else {
        Assert-NestedCommand terraform 'Install Terraform 1.10 or later.'
        if (-not (Get-Module -ListAvailable Az.Compute)) {
            throw 'The nested Terraform host provisioner requires the Az.Compute PowerShell module.'
        }
        Import-Module Az.Accounts -ErrorAction Stop
        if (-not (Get-AzContext)) {
            throw 'Run Connect-AzAccount before the nested Terraform deployment.'
        }
        $terraformRoot = Join-Path $scenarioRoot 'infra\terraform'
        $env:TF_VAR_admin_password = $plainPassword
        try {
            & terraform "-chdir=$terraformRoot" init -input=false
            if ($LASTEXITCODE -ne 0) { throw 'Nested Terraform initialization failed.' }
            $arguments = @(
                "-var=resource_group_name=$ResourceGroupName",
                "-var=location=$Location",
                "-var=name_prefix=$NamePrefix",
                "-var=host_vm_size=$HostVmSize",
                "-var=host_data_disk_size_gb=$HostDataDiskSizeGb",
                "-var=host_image={publisher=`"$($image[0])`",offer=`"$($image[1])`",sku=`"$($image[2])`",version=`"$($image[3])`"}",
                '-input=false'
            )
            if ($AutoApprove) { $arguments += '-auto-approve' }
            & terraform "-chdir=$terraformRoot" apply @arguments
            if ($LASTEXITCODE -ne 0) { throw 'Nested Terraform deployment failed.' }
        } finally {
            Remove-Item Env:\TF_VAR_admin_password -ErrorAction SilentlyContinue
        }
    }
} finally {
    $plainPassword = $null
}

if ($SkipGuestConfiguration) {
    Write-Host 'Nested Azure infrastructure is ready. Stage approved media, then run the scenario Initialize-Lab.ps1 command.'
    return
}

& "$PSScriptRoot\Initialize-Lab.ps1" -ResourceGroupName $ResourceGroupName `
    -NamePrefix $NamePrefix -GuestMediaManifestPath $GuestMediaManifestPath -Confirm:$false
