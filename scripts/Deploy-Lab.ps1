[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('AzureNative', 'NestedVirtualization')]
    [string]$Scenario,

    [ValidateSet('Bicep', 'Terraform')]
    [string]$Iac = 'Bicep',

    [string]$ResourceGroupName = 'rg-opmlab-source',
    [string]$Location = 'eastus2',
    [string]$NamePrefix = 'opmlab',
    [string]$SqlImageUrn = 'MicrosoftSQLServer:sql2016sp3-ws2019:sqldev:latest',
    [securestring]$AdminPassword,
    [switch]$SkipGuestConfiguration,
    [switch]$AutoApprove,
    [string]$GuestMediaManifestPath,
    [string]$HostVmSize = 'Standard_D32s_v5',
    [string]$HostImageUrn = 'MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition:latest',
    [int]$HostDataDiskSizeGb = 1024,
    [switch]$UseTemporaryPolicyExemption
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Scenario.Dispatch.psm1" -Force
$scenarioScript = Get-LabScenarioScript -Scenario $Scenario -ScriptName 'Deploy-Lab.ps1'

$arguments = @{
    Iac = $Iac
    ResourceGroupName = $ResourceGroupName
    Location = $Location
    NamePrefix = $NamePrefix
}
if ($PSBoundParameters.ContainsKey('AdminPassword')) {
    $arguments.AdminPassword = $AdminPassword
}
if ($SkipGuestConfiguration) {
    $arguments.SkipGuestConfiguration = $true
}
if ($AutoApprove) {
    $arguments.AutoApprove = $true
}
if ($Scenario -eq 'AzureNative') {
    $arguments.SqlImageUrn = $SqlImageUrn
    if ($UseTemporaryPolicyExemption) {
        $arguments.UseTemporaryPolicyExemption = $true
    }
} else {
    if ($UseTemporaryPolicyExemption) {
        throw 'UseTemporaryPolicyExemption is currently supported only by the AzureNative scenario.'
    }
    $arguments.HostVmSize = $HostVmSize
    $arguments.HostImageUrn = $HostImageUrn
    $arguments.HostDataDiskSizeGb = $HostDataDiskSizeGb
    if ($PSBoundParameters.ContainsKey('GuestMediaManifestPath')) {
        $arguments.GuestMediaManifestPath = $GuestMediaManifestPath
    }
}

if (-not $PSCmdlet.ShouldProcess(
        "$Scenario lab in $ResourceGroupName",
        "Deploy with $Iac"
    )) {
    return
}

& $scenarioScript @arguments -Confirm:$false
if ($LASTEXITCODE -ne 0) {
    throw "$Scenario deployment failed with exit code $LASTEXITCODE."
}
