[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [string]$NamePrefix = 'opmlab',
    [Parameter(Mandatory)][string]$GuestMediaManifestPath,
    [switch]$SkipGuestConfiguration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Nested.Common.psm1" -Force
$definitionJson = Get-Content (Join-Path (Get-NestedScenarioRoot) 'scenario-definition.json') -Raw
$manifest = Resolve-NestedMediaManifest -Path $GuestMediaManifestPath
$hostVmName = Get-NestedHostVmName -NamePrefix $NamePrefix

if (-not $PSCmdlet.ShouldProcess($hostVmName, 'Initialize Hyper-V and inner guests')) {
    return
}

$parameters = @(
    "ScenarioDefinitionBase64=$(ConvertTo-NestedBase64 $definitionJson)",
    "GuestMediaManifestBase64=$(ConvertTo-NestedBase64 $manifest.Json)",
    "SkipGuestConfiguration=$([bool]$SkipGuestConfiguration)"
)
$result = Invoke-NestedHostScript -ResourceGroupName $ResourceGroupName `
    -HostVmName $hostVmName -ScriptName 'Initialize-HyperVHost.ps1' -Parameters $parameters
$message = ($result.value.message -join [Environment]::NewLine)
if ($message -match 'NESTED_HOST_RESTART_REQUIRED') {
    & az vm restart --resource-group $ResourceGroupName --name $hostVmName --only-show-errors
    if ($LASTEXITCODE -ne 0) { throw 'Hyper-V host restart failed.' }
    Wait-NestedAzureVmReady -ResourceGroupName $ResourceGroupName -HostVmName $hostVmName
    $result = Invoke-NestedHostScript -ResourceGroupName $ResourceGroupName `
        -HostVmName $hostVmName -ScriptName 'Initialize-HyperVHost.ps1' -Parameters $parameters
}
$result.value.message | ForEach-Object { Write-Host $_ }
