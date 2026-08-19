[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Scenario.Dispatch.psm1" -Force

$expected = @{
    AzureNative = 'scenarios\azure-native\scripts\Test-Lab.ps1'
    NestedVirtualization = 'scenarios\nested-virtualization\scripts\Test-Lab.ps1'
    PublicFirewall = 'scenarios\public-firewall\scripts\Test-Lab.ps1'
}

foreach ($scenario in $expected.Keys) {
    $resolved = Get-LabScenarioScript -Scenario $scenario -ScriptName 'Test-Lab.ps1'
    if (-not $resolved.EndsWith($expected[$scenario], [StringComparison]::OrdinalIgnoreCase)) {
        throw "$scenario resolved to unexpected path $resolved."
    }
}

$testCommand = Get-Command "$PSScriptRoot\Test-Lab.ps1"
if (-not $testCommand.Parameters.Scenario.Attributes.Mandatory) {
    throw 'The root readiness command does not require scenario selection.'
}

$invalidScenarioRejected = $false
try {
    Get-LabScenarioScript -Scenario Unsupported -ScriptName 'Test-Lab.ps1'
} catch {
    $invalidScenarioRejected = $true
}
if (-not $invalidScenarioRejected) {
    throw 'The scenario resolver accepted an unsupported scenario.'
}

Write-Host 'Root scenario dispatch contract passed.'
