[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateSet('AzureNative', 'NestedVirtualization', 'PublicFirewall')]
    [string]$Scenario,

    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [ValidateSet('Bicep', 'Terraform')]
    [string]$Iac = 'Bicep'
)

$ErrorActionPreference = 'Stop'
if (-not $PSCmdlet.ShouldProcess(
        "$Scenario lab in $ResourceGroupName",
        'Permanently remove all scenario resources'
    )) {
    return
}

Import-Module "$PSScriptRoot\Scenario.Dispatch.psm1" -Force
$scenarioScript = Get-LabScenarioScript -Scenario $Scenario -ScriptName 'Remove-Lab.ps1'
& $scenarioScript -ResourceGroupName $ResourceGroupName -Iac $Iac -Confirm:$false
if ($LASTEXITCODE -ne 0) {
    throw "$Scenario removal failed with exit code $LASTEXITCODE."
}
