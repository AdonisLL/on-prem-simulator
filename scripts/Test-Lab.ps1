[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('AzureNative', 'NestedVirtualization', 'PublicFirewall')]
    [string]$Scenario,

    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [string]$NamePrefix = 'opmlab',

    [string]$DeployerAddressPrefix,
    [string[]]$AdditionalDeployerAddressPrefix = @()
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Scenario.Dispatch.psm1" -Force
$scenarioScript = Get-LabScenarioScript -Scenario $Scenario -ScriptName 'Test-Lab.ps1'
$arguments = @{ ResourceGroupName = $ResourceGroupName }
if ($Scenario -eq 'NestedVirtualization') {
    $arguments.NamePrefix = $NamePrefix
} elseif ($Scenario -eq 'PublicFirewall') {
    if (-not $PSBoundParameters.ContainsKey('DeployerAddressPrefix')) {
        throw 'DeployerAddressPrefix is required for PublicFirewall validation.'
    }
    $arguments.DeployerAddressPrefix = $DeployerAddressPrefix
    if ($AdditionalDeployerAddressPrefix.Count) {
        $arguments.AdditionalDeployerAddressPrefix = $AdditionalDeployerAddressPrefix
    }
}
& $scenarioScript @arguments
if ($LASTEXITCODE -ne 0) {
    throw "$Scenario readiness validation failed with exit code $LASTEXITCODE."
}
