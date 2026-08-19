[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [ValidateSet('Bicep', 'Terraform')][string]$Iac = 'Bicep'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $PSCmdlet.ShouldProcess($ResourceGroupName, 'Permanently remove all lab resources')) {
    return
}

& az group delete --name $ResourceGroupName --yes --no-wait
if ($LASTEXITCODE -ne 0) {
    throw 'Resource-group deletion request failed.'
}

Write-Host "Deletion started for $ResourceGroupName. Verify completion in Azure before ending the workshop."
