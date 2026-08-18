[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [ValidateSet('Bicep', 'Terraform')][string]$Iac = 'Bicep'
)

$ErrorActionPreference = 'Stop'
if (-not $PSCmdlet.ShouldProcess($ResourceGroupName, 'Permanently remove all lab resources')) {
    return
}

# Every lab resource is intentionally scoped to one disposable resource group.
# Group deletion also works after partial deployments when IaC state is missing.
& az group delete --name $ResourceGroupName --yes --no-wait
if ($LASTEXITCODE -ne 0) { throw 'Resource-group deletion request failed.' }
Write-Host "Deletion started for $ResourceGroupName. Verify completion in Azure before ending the workshop."
