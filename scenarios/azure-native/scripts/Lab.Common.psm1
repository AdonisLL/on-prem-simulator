Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-LabCommand {
    param([Parameter(Mandatory)][string]$Name, [string]$InstallHint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is required. $InstallHint"
    }
}

function New-LabPassword {
    $characters = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%*-_'
    $bytes = [byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    -join ($bytes | ForEach-Object { $characters[$_ % $characters.Length] })
}

function Set-LabKeyVaultSecretFromMemory {
    param(
        [Parameter(Mandatory)][string]$VaultName,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )
    $temporaryFile = Join-Path ([IO.Path]::GetTempPath()) "$([Guid]::NewGuid()).secret"
    try {
        [IO.File]::WriteAllText($temporaryFile, $Value)
        $stored = $false
        $lastError = $null
        for ($attempt = 1; $attempt -le 20; $attempt++) {
            $lastError = & az keyvault secret set --vault-name $VaultName `
                --name $Name --file $temporaryFile --only-show-errors `
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
        Remove-Item $temporaryFile -Force -ErrorAction SilentlyContinue
    }
}

function Wait-LabVmReady {
    param([Parameter(Mandatory)][string]$ResourceGroupName, [Parameter(Mandatory)][string]$VmName)
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
        [string[]]$ComputerName
    )

    $parameters = @(
        "Role=$Role",
        "StorageAccountName=$StorageAccountName",
        "KeyVaultName=$KeyVaultName",
        "ArtifactSource=$ArtifactSource"
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

Export-ModuleMember -Function *
