[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Role,
    [Parameter(Mandatory)][string]$StorageAccountName,
    [Parameter(Mandatory)][string]$KeyVaultName,
    [ValidateSet('Storage', 'Local')][string]$ArtifactSource = 'Storage',
    [string]$DomainName = 'corp.contoso.local',
    [string]$NetbiosName = 'CONTOSO',
    [string]$DomainControllerIp = '10.50.2.4',
    [string]$ComputerNamesCsv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = 'C:\ProgramData\OnPremLab'
$archive = Join-Path $root 'lab.zip'
$content = Join-Path $root 'content'
New-Item -Path $root -ItemType Directory -Force | Out-Null

if ($Role -eq 'DomainController') {
    $interface = Get-NetIPConfiguration |
        Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.IPv4Address -and $_.IPv4DefaultGateway } |
        Sort-Object InterfaceIndex |
        Select-Object -First 1
    if (-not $interface) {
        throw 'No active IPv4 interface with a default gateway was found.'
    }
    Set-DnsClientServerAddress -InterfaceIndex $interface.InterfaceIndex -ServerAddresses '168.63.129.16'
}

function Get-ManagedIdentityToken {
    param([Parameter(Mandatory)][string]$Resource)
    $encoded = [Uri]::EscapeDataString($Resource)
    (Invoke-RestMethod `
        -Headers @{ Metadata = 'true' } `
        -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2019-08-01&resource=$encoded").access_token
}

function Get-KeyVaultSecretValue {
    param([Parameter(Mandatory)][string]$Name)
    $token = Get-ManagedIdentityToken -Resource 'https://vault.azure.net'
    (Invoke-RestMethod `
        -Headers @{ Authorization = "Bearer $token" } `
        -Uri "https://$KeyVaultName.vault.azure.net/secrets/${Name}?api-version=7.4").value
}

if ($ArtifactSource -eq 'Storage') {
    $storageToken = Get-ManagedIdentityToken -Resource 'https://storage.azure.com/'
    Invoke-WebRequest `
        -Headers @{
            Authorization = "Bearer $storageToken"
            'x-ms-version' = '2023-11-03'
        } `
        -Uri "https://$StorageAccountName.blob.core.windows.net/artifacts/lab.zip" `
        -OutFile $archive `
        -UseBasicParsing
} elseif (-not (Test-Path $archive -PathType Leaf)) {
    throw "Local artifact source selected, but $archive does not exist. Stage lab.zip on this VM before running guest configuration."
}

if (Test-Path $content) {
    Remove-Item $content -Recurse -Force
}
Expand-Archive -Path $archive -DestinationPath $content -Force

$invoke = Join-Path $content 'configuration\powershell\Invoke-RoleConfiguration.ps1'
$adminPassword = ConvertTo-SecureString (Get-KeyVaultSecretValue 'admin-password') -AsPlainText -Force
$domainCredential = [pscredential]::new("$NetbiosName\labadmin", $adminPassword)
$localAdministratorCredential = [pscredential]::new("$env:COMPUTERNAME\labadmin", $adminPassword)
$arguments = @{
    Role               = $Role
    DomainName         = $DomainName
    NetbiosName        = $NetbiosName
    DomainControllerIp = $DomainControllerIp
}

switch ($Role) {
    'DomainController' { $arguments.SafeModePassword = $adminPassword }
    'DomainMember' { $arguments.DomainCredential = $domainCredential }
    'DomainAccounts' {
        $arguments.WebServicePassword = ConvertTo-SecureString (Get-KeyVaultSecretValue 'web-service-password') -AsPlainText -Force
        $arguments.DiscoveryPassword = ConvertTo-SecureString (Get-KeyVaultSecretValue 'migrate-discovery-password') -AsPlainText -Force
    }
    'DiscoveryAccess' {
        $arguments.DomainCredential = $domainCredential
        $arguments.DiscoveryPassword = ConvertTo-SecureString (Get-KeyVaultSecretValue 'migrate-discovery-password') -AsPlainText -Force
        $arguments.ComputerName = $ComputerNamesCsv -split ','
    }
    'Web' {
        $webPassword = ConvertTo-SecureString (Get-KeyVaultSecretValue 'web-service-password') -AsPlainText -Force
        $arguments.AppPoolCredential = [pscredential]::new("$NetbiosName\svc-legacyweb", $webPassword)
        $arguments.PackagePath = Join-Path $content 'artifacts\LegacyWeb.zip'
    }
    'Sql' {
        $arguments.SchemaScript = Join-Path $content 'database\schema\001-LegacyLab.sql'
        $arguments.SeedScript = Join-Path $content 'database\seed\001-Products.sql'
    }
    'SqlDiscovery' {
        $arguments.SqlDiscoveryPassword = ConvertTo-SecureString (Get-KeyVaultSecretValue 'sql-discovery-password') -AsPlainText -Force
    }
}

if ($Role -in 'Sql', 'SqlDiscovery') {
    $invokeParameters = @{
        ComputerName   = 'localhost'
        Credential     = $localAdministratorCredential
        Authentication = 'Negotiate'
        ScriptBlock    = {
            param($ScriptPath, $ScriptArguments)
            & $ScriptPath @ScriptArguments
        }
        ArgumentList   = @($invoke, $arguments)
    }
    $listeners = Get-ChildItem WSMan:\localhost\Listener
    $httpListener = $listeners | Where-Object { $_.Keys -contains 'Transport=HTTP' }
    $httpsListener = $listeners | Where-Object { $_.Keys -contains 'Transport=HTTPS' }
    if (-not $httpListener -and $httpsListener) {
        $invokeParameters.UseSSL = $true
        $invokeParameters.SessionOption = New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck
    }
    Invoke-Command @invokeParameters
    if ($Role -eq 'Sql') {
        Import-Module (Join-Path $content 'configuration\powershell\LabConfiguration.psm1') -Force
        Enable-LabWinRmHttps -DnsName "$env:COMPUTERNAME.$DomainName"
    }
} else {
    & $invoke @arguments
}
