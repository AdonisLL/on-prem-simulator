[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [string]$NamePrefix = 'opmlab'
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Nested.Common.psm1" -Force
$definitionJson = Get-Content (Join-Path (Get-NestedScenarioRoot) 'scenario-definition.json') -Raw
$result = Invoke-NestedHostScript -ResourceGroupName $ResourceGroupName `
    -HostVmName (Get-NestedHostVmName $NamePrefix) -ScriptName 'Test-HyperVHost.ps1' `
    -Parameters @("ScenarioDefinitionBase64=$(ConvertTo-NestedBase64 $definitionJson)")
$result.value.message | ForEach-Object { Write-Host $_ }
