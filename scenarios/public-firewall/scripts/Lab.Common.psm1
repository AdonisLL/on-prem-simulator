Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-LabCommand {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$InstallHint
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is required. $InstallHint"
    }
}

function Get-LabScenarioVmNames {
    @('dc01', 'web01', 'web02', 'sql01', 'migrate01')
}

function New-LabPassword {
    $characters = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%*-_'
    $bytes = [byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    -join ($bytes | ForEach-Object { $characters[$_ % $characters.Length] })
}

function New-LabScratchDirectory {
    param(
        [Parameter(Mandatory)][string]$ArtifactRoot,
        [string]$Prefix = 'public-firewall'
    )

    New-Item -Path $ArtifactRoot -ItemType Directory -Force | Out-Null
    $scratchPath = Join-Path $ArtifactRoot "$Prefix-$([Guid]::NewGuid().ToString('N'))"
    New-Item -Path $scratchPath -ItemType Directory -Force | Out-Null
    return $scratchPath
}

function Resolve-LabMsBuild {
    $msbuild = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if ($msbuild) {
        return $msbuild.Source
    }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vswhere) {
        $installationPath = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
        if ($installationPath) {
            $candidate = Join-Path $installationPath 'MSBuild\Current\Bin\MSBuild.exe'
            if (Test-Path $candidate) {
                return $candidate
            }
        }
    }

    throw 'Visual Studio 2022 Build Tools with the Web development build tools workload and .NET Framework 4.8 targeting pack are required. See labs\00-prerequisites\README.md.'
}

function Build-LabArtifacts {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$ScratchRoot
    )

    $artifactRoot = Join-Path $RepoRoot 'artifacts'
    New-Item -Path $artifactRoot -ItemType Directory -Force | Out-Null

    $msbuildPath = Resolve-LabMsBuild
    & $msbuildPath 'src\LegacyLab.sln' `
        /t:Restore `
        /p:RestorePackagesConfig=true `
        /nologo
    if ($LASTEXITCODE -ne 0) {
        throw 'NuGet restore failed.'
    }

    & $msbuildPath 'src\LegacyWeb\LegacyWeb.csproj' `
        /t:Build `
        /p:Configuration=Release `
        /p:DeployOnBuild=true `
        /p:WebPublishMethod=Package `
        /p:AutoParameterizationWebConfigConnectionStrings=false `
        /nologo
    if ($LASTEXITCODE -ne 0) {
        throw 'LegacyWeb build/publish failed.'
    }

    $packageRoot = Join-Path $RepoRoot 'src\LegacyWeb\obj\Release\Package\PackageTmp'
    if (
        -not (Test-Path (Join-Path $packageRoot 'bin\LegacyWeb.dll')) -or
        -not (Test-Path (Join-Path $packageRoot 'web.config'))
    ) {
        throw 'The IIS package output is incomplete.'
    }

    $webArchive = Join-Path $artifactRoot 'LegacyWeb.zip'
    if (Test-Path $webArchive) {
        Remove-Item $webArchive -Force
    }
    Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $webArchive -Force

    $labContentRoot = Join-Path $ScratchRoot 'lab-content'
    $stagedArtifactsRoot = Join-Path $labContentRoot 'artifacts'
    New-Item -Path $stagedArtifactsRoot -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path $RepoRoot 'configuration') -Destination $labContentRoot -Recurse -Force
    Copy-Item -Path (Join-Path $RepoRoot 'database') -Destination $labContentRoot -Recurse -Force
    Copy-Item -Path $webArchive -Destination $stagedArtifactsRoot -Force

    $labArchive = Join-Path $artifactRoot 'lab.zip'
    if (Test-Path $labArchive) {
        Remove-Item $labArchive -Force
    }
    Compress-Archive -Path (Join-Path $labContentRoot '*') -DestinationPath $labArchive -Force

    return [pscustomobject]@{
        ArtifactRoot = $artifactRoot
        WebArchive   = $webArchive
        LabArchive   = $labArchive
    }
}

function Convert-LabUInt32ToIpv4Address {
    param([Parameter(Mandatory)][uint32]$Value)

    $bytes = @(
        ($Value -shr 24) -band 0xFF
        ($Value -shr 16) -band 0xFF
        ($Value -shr 8) -band 0xFF
        $Value -band 0xFF
    )
    return ($bytes | ForEach-Object { [string]$_ }) -join '.'
}

function Assert-LabIpv4Address {
    param([Parameter(Mandatory)][string]$Address)

    $trimmed = $Address.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw 'An IPv4 address value is required.'
    }

    $parsedAddress = $null
    if (
        -not [Net.IPAddress]::TryParse($trimmed, [ref]$parsedAddress) -or
        $parsedAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork
    ) {
        throw "IPv4 address '$Address' is invalid."
    }

    return ($parsedAddress.GetAddressBytes() | ForEach-Object { [string]$_ }) -join '.'
}

function Assert-LabIpv4Cidr {
    param(
        [Parameter(Mandatory)][string]$AddressPrefix,
        [switch]$AllowNon32
    )

    if ($AddressPrefix -notmatch '^(?<address>(?:\d{1,3}\.){3}\d{1,3})/(?<length>\d{1,2})$') {
        throw "DeployerAddressPrefix must be an explicit IPv4 CIDR such as 203.0.113.10/32."
    }

    $normalizedAddress = Assert-LabIpv4Address -Address $Matches.address
    $prefixLength = [int]$Matches.length
    if ($prefixLength -lt 0 -or $prefixLength -gt 32) {
        throw "CIDR prefix length '/$prefixLength' is invalid."
    }

    if (-not $AllowNon32 -and $prefixLength -ne 32) {
        throw 'DeployerAddressPrefix must be a single-host /32 unless -AllowNon32DeployerPrefix is specified explicitly.'
    }

    $octets = $normalizedAddress.Split('.') | ForEach-Object { [uint32]$_ }
    $addressValue =
        (($octets[0] -shl 24) -bor
         ($octets[1] -shl 16) -bor
         ($octets[2] -shl 8) -bor
         $octets[3])

    $mask = if ($prefixLength -eq 0) {
        [uint32]0
    } else {
        [uint32]::MaxValue -shl (32 - $prefixLength)
    }

    $networkValue = $addressValue -band $mask
    if ($prefixLength -lt 32 -and $networkValue -ne $addressValue) {
        $canonicalPrefix = Convert-LabUInt32ToIpv4Address -Value $networkValue
        throw "DeployerAddressPrefix must use the canonical network address $canonicalPrefix/$prefixLength."
    }

    return "$normalizedAddress/$prefixLength"
}

function Normalize-LabIpRuleValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $trimmed = $Value.Trim()
    if ($trimmed -eq '*') {
        return $trimmed
    }

    if ($trimmed.Contains('/')) {
        return Assert-LabIpv4Cidr -AddressPrefix $trimmed -AllowNon32
    }

    return "$(Assert-LabIpv4Address -Address $trimmed)/32"
}

function Resolve-LabStorageAccountName {
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [switch]$Optional
    )

    $name = & az storage account list `
        --resource-group $ResourceGroupName `
        --query "[?tags.workload=='on-prem-modernization-lab'].name | [0]" `
        --output tsv `
        --only-show-errors 2>$null

    if ($LASTEXITCODE -ne 0 -or -not $name) {
        if ($Optional) {
            return $null
        }
        throw "Could not resolve the staging Storage account in $ResourceGroupName."
    }

    return $name
}

function Resolve-LabKeyVaultName {
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [switch]$Optional
    )

    $name = & az keyvault list `
        --resource-group $ResourceGroupName `
        --query '[0].name' `
        --output tsv `
        --only-show-errors 2>$null

    if ($LASTEXITCODE -ne 0 -or -not $name) {
        if ($Optional) {
            return $null
        }
        throw "Could not resolve the Key Vault in $ResourceGroupName."
    }

    return $name
}

function Get-LabCurrentPrincipal {
    $accountContext = & az account show --output json --only-show-errors | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $accountContext) {
        throw 'Could not resolve the signed-in Azure principal.'
    }

    if ($accountContext.user.type -eq 'user') {
        $objectId = & az ad signed-in-user show --query id --output tsv --only-show-errors
        $principalType = 'User'
    } else {
        $objectId = & az ad sp show --id $accountContext.user.name --query id --output tsv --only-show-errors
        $principalType = 'ServicePrincipal'
    }

    if (-not $objectId) {
        throw 'Could not resolve the signed-in Azure principal for RBAC operations.'
    }

    return [pscustomobject]@{
        ObjectId      = $objectId
        PrincipalType = $principalType
    }
}

function Ensure-LabRoleAssignment {
    param(
        [Parameter(Mandatory)][string]$AssigneeObjectId,
        [Parameter(Mandatory)][string]$AssigneePrincipalType,
        [Parameter(Mandatory)][string]$RoleDefinitionName,
        [Parameter(Mandatory)][string]$Scope
    )

    $existing = & az role assignment list `
        --assignee-object-id $AssigneeObjectId `
        --scope $Scope `
        --query "[?roleDefinitionName=='$RoleDefinitionName'] | [0].id" `
        --output tsv `
        --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to query existing role assignments for $RoleDefinitionName."
    }

    if ($existing) {
        return
    }

    $createResult = & az role assignment create `
        --assignee-object-id $AssigneeObjectId `
        --assignee-principal-type $AssigneePrincipalType `
        --role $RoleDefinitionName `
        --scope $Scope `
        --output none `
        --only-show-errors 2>&1
    if ($LASTEXITCODE -ne 0 -and $createResult -notmatch 'RoleAssignmentExists') {
        throw "Failed to create role assignment $RoleDefinitionName. Azure CLI error: $createResult"
    }
}

function Set-LabKeyVaultSecretFromMemory {
    param(
        [Parameter(Mandatory)][string]$VaultName,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$ScratchRoot
    )

    $secretRoot = Join-Path $ScratchRoot 'secrets'
    New-Item -Path $secretRoot -ItemType Directory -Force | Out-Null
    $secretFile = Join-Path $secretRoot "$Name.secret"

    try {
        $utf8NoBom = [Text.UTF8Encoding]::new($false)
        [IO.File]::WriteAllText($secretFile, $Value, $utf8NoBom)

        $stored = $false
        $lastError = $null
        for ($attempt = 1; $attempt -le 20; $attempt++) {
            $lastError = & az keyvault secret set `
                --vault-name $VaultName `
                --name $Name `
                --file $secretFile `
                --only-show-errors `
                --output none 2>&1
            if ($LASTEXITCODE -eq 0) {
                $stored = $true
                break
            }

            if ($attempt -lt 20) {
                Write-Host "Key Vault write access is not available yet; retrying in 15 seconds ($attempt/20)."
                Start-Sleep -Seconds 15
            }
        }

        if (-not $stored) {
            throw "Failed to store Key Vault secret $Name after waiting for RBAC propagation. Azure CLI error: $lastError"
        }
    } finally {
        if (Test-Path $secretFile) {
            Remove-Item $secretFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Wait-LabVmReady {
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VmName
    )

    $deadline = [DateTime]::UtcNow.AddMinutes(15)
    do {
        $state = & az vm get-instance-view `
            --resource-group $ResourceGroupName `
            --name $VmName `
            --query "instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]" `
            --output tsv `
            --only-show-errors

        if ($state -eq 'PowerState/running') {
            Start-Sleep -Seconds 20
            return
        }

        Start-Sleep -Seconds 15
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "$VmName did not return to a running state."
}

function Invoke-LabBootstrap {
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][string]$Role,
        [Parameter(Mandatory)][string]$StorageAccountName,
        [Parameter(Mandatory)][string]$KeyVaultName,
        [ValidateSet('Storage', 'Local')][string]$ArtifactSource = 'Storage',
        [string[]]$ComputerName,
        [string]$DomainName = 'corp.contoso.local',
        [string]$NetbiosName = 'CONTOSO',
        [string]$DomainControllerIp = '10.50.2.4'
    )

    $parameters = @(
        "Role=$Role",
        "StorageAccountName=$StorageAccountName",
        "KeyVaultName=$KeyVaultName",
        "ArtifactSource=$ArtifactSource",
        "DomainName=$DomainName",
        "NetbiosName=$NetbiosName",
        "DomainControllerIp=$DomainControllerIp"
    )
    if ($ComputerName) {
        $parameters += "ComputerNamesCsv=$($ComputerName -join ',')"
    }

    & az vm run-command invoke `
        --resource-group $ResourceGroupName `
        --name $VmName `
        --command-id RunPowerShellScript `
        --scripts "@configuration\powershell\Invoke-AzureBootstrap.ps1" `
        --parameters $parameters `
        --only-show-errors `
        --output none
    if ($LASTEXITCODE -ne 0) {
        throw "Guest configuration role $Role failed on $VmName."
    }
}

function Get-LabVmPrivateIpMap {
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string[]]$VmNames
    )

    $privateIpMap = @{}
    foreach ($vmName in $VmNames) {
        $ip = & az vm list-ip-addresses `
            --resource-group $ResourceGroupName `
            --name $vmName `
            --query "[0].virtualMachine.network.privateIpAddresses[0]" `
            --output tsv `
            --only-show-errors
        if ($LASTEXITCODE -ne 0 -or -not $ip) {
            throw "Could not resolve the private IP for $vmName."
        }
        $privateIpMap[$vmName] = Assert-LabIpv4Address -Address $ip
    }

    return $privateIpMap
}

function ConvertTo-LabNatRuleRecord {
    param(
        [Parameter(Mandatory)]$Rule,
        [Parameter(Mandatory)][string]$CollectionName
    )

    $ruleProperties = if ($Rule.PSObject.Properties.Name -contains 'properties' -and $null -ne $Rule.properties) {
        $Rule.properties
    } else {
        $Rule
    }

    $ruleName = if ($Rule.PSObject.Properties.Name -contains 'name' -and $Rule.name) {
        [string]$Rule.name
    } elseif ($ruleProperties.PSObject.Properties.Name -contains 'name' -and $ruleProperties.name) {
        [string]$ruleProperties.name
    } else {
        $null
    }

    if (
        -not ($ruleProperties.PSObject.Properties.Name -contains 'translatedAddress') -or
        -not ($ruleProperties.PSObject.Properties.Name -contains 'translatedPort')
    ) {
        return $null
    }

    return [pscustomobject]@{
        Name                 = $ruleName
        CollectionName       = $CollectionName
        SourceAddresses      = @($ruleProperties.sourceAddresses | ForEach-Object { Normalize-LabIpRuleValue $_ } | Where-Object { $_ })
        DestinationAddresses = @($ruleProperties.destinationAddresses | ForEach-Object { Assert-LabIpv4Address -Address $_ })
        DestinationPorts     = @($ruleProperties.destinationPorts | ForEach-Object { [string]$_ })
        TranslatedAddress    = if ($ruleProperties.translatedAddress) { Assert-LabIpv4Address -Address $ruleProperties.translatedAddress } else { $null }
        TranslatedPort       = if ($ruleProperties.translatedPort) { [string]$ruleProperties.translatedPort } else { $null }
    }
}

function Get-LabNatRulesFromCollections {
    param([Parameter(Mandatory)]$Collections)

    $records = @()
    foreach ($collection in @($Collections)) {
        if (-not $collection) {
            continue
        }

        $collectionProperties = if ($collection.PSObject.Properties.Name -contains 'properties' -and $null -ne $collection.properties) {
            $collection.properties
        } else {
            $collection
        }

        $collectionName = if ($collection.PSObject.Properties.Name -contains 'name' -and $collection.name) {
            [string]$collection.name
        } elseif ($collectionProperties.PSObject.Properties.Name -contains 'name' -and $collectionProperties.name) {
            [string]$collectionProperties.name
        } else {
            'unnamed'
        }

        foreach ($rule in @($collectionProperties.rules)) {
            $record = ConvertTo-LabNatRuleRecord -Rule $rule -CollectionName $collectionName
            if ($record) {
                $records += $record
            }
        }
    }

    return $records
}

function Get-LabFirewallPolicyNatRules {
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$FirewallPolicyId
    )

    $groupResources = & az resource list `
        --resource-group $ResourceGroupName `
        --query "[?type=='Microsoft.Network/firewallPolicies/ruleCollectionGroups']" `
        --output json `
        --only-show-errors | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $groupResources) {
        return @()
    }

    $ruleCollections = @()
    foreach ($groupResource in @($groupResources)) {
        $group = & az resource show --ids $groupResource.id --output json --only-show-errors | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or -not $group) {
            continue
        }

        $policyId = if (
            $group.properties.PSObject.Properties.Name -contains 'firewallPolicy' -and
            $group.properties.firewallPolicy
        ) {
            [string]$group.properties.firewallPolicy.id
        } else {
            $null
        }

        if ($policyId -and $policyId -eq $FirewallPolicyId) {
            $ruleCollections += @($group.properties.ruleCollections)
        }
    }

    return Get-LabNatRulesFromCollections -Collections $ruleCollections
}

function Get-LabFirewallEndpointMap {
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][hashtable]$VmPrivateIpMap
    )

    $firewallResources = & az resource list `
        --resource-group $ResourceGroupName `
        --query "[?type=='Microsoft.Network/azureFirewalls']" `
        --output json `
        --only-show-errors | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $firewallResources) {
        throw "No Azure Firewall resource was found in $ResourceGroupName."
    }

    $firewallList = @($firewallResources)
    if ($firewallList.Count -ne 1) {
        throw "Expected exactly one Azure Firewall in $ResourceGroupName but found $($firewallList.Count)."
    }

    $firewall = & az resource show --ids $firewallList[0].id --output json --only-show-errors | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $firewall) {
        throw 'Could not resolve Azure Firewall details.'
    }

    $publicIpAddresses = @()
    foreach ($ipConfiguration in @($firewall.properties.ipConfigurations)) {
        $publicIpId = if (
            $ipConfiguration.properties.PSObject.Properties.Name -contains 'publicIPAddress' -and
            $ipConfiguration.properties.publicIPAddress
        ) {
            $ipConfiguration.properties.publicIPAddress.id
        } else {
            $null
        }

        if (-not $publicIpId) {
            continue
        }

        $publicIp = & az resource show --ids $publicIpId --query properties.ipAddress --output tsv --only-show-errors
        if ($LASTEXITCODE -ne 0 -or -not $publicIp) {
            throw "Could not resolve Azure Firewall public IP $publicIpId."
        }
        $publicIpAddresses += Assert-LabIpv4Address -Address $publicIp
    }

    $natRules = @()
    $natRules += Get-LabNatRulesFromCollections -Collections $firewall.properties.natRuleCollections
    if (
        $firewall.properties.PSObject.Properties.Name -contains 'firewallPolicy' -and
        $firewall.properties.firewallPolicy -and
        $firewall.properties.firewallPolicy.id
    ) {
        $natRules += Get-LabFirewallPolicyNatRules `
            -ResourceGroupName $ResourceGroupName `
            -FirewallPolicyId $firewall.properties.firewallPolicy.id
    }

    $expectedMappings = @{
        web01 = @{ PrivatePort = '80'; PublicPort = '80' }
        web02 = @{ PrivatePort = '80'; PublicPort = '80' }
        sql01 = @{ PrivatePort = '1433'; PublicPort = '1633' }
    }

    $endpointMap = @{}
    foreach ($role in $expectedMappings.Keys) {
        if (-not $VmPrivateIpMap.ContainsKey($role)) {
            throw "The private IP for $role was not supplied."
        }

        $expected = $expectedMappings[$role]
        $matches = @(
            $natRules | Where-Object {
                $_.TranslatedAddress -eq $VmPrivateIpMap[$role] -and
                $_.TranslatedPort -eq $expected.PrivatePort -and
                ($_.DestinationPorts -contains $expected.PublicPort)
            }
        )

        if ($matches.Count -gt 1) {
            throw "Multiple Azure Firewall NAT rules matched $role."
        }

        if ($matches.Count -eq 0) {
            continue
        }

        $destinationAddresses = @($matches[0].DestinationAddresses | Where-Object { $_ })
        if ($destinationAddresses.Count -ne 1) {
            throw "Expected one public destination address for $role."
        }

        $endpointMap[$role] = [pscustomobject]@{
            Role            = $role
            PublicAddress   = $destinationAddresses[0]
            PublicPort      = [int]$expected.PublicPort
            PrivateAddress  = $VmPrivateIpMap[$role]
            PrivatePort     = [int]$expected.PrivatePort
            SourceAddresses = @($matches[0].SourceAddresses | Where-Object { $_ })
            RuleName        = $matches[0].Name
            CollectionName  = $matches[0].CollectionName
        }
    }

    return [pscustomobject]@{
        FirewallName      = $firewall.name
        PublicIpAddresses = @($publicIpAddresses | Sort-Object -Unique)
        EndpointMap       = $endpointMap
    }
}

function Get-LabExpectedDeploymentAccessSources {
    param(
        [Parameter(Mandatory)][string]$DeployerAddressPrefix,
        [Parameter(Mandatory)]$FirewallData
    )

    return @(
        @($DeployerAddressPrefix) + @($FirewallData.PublicIpAddresses) |
        ForEach-Object { Normalize-LabIpRuleValue $_ } |
        Where-Object { $_ -and $_ -ne '*' } |
        Sort-Object -Unique
    )
}

function Assert-LabFirewallEndpointContract {
    param(
        [Parameter(Mandatory)]$FirewallData,
        [Parameter(Mandatory)][string]$DeployerAddressPrefix
    )

    if (@($FirewallData.PublicIpAddresses).Count -ne 3) {
        throw "Expected three Azure Firewall public IPs but found $(@($FirewallData.PublicIpAddresses).Count)."
    }

    foreach ($role in 'web01', 'web02', 'sql01') {
        if (-not $FirewallData.EndpointMap.ContainsKey($role)) {
            throw "Azure Firewall DNAT does not expose the expected $role endpoint."
        }
    }

    if (
        $FirewallData.EndpointMap.web01.PublicPort -ne 80 -or
        $FirewallData.EndpointMap.web01.PrivatePort -ne 80 -or
        $FirewallData.EndpointMap.web02.PublicPort -ne 80 -or
        $FirewallData.EndpointMap.web02.PrivatePort -ne 80
    ) {
        throw 'Both IIS endpoints must expose public TCP 80 to private TCP 80.'
    }

    if (
        $FirewallData.EndpointMap.sql01.PublicPort -ne 1633 -or
        $FirewallData.EndpointMap.sql01.PrivatePort -ne 1433
    ) {
        throw 'The SQL endpoint must expose public TCP 1633 to private TCP 1433.'
    }

    $normalizedDeployerPrefix = Normalize-LabIpRuleValue $DeployerAddressPrefix
    foreach ($role in $FirewallData.EndpointMap.Keys) {
        $sourceAddresses = @($FirewallData.EndpointMap[$role].SourceAddresses | Sort-Object -Unique)
        if (-not ($sourceAddresses -contains $normalizedDeployerPrefix)) {
            throw "$role does not restrict Azure Firewall DNAT to $normalizedDeployerPrefix."
        }

        $extraSources = @($sourceAddresses | Where-Object { $_ -ne $normalizedDeployerPrefix })
        if ($extraSources.Count) {
            throw "$role accepts unexpected source prefixes: $($extraSources -join ', ')."
        }
    }
}

function Get-LabKeyVaultNetworkRules {
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$KeyVaultName
    )

    $details = & az keyvault show `
        --resource-group $ResourceGroupName `
        --name $KeyVaultName `
        --query '{publicNetworkAccess:properties.publicNetworkAccess, defaultAction:properties.networkAcls.defaultAction, ipRules:properties.networkAcls.ipRules[].value}' `
        --output json `
        --only-show-errors | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $details) {
        throw "Could not resolve Key Vault network rules for $KeyVaultName."
    }

    return [pscustomobject]@{
        PublicNetworkAccess = [string]$details.publicNetworkAccess
        DefaultAction       = [string]$details.defaultAction
        IpRules             = @($details.ipRules)
    }
}

function Get-LabStorageNetworkRules {
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$StorageAccountName
    )

    $details = & az storage account show `
        --resource-group $ResourceGroupName `
        --name $StorageAccountName `
        --query '{publicNetworkAccess:publicNetworkAccess, defaultAction:networkRuleSet.defaultAction, ipRules:networkRuleSet.ipRules[].value}' `
        --output json `
        --only-show-errors | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $details) {
        throw "Could not resolve Storage network rules for $StorageAccountName."
    }

    return [pscustomobject]@{
        PublicNetworkAccess = [string]$details.publicNetworkAccess
        DefaultAction       = [string]$details.defaultAction
        IpRules             = @($details.ipRules)
    }
}

function Assert-LabRestrictedDeploymentAccess {
    param(
        [Parameter(Mandatory)][string]$ResourceType,
        [Parameter(Mandatory)]$NetworkRules,
        [Parameter(Mandatory)][string[]]$ExpectedAddressPrefixes
    )

    if ($NetworkRules.PublicNetworkAccess -ne 'Enabled') {
        throw "$ResourceType public network access must remain enabled only during deployment."
    }

    if ($NetworkRules.DefaultAction -ne 'Deny') {
        throw "$ResourceType default action must stay Deny while temporary deployment access is enabled."
    }

    $actualRules = @(
        $NetworkRules.IpRules |
        ForEach-Object { Normalize-LabIpRuleValue $_ } |
        Where-Object { $_ -and $_ -ne '*' } |
        Sort-Object -Unique
    )
    $expectedRules = @(
        $ExpectedAddressPrefixes |
        ForEach-Object { Normalize-LabIpRuleValue $_ } |
        Where-Object { $_ -and $_ -ne '*' } |
        Sort-Object -Unique
    )

    $differences = Compare-Object -ReferenceObject $expectedRules -DifferenceObject $actualRules
    if ($differences) {
        throw "$ResourceType IP rules did not match the expected deployer/firewall addresses. Expected: $($expectedRules -join ', '). Actual: $($actualRules -join ', ')."
    }
}

function Assert-LabPublicAccessLockedDown {
    param(
        [Parameter(Mandatory)][string]$ResourceType,
        [Parameter(Mandatory)]$NetworkRules
    )

    if ($NetworkRules.PublicNetworkAccess -ne 'Disabled') {
        throw "$ResourceType public network access should be Disabled after deployment cleanup."
    }

    if ($NetworkRules.DefaultAction -ne 'Deny') {
        throw "$ResourceType default action should be Deny after deployment cleanup."
    }
}

function Get-LabResourceGroupSecurityControlTag {
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [switch]$Optional
    )

    $value = & az group show `
        --name $ResourceGroupName `
        --query tags.SecurityControl `
        --output tsv `
        --only-show-errors 2>$null

    if ($LASTEXITCODE -ne 0) {
        if ($Optional) {
            return $null
        }
        throw "Could not resolve the SecurityControl tag for $ResourceGroupName."
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    return $value
}

function Format-LabEndpointSummary {
    param([Parameter(Mandatory)]$FirewallData)

    $lines = @('Azure Firewall public endpoints:')
    foreach ($role in 'web01', 'web02') {
        if ($FirewallData.EndpointMap.ContainsKey($role)) {
            $endpoint = $FirewallData.EndpointMap[$role]
            $uri = if ($endpoint.PublicPort -eq 80) {
                "http://$($endpoint.PublicAddress)/"
            } else {
                "http://$($endpoint.PublicAddress):$($endpoint.PublicPort)/"
            }
            $lines += "  $role -> $uri"
        }
    }

    if ($FirewallData.EndpointMap.ContainsKey('sql01')) {
        $sqlEndpoint = $FirewallData.EndpointMap.sql01
        $lines += "  sql01 -> $($sqlEndpoint.PublicAddress):$($sqlEndpoint.PublicPort) (DNAT to $($sqlEndpoint.PrivateAddress):$($sqlEndpoint.PrivatePort))"
    }

    return $lines -join [Environment]::NewLine
}

function Test-LabTcpEndpoint {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutMs = 10000
    )

    $client = [Net.Sockets.TcpClient]::new()
    try {
        $connectTask = $client.ConnectAsync($ComputerName, $Port)
        if (-not $connectTask.Wait($TimeoutMs)) {
            return $false
        }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

Export-ModuleMember -Function *
