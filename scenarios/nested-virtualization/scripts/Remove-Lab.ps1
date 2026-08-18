[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [ValidateSet('Bicep', 'Terraform')][string]$Iac = 'Bicep'
)

$ErrorActionPreference = 'Stop'
if (-not $PSCmdlet.ShouldProcess($ResourceGroupName, "Remove nested $Iac lab resources")) { return }
& az group delete --name $ResourceGroupName --yes --no-wait --only-show-errors
if ($LASTEXITCODE -ne 0) { throw 'Nested resource-group deletion request failed.' }
Write-Host "Deletion started for $ResourceGroupName."
