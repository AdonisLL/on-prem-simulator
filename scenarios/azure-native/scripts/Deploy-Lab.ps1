[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Bicep', 'Terraform')][string]$Iac = 'Bicep',
    [string]$ResourceGroupName = 'rg-opmlab-source',
    [string]$Location = 'eastus2',
    [string]$NamePrefix = 'opmlab',
    [string]$SqlImageUrn = 'MicrosoftSQLServer:sql2016sp3-ws2019:sqldev:latest',
    [securestring]$AdminPassword,
    [switch]$SkipGuestConfiguration,
    [switch]$AutoApprove,
    [switch]$UseTemporaryPolicyExemption
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$scenarioRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path (Split-Path $scenarioRoot -Parent) -Parent
Set-Location $repoRoot
Import-Module "$PSScriptRoot\Lab.Common.psm1" -Force

Assert-LabCommand az 'Install Azure CLI and run az login.'
if ($Iac -eq 'Terraform') {
    Assert-LabCommand terraform 'Install Terraform 1.7 or later.'
}

$account = & az account show --query id --output tsv --only-show-errors
if ($LASTEXITCODE -ne 0 -or -not $account) {
    throw 'Azure CLI is not authenticated. Run az login and select a subscription.'
}
$deploymentId = & az group show --name $ResourceGroupName --query tags.deploymentId --output tsv --only-show-errors 2>$null
if (-not $deploymentId) {
    $deploymentId = [Guid]::NewGuid().ToString('N').Substring(0, 10)
}
$previousSecurityControlTag = $null
$temporaryPolicyExemptionActivated = $false
if ($UseTemporaryPolicyExemption) {
    $previousSecurityControlTag = & az group show --name $ResourceGroupName `
        --query tags.SecurityControl --output tsv --only-show-errors 2>$null
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
$stagingRoot = Join-Path ([IO.Path]::GetTempPath()) "onprem-lab-$([Guid]::NewGuid())"
$deploymentError = $null
try {
    New-Item $artifactRoot -ItemType Directory -Force | Out-Null
    New-Item $stagingRoot -ItemType Directory -Force | Out-Null

    $msbuild = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if (-not $msbuild) {
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
        if (Test-Path $vswhere) {
            $installationPath = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
            if ($installationPath) {
                $msbuildPath = Join-Path $installationPath 'MSBuild\Current\Bin\MSBuild.exe'
                if (Test-Path $msbuildPath) {
                    $msbuild = Get-Item $msbuildPath
                }
            }
        }
    }
    if ($msbuild) {
        & $msbuild.FullName 'src\LegacyLab.sln' `
            /t:Restore `
            /p:RestorePackagesConfig=true `
            /nologo
        if ($LASTEXITCODE -ne 0) { throw 'NuGet restore failed.' }
        & $msbuild.FullName 'src\LegacyWeb\LegacyWeb.csproj' `
            /t:Build `
            /p:Configuration=Release `
            /p:DeployOnBuild=true `
            /p:WebPublishMethod=Package `
            /p:AutoParameterizationWebConfigConnectionStrings=false `
            /nologo
        if ($LASTEXITCODE -ne 0) { throw 'LegacyWeb build/publish failed.' }
    } else {
        throw 'Visual Studio 2022 Build Tools with the Web development build tools workload and .NET Framework 4.8 targeting pack are required. See labs\00-prerequisites\README.md.'
    }

    $webArchive = Join-Path $artifactRoot 'LegacyWeb.zip'
    $packageRoot = Join-Path $repoRoot 'src\LegacyWeb\obj\Release\Package\PackageTmp'
    if (-not (Test-Path "$packageRoot\bin\LegacyWeb.dll") -or -not (Test-Path "$packageRoot\web.config")) {
        throw 'The IIS package output is incomplete.'
    }
    Compress-Archive -Path "$packageRoot\*" -DestinationPath $webArchive -Force
    foreach ($path in 'configuration', 'database', 'artifacts') {
        Copy-Item $path -Destination $stagingRoot -Recurse -Force
    }
    $labArchive = Join-Path $artifactRoot 'lab.zip'
    Compress-Archive -Path "$stagingRoot\*" -DestinationPath $labArchive -Force

    if (-not $PSCmdlet.ShouldProcess($ResourceGroupName, "Deploy the $Iac source lab")) {
        return
    }

    if ($Iac -eq 'Bicep') {
        $resourceGroupTags = @(
            'workload=on-prem-modernization-lab',
            'environment=lab',
            "deploymentId=$deploymentId"
        )
        if ($UseTemporaryPolicyExemption) {
            $resourceGroupTags += 'SecurityControl=Ignore'
        }
        & az group create --name $ResourceGroupName --location $Location `
            --tags $resourceGroupTags --output none
        if ($LASTEXITCODE -ne 0) { throw 'Resource group creation failed.' }
        $temporaryPolicyExemptionActivated = [bool]$UseTemporaryPolicyExemption
        $parameterFile = Join-Path $stagingRoot 'deployment-parameters.json'
        try {
            @{
                '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
                contentVersion = '1.0.0.0'
                parameters     = @{
                    namePrefix   = @{ value = $NamePrefix }
                    location     = @{ value = $Location }
                    deploymentId = @{ value = $deploymentId }
                    adminUsername = @{ value = 'labadmin' }
                    adminPassword = @{ value = $plainAdminPassword }
                    sqlImage      = @{ value = $sqlImage }
                    enableTemporaryDeploymentAccess = @{ value = [bool]$UseTemporaryPolicyExemption }
                }
            } | ConvertTo-Json -Depth 6 | Set-Content -Path $parameterFile -Encoding UTF8
            & az deployment group create `
                --resource-group $ResourceGroupName `
                --template-file (Join-Path $scenarioRoot 'infra\bicep\main.bicep') `
                --parameters "@$parameterFile" `
                --only-show-errors `
                --output none
            if ($LASTEXITCODE -ne 0) { throw 'Bicep deployment failed.' }
        } finally {
            Remove-Item $parameterFile -Force -ErrorAction SilentlyContinue
        }
    } else {
        $env:TF_VAR_admin_password = $plainAdminPassword
        $env:TF_VAR_sql_image = $sqlImage | ConvertTo-Json -Compress
        $env:ARM_SUBSCRIPTION_ID = $account
        $temporaryAccessValue = ([bool]$UseTemporaryPolicyExemption).ToString().ToLowerInvariant()
        try {
            $terraformRoot = Join-Path $scenarioRoot 'infra\terraform'
            & terraform "-chdir=$terraformRoot" init -input=false
            if ($LASTEXITCODE -ne 0) { throw 'Terraform initialization failed.' }
            $temporaryPolicyExemptionActivated = [bool]$UseTemporaryPolicyExemption
            & terraform "-chdir=$terraformRoot" apply `
                "-var=resource_group_name=$ResourceGroupName" `
                "-var=location=$Location" `
                "-var=name_prefix=$NamePrefix" `
                "-var=deployment_id=$deploymentId" `
                "-var=enable_temporary_deployment_access=$temporaryAccessValue" `
                -input=false `
                $(if ($AutoApprove) { '-auto-approve' })
            if ($LASTEXITCODE -ne 0) { throw 'Terraform deployment failed.' }
        } finally {
            Remove-Item Env:\TF_VAR_admin_password -ErrorAction SilentlyContinue
            Remove-Item Env:\TF_VAR_sql_image -ErrorAction SilentlyContinue
            Remove-Item Env:\ARM_SUBSCRIPTION_ID -ErrorAction SilentlyContinue
        }
    }

    $storageAccount = & az storage account list --resource-group $ResourceGroupName --query "[?tags.workload=='on-prem-modernization-lab'].name | [0]" --output tsv
    $keyVault = & az keyvault list --resource-group $ResourceGroupName --query "[0].name" --output tsv
    if (-not $storageAccount -or -not $keyVault) {
        throw 'Deployment completed but staging storage or Key Vault could not be resolved.'
    }

    $accountContext = & az account show --output json | ConvertFrom-Json
    if ($accountContext.user.type -eq 'user') {
        $operatorPrincipalId = & az ad signed-in-user show --query id --output tsv --only-show-errors
        $operatorPrincipalType = 'User'
    } else {
        $operatorPrincipalId = & az ad sp show --id $accountContext.user.name --query id --output tsv --only-show-errors
        $operatorPrincipalType = 'ServicePrincipal'
    }
    if (-not $operatorPrincipalId) {
        throw 'Could not resolve the signed-in Azure principal for data-plane role assignment.'
    }
    $storageId = & az storage account show --resource-group $ResourceGroupName --name $storageAccount --query id --output tsv
    $vaultId = & az keyvault show --resource-group $ResourceGroupName --name $keyVault --query id --output tsv
    $vaultPublicNetworkAccess = & az keyvault show --resource-group $ResourceGroupName --name $keyVault --query properties.publicNetworkAccess --output tsv --only-show-errors
    if ($LASTEXITCODE -ne 0 -or -not $vaultPublicNetworkAccess) {
        throw "Could not determine public network access for Key Vault $keyVault. No secrets were written."
    }

    $publicNetworkAccess = & az storage account show `
        --resource-group $ResourceGroupName `
        --name $storageAccount `
        --query publicNetworkAccess `
        --output tsv `
        --only-show-errors

    if ($vaultPublicNetworkAccess -ne 'Enabled') {
        Write-Warning "Key Vault public network access is $vaultPublicNetworkAccess. This workstation cannot seed secrets through the private endpoint unless it has private VNet connectivity and DNS resolution."
        Write-Host "Infrastructure is ready. Resume private Key Vault setup with: .\scenarios\azure-native\scripts\Repair-KeyVaultAccess.ps1 -ResourceGroupName $ResourceGroupName"
        Write-Host 'Run configuration\powershell\Set-LabKeyVaultSecrets.ps1 from dc01, then finalize access as described in labs\01-deploy-source\README.md.'
        return
    }

    & az role assignment create --assignee-object-id $operatorPrincipalId --assignee-principal-type $operatorPrincipalType --role 'Key Vault Secrets Officer' --scope $vaultId --output none
    if ($LASTEXITCODE -ne 0) {
        throw 'Failed to grant temporary Key Vault secret-seeding access to the deployment principal.'
    }

    if ($publicNetworkAccess -eq 'Enabled') {
        & az role assignment create --assignee-object-id $operatorPrincipalId --assignee-principal-type $operatorPrincipalType --role 'Storage Blob Data Contributor' --scope $storageId --output none
        $artifactUploaded = $false
        $uploadError = $null
        for ($attempt = 1; $attempt -le 20; $attempt++) {
            $uploadError = & az storage blob upload `
                --account-name $storageAccount `
                --container-name artifacts `
                --name lab.zip `
                --file $labArchive `
                --auth-mode login `
                --overwrite true `
                --only-show-errors `
                --output none
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
            $networkRuleSet = & az storage account show `
                --resource-group $ResourceGroupName `
                --name $storageAccount `
                --query '{publicNetworkAccess:publicNetworkAccess, defaultAction:networkRuleSet.defaultAction, bypass:networkRuleSet.bypass, ipRules:networkRuleSet.ipRules[].value, virtualNetworkRules:networkRuleSet.virtualNetworkRules[].virtualNetworkResourceId}' `
                --output json `
                --only-show-errors
            throw "Artifact upload failed after waiting for Storage Blob Data Contributor propagation. Azure CLI error: $uploadError Storage network configuration: $networkRuleSet"
        }
    }

    Set-LabKeyVaultSecretFromMemory -VaultName $keyVault -Name 'admin-password' -Value $plainAdminPassword
    Set-LabKeyVaultSecretFromMemory -VaultName $keyVault -Name 'web-service-password' -Value $servicePassword
    Set-LabKeyVaultSecretFromMemory -VaultName $keyVault -Name 'migrate-discovery-password' -Value $discoveryPassword
    Set-LabKeyVaultSecretFromMemory -VaultName $keyVault -Name 'sql-discovery-password' -Value $sqlDiscoveryPassword

    foreach ($vmName in 'dc01', 'web01', 'web02', 'sql01', 'migrate01') {
        $principalId = & az vm identity show --resource-group $ResourceGroupName --name $vmName --query principalId --output tsv
        & az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal --role 'Storage Blob Data Reader' --scope $storageId --output none
        & az role assignment create --assignee-object-id $principalId --assignee-principal-type ServicePrincipal --role 'Key Vault Secrets User' --scope $vaultId --output none
    }
    Start-Sleep -Seconds 30

    if ($publicNetworkAccess -ne 'Enabled' -and -not $SkipGuestConfiguration) {
        Write-Warning "Storage public network access is $publicNetworkAccess. The script did not use account keys, a SAS token, or attempt to override policy."
        Write-Host "Infrastructure and secrets are ready. Copy $labArchive to C:\ProgramData\OnPremLab\lab.zip on dc01, web01, web02, sql01, and migrate01 using an approved management path."
        Write-Host "Then resume with the Azure-native recovery command documented in labs\01-deploy-source\README.md."
        Write-Host "After initialization, run: .\scenarios\azure-native\scripts\Export-DiscoveryInventory.ps1 -ResourceGroupName $ResourceGroupName"
        return
    }

    if (-not $SkipGuestConfiguration) {
        & "$PSScriptRoot\Initialize-Lab.ps1" -ResourceGroupName $ResourceGroupName -StorageAccountName $storageAccount -KeyVaultName $keyVault
    }

    & "$PSScriptRoot\Export-DiscoveryInventory.ps1" -ResourceGroupName $ResourceGroupName
    Write-Host "Lab deployment completed in $ResourceGroupName. Follow labs\02-configure-migrate-appliance next."
} catch {
    $deploymentError = $_
} finally {
    $cleanupFailures = [Collections.Generic.List[string]]::new()
    if ($UseTemporaryPolicyExemption -and $temporaryPolicyExemptionActivated) {
        $keyVaultToLock = & az keyvault list --resource-group $ResourceGroupName `
            --query '[0].name' --output tsv --only-show-errors 2>$null
        if ($keyVaultToLock) {
            & az keyvault update --resource-group $ResourceGroupName `
                --name $keyVaultToLock --public-network-access Disabled `
                --default-action Deny `
                --output none --only-show-errors
            if ($LASTEXITCODE -ne 0) {
                $cleanupFailures.Add("Failed to disable public access on Key Vault $keyVaultToLock.")
            }
        }

        $storageToLock = & az storage account list --resource-group $ResourceGroupName `
            --query "[?tags.workload=='on-prem-modernization-lab'].name | [0]" `
            --output tsv --only-show-errors 2>$null
        if ($storageToLock) {
            & az storage account update --resource-group $ResourceGroupName `
                --name $storageToLock --public-network-access Disabled `
                --default-action Deny --output none --only-show-errors
            if ($LASTEXITCODE -ne 0) {
                $cleanupFailures.Add("Failed to disable public access on Storage account $storageToLock.")
            }
        }

        $resourceGroupId = & az group show --name $ResourceGroupName `
            --query id --output tsv --only-show-errors 2>$null
        if ($resourceGroupId) {
            if ($previousSecurityControlTag) {
                & az tag update --resource-id $resourceGroupId --operation Merge `
                    --tags "SecurityControl=$previousSecurityControlTag" `
                    --output none --only-show-errors
            } else {
                & az tag update --resource-id $resourceGroupId --operation Delete `
                    --tags SecurityControl=Ignore --output none --only-show-errors
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
    Remove-Item $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
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
