[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$DeployerAddressPrefix,
    [switch]$AllowNon32DeployerPrefix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\Lab.Common.psm1" -Force

$DeployerAddressPrefix = Assert-LabIpv4Cidr `
    -AddressPrefix $DeployerAddressPrefix `
    -AllowNon32:$AllowNon32DeployerPrefix

$failures = [Collections.Generic.List[string]]::new()
$expectedVmNames = Get-LabScenarioVmNames
foreach ($vmName in $expectedVmNames) {
    $details = & az vm show `
        --resource-group $ResourceGroupName `
        --name $vmName `
        --show-details `
        --output json `
        --only-show-errors | ConvertFrom-Json
    if (-not $details) {
        $failures.Add("$vmName does not exist.")
        continue
    }

    if ($details.publicIps) {
        $failures.Add("$vmName unexpectedly has a public IP.")
    }
}

$firewallData = $null
try {
    $privateIpMap = Get-LabVmPrivateIpMap `
        -ResourceGroupName $ResourceGroupName `
        -VmNames $expectedVmNames
    $firewallData = Get-LabFirewallEndpointMap `
        -ResourceGroupName $ResourceGroupName `
        -VmPrivateIpMap $privateIpMap
    Assert-LabFirewallEndpointContract `
        -FirewallData $firewallData `
        -DeployerAddressPrefix $DeployerAddressPrefix
} catch {
    $failures.Add($_.Exception.Message)
}

if ($firewallData) {
    foreach ($role in 'web01', 'web02') {
        $endpoint = $firewallData.EndpointMap[$role]
        if (-not $endpoint) {
            $failures.Add("Azure Firewall does not expose the expected $role web endpoint.")
            continue
        }

        $uri = if ($endpoint.PublicPort -eq 80) {
            "http://$($endpoint.PublicAddress)/"
        } else {
            "http://$($endpoint.PublicAddress):$($endpoint.PublicPort)/"
        }

        try {
            $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 60
            if ($response.StatusCode -ne 200) {
                $failures.Add("$role returned HTTP $($response.StatusCode) instead of HTTP 200 from $uri.")
            }
        } catch {
            $failures.Add("$role did not return HTTP 200 from $uri. $($_.Exception.Message)")
        }
    }

    $sqlEndpoint = $firewallData.EndpointMap.sql01
    if (-not $sqlEndpoint) {
        $failures.Add('Azure Firewall does not expose the expected sql01 endpoint.')
    } elseif (-not (Test-LabTcpEndpoint -ComputerName $sqlEndpoint.PublicAddress -Port $sqlEndpoint.PublicPort)) {
        $failures.Add("SQL public endpoint $($sqlEndpoint.PublicAddress):$($sqlEndpoint.PublicPort) was not reachable.")
    }
}

try {
    $storageAccount = Resolve-LabStorageAccountName -ResourceGroupName $ResourceGroupName
    $storageRules = Get-LabStorageNetworkRules `
        -ResourceGroupName $ResourceGroupName `
        -StorageAccountName $storageAccount
    Assert-LabPublicAccessLockedDown `
        -ResourceType 'Storage account' `
        -NetworkRules $storageRules
} catch {
    $failures.Add($_.Exception.Message)
}

try {
    $keyVault = Resolve-LabKeyVaultName -ResourceGroupName $ResourceGroupName
    $keyVaultRules = Get-LabKeyVaultNetworkRules `
        -ResourceGroupName $ResourceGroupName `
        -KeyVaultName $keyVault
    Assert-LabPublicAccessLockedDown `
        -ResourceType 'Key Vault' `
        -NetworkRules $keyVaultRules
} catch {
    $failures.Add($_.Exception.Message)
}

try {
    $securityControlTag = Get-LabResourceGroupSecurityControlTag -ResourceGroupName $ResourceGroupName -Optional
    if ($securityControlTag -eq 'Ignore') {
        $failures.Add('The resource-group SecurityControl tag is still Ignore after cleanup.')
    }
} catch {
    $failures.Add($_.Exception.Message)
}

if ($failures.Count) {
    throw ($failures -join [Environment]::NewLine)
}

Write-Host 'Public firewall readiness checks passed.'
