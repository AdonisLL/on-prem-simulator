[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('AzureNative', 'NestedVirtualization')]
    [string]$Scenario,

    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [string]$NamePrefix = 'opmlab'
)

$ErrorActionPreference = 'Stop'
if (-not $PSCmdlet.ShouldProcess(
        "$Scenario lab in $ResourceGroupName",
        'Reset scenario data and synthetic traffic'
    )) {
    return
}

Import-Module "$PSScriptRoot\Scenario.Dispatch.psm1" -Force
$scenarioScript = Get-LabScenarioScript -Scenario $Scenario -ScriptName 'Reset-Lab.ps1'
$arguments = @{ ResourceGroupName = $ResourceGroupName; Confirm = $false }
if ($Scenario -eq 'NestedVirtualization') {
    $arguments.NamePrefix = $NamePrefix
}
& $scenarioScript @arguments
if ($LASTEXITCODE -ne 0) {
    throw "$Scenario reset failed with exit code $LASTEXITCODE."
}
