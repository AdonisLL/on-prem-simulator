[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Bicep', 'Terraform')][string]$Iac = 'Bicep',
    [string]$ResourceGroupName = 'rg-opmlab-public',
    [string]$Location = 'eastus2',
    [string]$NamePrefix = 'opmlab',
    [string]$SqlImageUrn = 'MicrosoftSQLServer:sql2016sp3-ws2019:sqldev:latest',
    [securestring]$AdminPassword,
    [switch]$SkipGuestConfiguration,
    [switch]$AutoApprove,
    [Parameter(Mandatory)][string]$DeployerAddressPrefix,
    [switch]$AllowNon32DeployerPrefix,
    [switch]$UseTemporaryPolicyExemption = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scenarioRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path (Split-Path $scenarioRoot -Parent) -Parent
Set-Location $repoRoot
Import-Module "$PSScriptRoot\Lab.Common.psm1" -Force

Assert-LabCommand az 'Install Azure CLI and run az login.'
if ($Iac -eq 'Terraform') {
    Assert-LabCommand terraform 'Install Terraform 1.10 or later.'
}

$infrastructurePath = if ($Iac -eq 'Bicep') {
    Join-Path $scenarioRoot 'infra\bicep\main.bicep'
} else {
    Join-Path $scenarioRoot 'infra\terraform\main.tf'
}
if (-not (Test-Path $infrastructurePath -PathType Leaf)) {
    throw "PublicFirewall $Iac infrastructure is missing at $infrastructurePath."
}

$DeployerAddressPrefix = Assert-LabIpv4Cidr `
    -AddressPrefix $DeployerAddressPrefix `
    -AllowNon32:$AllowNon32DeployerPrefix

$account = & az account show --query id --output tsv --only-show-errors
if ($LASTEXITCODE -ne 0 -or -not $account) {
    throw 'Azure CLI is not authenticated. Run az login and select a subscription.'
}

$deploymentId = & az group show `
    --name $ResourceGroupName `
    --query tags.deploymentId `
    --output tsv `
    --only-show-errors 2>$null
if (-not $deploymentId) {
    $deploymentId = [Guid]::NewGuid().ToString('N').Substring(0, 10)
}

$previousSecurityControlTag = $null
if ($UseTemporaryPolicyExemption) {
    $previousSecurityControlTag = Get-LabResourceGroupSecurityControlTag `
        -ResourceGroupName $ResourceGroupName `
        -Optional
}

$sqlImageParts = $SqlImageUrn -split ':'
if ($sqlImageParts.Count -ne 4 -or $sqlImageParts -contains '') {
    throw 'SqlImageUrn must use the publisher:offer:sku:version format.'
}
$sqlImage = @{
    publisher = $sqlImageParts[0]
    offer     = $sqlImageParts[1]
    sku       = $sqlImageParts[2]
    version   = $sqlImageParts[3]
}

& az vm image show --location $Location --urn $SqlImageUrn --only-show-errors --output none
if ($LASTEXITCODE -ne 0) {
    throw "The required SQL image $SqlImageUrn is unavailable in $Location. Select a supported region or pass -SqlImageUrn with an available image."
}

if (-not $AdminPassword) {
    $AdminPassword = Read-Host 'Enter the labadmin password' -AsSecureString
}

$plainAdminPassword = [Net.NetworkCredential]::new('', $AdminPassword).Password
$servicePassword = New-LabPassword
$discoveryPassword = New-LabPassword
$sqlDiscoveryPassword = New-LabPassword

$artifactRoot = Join-Path $repoRoot 'artifacts'
$scratchRoot = New-LabScratchDirectory -ArtifactRoot $artifactRoot
$deploymentError = $null
$cleanupFailures = [Collections.Generic.List[string]]::new()
$temporaryPolicyExemptionActivated = $false

try {
    $artifacts = Build-LabArtifacts -RepoRoot $repoRoot -ScratchRoot $scratchRoot

    if (-not $PSCmdlet.ShouldProcess($ResourceGroupName, "Deploy the $Iac public-firewall lab")) {
        return
    }

    if ($Iac -eq 'Bicep') {
        $existingGroup = & az group show --name $ResourceGroupName --output json --only-show-errors 2>$null | ConvertFrom-Json
        $resourceGroupTags = @{}
        if ($existingGroup -and $existingGroup.tags) {
            foreach ($tag in $existingGroup.tags.PSObject.Properties) {
                $resourceGroupTags[$tag.Name] = [string]$tag.Value
            }
        }
        $resourceGroupTags.workload = 'on-prem-modernization-lab'
        $resourceGroupTags.environment = 'lab'
        $resourceGroupTags.deploymentId = $deploymentId
        if ($UseTemporaryPolicyExemption) {
            $resourceGroupTags.SecurityControl = 'Ignore'
            $temporaryPolicyExemptionActivated = $true
        }

        $tagArguments = foreach ($key in $resourceGroupTags.Keys) {
            "$key=$($resourceGroupTags[$key])"
        }
        & az group create `
            --name $ResourceGroupName `
            --location $Location `
            --tags $tagArguments `
            --output none `
            --only-show-errors
        if ($LASTEXITCODE -ne 0) {
            throw 'Resource group creation failed.'
        }

        $parameterFile = Join-Path $scratchRoot 'deployment-parameters.json'
        try {
            @{
                '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
                contentVersion = '1.0.0.0'
                parameters     = @{
                    namePrefix                     = @{ value = $NamePrefix }
                    location                       = @{ value = $Location }
                    deploymentId                   = @{ value = $deploymentId }
                    adminUsername                  = @{ value = 'labadmin' }
                    adminPassword                  = @{ value = $plainAdminPassword }
                    sqlImage                       = @{ value = $sqlImage }
                    deployerAddressPrefix          = @{ value = $DeployerAddressPrefix }
                    enableTemporaryDeploymentAccess = @{ value = [bool]$UseTemporaryPolicyExemption }
                }
            } | ConvertTo-Json -Depth 8 | Set-Content -Path $parameterFile -Encoding UTF8

            & az deployment group create `
                --resource-group $ResourceGroupName `
                --template-file $infrastructurePath `
                --parameters "@$parameterFile" `
                --only-show-errors `
                --output none
            if ($LASTEXITCODE -ne 0) {
                throw 'Bicep deployment failed.'
            }
        } finally {
            Remove-Item $parameterFile -Force -ErrorAction SilentlyContinue
        }
    } else {
        $env:TF_VAR_admin_password = $plainAdminPassword
        $env:TF_VAR_sql_image = $sqlImage | ConvertTo-Json -Compress
        $env:ARM_SUBSCRIPTION_ID = $account
        $temporaryAccessValue = ([bool]$UseTemporaryPolicyExemption).ToString().ToLowerInvariant()
        if ($UseTemporaryPolicyExemption) {
            $temporaryPolicyExemptionActivated = $true
        }

        try {
            $terraformRoot = Join-Path $scenarioRoot 'infra\terraform'
            & terraform "-chdir=$terraformRoot" init -input=false
            if ($LASTEXITCODE -ne 0) {
                throw 'Terraform initialization failed.'
            }

            $terraformArguments = @(
                "-chdir=$terraformRoot"
                'apply'
                "-var=resource_group_name=$ResourceGroupName"
                "-var=location=$Location"
                "-var=name_prefix=$NamePrefix"
                "-var=deployment_id=$deploymentId"
                "-var=deployer_address_prefix=$DeployerAddressPrefix"
                "-var=enable_temporary_deployment_access=$temporaryAccessValue"
                '-input=false'
            )
            if ($AutoApprove) {
                $terraformArguments += '-auto-approve'
            }

            & terraform @terraformArguments
            if ($LASTEXITCODE -ne 0) {
                throw 'Terraform deployment failed.'
            }
        } finally {
            Remove-Item Env:\TF_VAR_admin_password -ErrorAction SilentlyContinue
            Remove-Item Env:\TF_VAR_sql_image -ErrorAction SilentlyContinue
            Remove-Item Env:\ARM_SUBSCRIPTION_ID -ErrorAction SilentlyContinue
        }
    }

    $storageAccount = Resolve-LabStorageAccountName -ResourceGroupName $ResourceGroupName
    $keyVault = Resolve-LabKeyVaultName -ResourceGroupName $ResourceGroupName
    $storageId = & az storage account show --resource-group $ResourceGroupName --name $storageAccount --query id --output tsv --only-show-errors
    if ($LASTEXITCODE -ne 0 -or -not $storageId) {
        throw "Could not resolve Storage account $storageAccount."
    }

    $vaultId = & az keyvault show --resource-group $ResourceGroupName --name $keyVault --query id --output tsv --only-show-errors
    if ($LASTEXITCODE -ne 0 -or -not $vaultId) {
        throw "Could not resolve Key Vault $keyVault."
    }

    $privateIpMap = Get-LabVmPrivateIpMap `
        -ResourceGroupName $ResourceGroupName `
        -VmNames (Get-LabScenarioVmNames)

    $firewallData = Get-LabFirewallEndpointMap `
        -ResourceGroupName $ResourceGroupName `
        -VmPrivateIpMap $privateIpMap
    Assert-LabFirewallEndpointContract `
        -FirewallData $firewallData `
        -DeployerAddressPrefix $DeployerAddressPrefix

    $expectedDeploymentSources = Get-LabExpectedDeploymentAccessSources `
        -DeployerAddressPrefix $DeployerAddressPrefix `
        -FirewallData $firewallData

    $keyVaultNetworkRules = Get-LabKeyVaultNetworkRules `
        -ResourceGroupName $ResourceGroupName `
        -KeyVaultName $keyVault
    Assert-LabRestrictedDeploymentAccess `
        -ResourceType 'Key Vault' `
        -NetworkRules $keyVaultNetworkRules `
        -ExpectedAddressPrefixes $expectedDeploymentSources

    $storageNetworkRules = Get-LabStorageNetworkRules `
        -ResourceGroupName $ResourceGroupName `
        -StorageAccountName $storageAccount
    Assert-LabRestrictedDeploymentAccess `
        -ResourceType 'Storage account' `
        -NetworkRules $storageNetworkRules `
        -ExpectedAddressPrefixes $expectedDeploymentSources

    $principal = Get-LabCurrentPrincipal
    Ensure-LabRoleAssignment `
        -AssigneeObjectId $principal.ObjectId `
        -AssigneePrincipalType $principal.PrincipalType `
        -RoleDefinitionName 'Key Vault Secrets Officer' `
        -Scope $vaultId
    Ensure-LabRoleAssignment `
        -AssigneeObjectId $principal.ObjectId `
        -AssigneePrincipalType $principal.PrincipalType `
        -RoleDefinitionName 'Storage Blob Data Contributor' `
        -Scope $storageId

    $artifactUploaded = $false
    $uploadError = $null
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        $uploadError = & az storage blob upload `
            --account-name $storageAccount `
            --container-name artifacts `
            --name lab.zip `
            --file $artifacts.LabArchive `
            --auth-mode login `
            --overwrite true `
            --only-show-errors `
            --output none 2>&1
        if ($LASTEXITCODE -eq 0) {
            $artifactUploaded = $true
            break
        }

        if ($attempt -lt 20) {
            Write-Host "Artifact upload is not available yet; retrying in 15 seconds ($attempt/20)."
            Start-Sleep -Seconds 15
        }
    }
    if (-not $artifactUploaded) {
        throw "Artifact upload failed after waiting for Storage Blob Data Contributor propagation. Azure CLI error: $uploadError"
    }

    Set-LabKeyVaultSecretFromMemory `
        -VaultName $keyVault `
        -Name 'admin-password' `
        -Value $plainAdminPassword `
        -ScratchRoot $scratchRoot
    Set-LabKeyVaultSecretFromMemory `
        -VaultName $keyVault `
        -Name 'web-service-password' `
        -Value $servicePassword `
        -ScratchRoot $scratchRoot
    Set-LabKeyVaultSecretFromMemory `
        -VaultName $keyVault `
        -Name 'migrate-discovery-password' `
        -Value $discoveryPassword `
        -ScratchRoot $scratchRoot
    Set-LabKeyVaultSecretFromMemory `
        -VaultName $keyVault `
        -Name 'sql-discovery-password' `
        -Value $sqlDiscoveryPassword `
        -ScratchRoot $scratchRoot

    foreach ($vmName in Get-LabScenarioVmNames) {
        $principalId = & az vm identity show `
            --resource-group $ResourceGroupName `
            --name $vmName `
            --query principalId `
            --output tsv `
            --only-show-errors
        if ($LASTEXITCODE -ne 0 -or -not $principalId) {
            throw "Could not resolve the managed identity for $vmName."
        }

        Ensure-LabRoleAssignment `
            -AssigneeObjectId $principalId `
            -AssigneePrincipalType 'ServicePrincipal' `
            -RoleDefinitionName 'Storage Blob Data Reader' `
            -Scope $storageId
        Ensure-LabRoleAssignment `
            -AssigneeObjectId $principalId `
            -AssigneePrincipalType 'ServicePrincipal' `
            -RoleDefinitionName 'Key Vault Secrets User' `
            -Scope $vaultId
    }
    Start-Sleep -Seconds 30

    if (-not $SkipGuestConfiguration) {
        & "$PSScriptRoot\Initialize-Lab.ps1" `
            -ResourceGroupName $ResourceGroupName `
            -StorageAccountName $storageAccount `
            -KeyVaultName $keyVault `
            -ArtifactSource Storage
    }

    & "$PSScriptRoot\Export-DiscoveryInventory.ps1" -ResourceGroupName $ResourceGroupName
    Write-Host (Format-LabEndpointSummary -FirewallData $firewallData)
    if ($SkipGuestConfiguration) {
        Write-Host "Guest configuration was skipped. Re-run .\scripts\Deploy-Lab.ps1 -Scenario PublicFirewall without -SkipGuestConfiguration to reopen restricted deployment access and finish the build."
    } else {
        Write-Host "Lab deployment completed in $ResourceGroupName. Follow labs\02-configure-migrate-appliance next."
    }
} catch {
    $deploymentError = $_
} finally {
    $storageToLock = Resolve-LabStorageAccountName -ResourceGroupName $ResourceGroupName -Optional
    if ($storageToLock) {
        & az storage account update `
            --resource-group $ResourceGroupName `
            --name $storageToLock `
            --public-network-access Disabled `
            --default-action Deny `
            --output none `
            --only-show-errors
        if ($LASTEXITCODE -ne 0) {
            $cleanupFailures.Add("Failed to disable public access on Storage account $storageToLock.")
        }
    }

    $keyVaultToLock = Resolve-LabKeyVaultName -ResourceGroupName $ResourceGroupName -Optional
    if ($keyVaultToLock) {
        & az keyvault update `
            --resource-group $ResourceGroupName `
            --name $keyVaultToLock `
            --public-network-access Disabled `
            --default-action Deny `
            --output none `
            --only-show-errors
        if ($LASTEXITCODE -ne 0) {
            $cleanupFailures.Add("Failed to disable public access on Key Vault $keyVaultToLock.")
        }
    }

    if ($temporaryPolicyExemptionActivated) {
        $resourceGroupId = & az group show `
            --name $ResourceGroupName `
            --query id `
            --output tsv `
            --only-show-errors 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $resourceGroupId) {
            $cleanupFailures.Add('Failed to resolve the resource group while restoring the SecurityControl tag.')
        } else {
            if ($previousSecurityControlTag) {
                & az tag update `
                    --resource-id $resourceGroupId `
                    --operation Merge `
                    --tags "SecurityControl=$previousSecurityControlTag" `
                    --output none `
                    --only-show-errors
            } else {
                & az tag update `
                    --resource-id $resourceGroupId `
                    --operation Delete `
                    --tags SecurityControl=Ignore `
                    --output none `
                    --only-show-errors
            }

            if ($LASTEXITCODE -ne 0) {
                $cleanupFailures.Add('Failed to restore the resource-group SecurityControl tag.')
            }
        }
    }

    $plainAdminPassword = $null
    $servicePassword = $null
    $discoveryPassword = $null
    $sqlDiscoveryPassword = $null
    Remove-Item $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue

    if ($cleanupFailures.Count -and -not $deploymentError) {
        throw ($cleanupFailures -join [Environment]::NewLine)
    }
}

if ($deploymentError) {
    if ($cleanupFailures.Count) {
        throw "$($deploymentError.Exception.Message)$([Environment]::NewLine)Cleanup failures:$([Environment]::NewLine)$($cleanupFailures -join [Environment]::NewLine)"
    }
    throw $deploymentError
}
