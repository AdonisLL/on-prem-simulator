[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$rootDeploy = Get-Command "$root\scripts\Deploy-Lab.ps1"
$scenarioDeploy = Get-Command "$root\scenarios\azure-native\scripts\Deploy-Lab.ps1"
$scenarioText = Get-Content "$root\scenarios\azure-native\scripts\Deploy-Lab.ps1" -Raw
$bicepMain = Get-Content "$root\scenarios\azure-native\infra\bicep\main.bicep" -Raw
$bicepShared = Get-Content "$root\scenarios\azure-native\infra\bicep\modules\shared.bicep" -Raw
$terraformVariables = Get-Content "$root\scenarios\azure-native\infra\terraform\variables.tf" -Raw
$terraformMain = Get-Content "$root\scenarios\azure-native\infra\terraform\main.tf" -Raw

$requirements = @{
    'root dispatcher exposes exemption switch' =
        $rootDeploy.Parameters.ContainsKey('UseTemporaryPolicyExemption')
    'Azure-native deployment exposes exemption switch' =
        $scenarioDeploy.Parameters.ContainsKey('UseTemporaryPolicyExemption')
    'Bicep exposes temporary access parameter' =
        $bicepMain -match 'param enableTemporaryDeploymentAccess bool = false'
    'Bicep gates Key Vault and Storage public access' =
        ([regex]::Matches($bicepShared, "publicNetworkAccess:\s*enableTemporaryDeploymentAccess \? 'Enabled' : 'Disabled'").Count -eq 2)
    'Terraform exposes temporary access variable' =
        $terraformVariables -match 'variable "enable_temporary_deployment_access"'
    'Terraform tags only the resource group for exemption' =
        $terraformMain -match 'SecurityControl = "Ignore"'
    'Terraform gates both public endpoints' =
        ([regex]::Matches($terraformMain, 'public_network_access_enabled\s*=\s*var\.enable_temporary_deployment_access').Count -eq 2)
    'cleanup disables Key Vault public access' =
        ($scenarioText -match 'az keyvault update[\s\S]+--public-network-access Disabled' -and
         $scenarioText -match 'az keyvault update[\s\S]+--default-action Deny')
    'cleanup disables Storage public access' =
        $scenarioText -match 'az storage account update[\s\S]+--public-network-access Disabled'
    'cleanup restores or deletes the exemption tag' =
        ($scenarioText -match 'az tag update[\s\S]+--operation Merge' -and
         $scenarioText -match 'az tag update[\s\S]+--operation Delete')
    'cleanup preserves primary deployment failures' =
        ($scenarioText -match '\$deploymentError = \$_' -and
         $scenarioText -match 'Cleanup failures:')
}

$failed = $requirements.GetEnumerator() | Where-Object { -not $_.Value }
if ($failed) {
    throw (($failed | ForEach-Object Key) -join [Environment]::NewLine)
}

Write-Host 'Temporary policy exemption contract passed.'
