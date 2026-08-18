[CmdletBinding()]
param([Parameter(Mandatory)][string]$KeyVaultName)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-LabPassword {
    $characters = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%*-_'
    $bytes = [byte[]]::new(32)
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
    } finally {
        $generator.Dispose()
    }
    -join ($bytes | ForEach-Object { $characters[$_ % $characters.Length] })
}

function Set-LabSecret {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][securestring]$Value,
        [Parameter(Mandatory)][string]$AccessToken
    )

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    $plainValue = $null
    try {
        $plainValue = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        $body = @{ value = $plainValue } | ConvertTo-Json -Compress
        Invoke-RestMethod `
            -Method Put `
            -Headers @{ Authorization = "Bearer $AccessToken" } `
            -ContentType 'application/json' `
            -Uri "https://$KeyVaultName.vault.azure.net/secrets/$Name`?api-version=7.4" `
            -Body $body | Out-Null
    } finally {
        $plainValue = $null
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

$adapter = Get-NetAdapter | Where-Object Status -eq Up | Sort-Object ifIndex | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses '168.63.129.16'
$vaultAddresses = [Net.Dns]::GetHostAddresses("$KeyVaultName.vault.azure.net")
$hasPrivateAddress = $vaultAddresses | Where-Object {
    $_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork -and (
        $_.GetAddressBytes()[0] -eq 10 -or
        ($_.GetAddressBytes()[0] -eq 172 -and $_.GetAddressBytes()[1] -ge 16 -and $_.GetAddressBytes()[1] -le 31) -or
        ($_.GetAddressBytes()[0] -eq 192 -and $_.GetAddressBytes()[1] -eq 168)
    )
}
if (-not $hasPrivateAddress) {
    throw "Key Vault did not resolve to a private address. Verify the private endpoint and $KeyVaultName private DNS zone group."
}
$token = (Invoke-RestMethod `
    -Headers @{ Metadata = 'true' } `
    -Uri 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2019-08-01&resource=https%3A%2F%2Fvault.azure.net').access_token

$adminPassword = Read-Host 'Enter the labadmin password used by Repair-KeyVaultAccess.ps1' -AsSecureString
Set-LabSecret -Name 'admin-password' -Value $adminPassword -AccessToken $token
foreach ($name in 'web-service-password', 'migrate-discovery-password', 'sql-discovery-password') {
    $generatedPassword = ConvertTo-SecureString (New-LabPassword) -AsPlainText -Force
    Set-LabSecret -Name $name -Value $generatedPassword -AccessToken $token
}

Write-Host 'Lab secrets were created in Key Vault. Return to the deployment workstation and finalize Key Vault access.'