Set-StrictMode -Version Latest

function Get-LabScenarioScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('AzureNative', 'NestedVirtualization')]
        [string]$Scenario,

        [Parameter(Mandatory)]
        [ValidateSet('Deploy-Lab.ps1', 'Test-Lab.ps1', 'Reset-Lab.ps1', 'Remove-Lab.ps1')]
        [string]$ScriptName
    )

    $scenarioDirectory = switch ($Scenario) {
        'AzureNative' { 'azure-native' }
        'NestedVirtualization' { 'nested-virtualization' }
    }

    $repositoryRoot = Split-Path $PSScriptRoot -Parent
    $scriptPath = Join-Path $repositoryRoot "scenarios\$scenarioDirectory\scripts\$ScriptName"
    if (-not (Test-Path $scriptPath -PathType Leaf)) {
        throw "Scenario '$Scenario' does not provide $ScriptName at $scriptPath."
    }

    return $scriptPath
}

Export-ModuleMember -Function Get-LabScenarioScript
