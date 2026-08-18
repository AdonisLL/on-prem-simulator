[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$scenarioRoot = Join-Path $root 'scenarios'
$failures = [Collections.Generic.List[string]]::new()
$contracts = Get-ChildItem $scenarioRoot -Filter 'parity-contract.json' -Recurse

if (-not $contracts) {
    throw 'No scenario parity contracts were found.'
}

foreach ($contractFile in $contracts) {
    $contractParent = Split-Path $contractFile.FullName -Parent
    $scenarioDirectory = if ((Split-Path $contractParent -Leaf) -eq 'infra') {
        Split-Path $contractParent -Parent
    } else {
        $contractParent
    }
    $scenarioName = Split-Path $scenarioDirectory -Leaf
    $contract = Get-Content $contractFile.FullName -Raw | ConvertFrom-Json
    $bicepFiles = Get-ChildItem "$scenarioDirectory\infra\bicep" -Filter '*.bicep' -Recurse -ErrorAction SilentlyContinue
    $terraformFiles = Get-ChildItem "$scenarioDirectory\infra\terraform" -Filter '*.tf' -Recurse -ErrorAction SilentlyContinue

    if (-not $bicepFiles) {
        $failures.Add("$scenarioName has no Bicep implementation.")
        continue
    }
    if (-not $terraformFiles) {
        $failures.Add("$scenarioName has no Terraform implementation.")
        continue
    }

    $bicep = ($bicepFiles | Get-Content -Raw) -join "`n"
    $terraform = ($terraformFiles | Get-Content -Raw) -join "`n"
    $scenarioImplementation = (
        Get-ChildItem $scenarioDirectory -File -Recurse |
            Where-Object {
                $_.Extension -in '.bicep', '.tf', '.ps1', '.psm1', '.json' -and
                $_.Name -ne 'parity-contract.json'
            } |
            Get-Content -Raw
    ) -join "`n"

    $azureVmRoles = if ($contract.PSObject.Properties.Name -contains 'azureVmRoles') {
        $contract.azureVmRoles
    } else {
        $contract.vmRoles
    }
    foreach ($vm in $azureVmRoles) {
        if ($bicep -notmatch [Regex]::Escape($vm)) {
            $failures.Add("$scenarioName Bicep does not declare Azure VM role $vm.")
        }
        if ($terraform -notmatch [Regex]::Escape($vm)) {
            $failures.Add("$scenarioName Terraform does not declare Azure VM role $vm.")
        }
    }

    foreach ($vm in $contract.vmRoles) {
        if ($scenarioImplementation -notmatch [Regex]::Escape($vm)) {
            $failures.Add("$scenarioName does not implement logical VM role $vm.")
        }
    }

    foreach ($subnet in $contract.subnets) {
        if ($bicep -notmatch [Regex]::Escape($subnet)) {
            $failures.Add("$scenarioName Bicep does not declare subnet $subnet.")
        }
        if ($terraform -notmatch [Regex]::Escape($subnet)) {
            $failures.Add("$scenarioName Terraform does not declare subnet $subnet.")
        }
    }

    foreach ($property in $contract.privateAddresses.PSObject.Properties) {
        if ($scenarioImplementation -notmatch [Regex]::Escape([string]$property.Value)) {
            $failures.Add("$scenarioName does not contain $($property.Name) address $($property.Value).")
        }
    }

    if ($scenarioName -eq 'azure-native') {
        if ($bicep -notmatch '@secure\(\)[\r\n]+\s*param adminPassword') {
            $failures.Add('azure-native Bicep does not mark the administrator password secure.')
        }
        if (
            $terraform -notmatch 'variable "admin_password"' -or
            $terraform -notmatch 'sensitive\s*=\s*true'
        ) {
            $failures.Add('azure-native Terraform does not mark the administrator password sensitive.')
        }
    }

    if (
        $bicep -match 'publicIPAddress:\s*\{\s*id:.*vm' -or
        $terraform -match 'public_ip_address_id\s*=.*windows'
    ) {
        $failures.Add("$scenarioName workload NIC appears to reference a public IP.")
    }
}

if ($failures.Count) {
    throw ($failures -join [Environment]::NewLine)
}

Write-Host "All $($contracts.Count) scenario IaC implementations satisfy their parity contracts."
