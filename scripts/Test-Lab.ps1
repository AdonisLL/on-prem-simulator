[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('AzureNative', 'NestedVirtualization')]
    [string]$Scenario,

    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [string]$NamePrefix = 'opmlab'
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Scenario.Dispatch.psm1" -Force
$scenarioScript = Get-LabScenarioScript -Scenario $Scenario -ScriptName 'Test-Lab.ps1'
$arguments = @{ ResourceGroupName = $ResourceGroupName }
if ($Scenario -eq 'NestedVirtualization') {
    $arguments.NamePrefix = $NamePrefix
}
& $scenarioScript @arguments
if ($LASTEXITCODE -ne 0) {
    throw "$Scenario readiness validation failed with exit code $LASTEXITCODE."
}
