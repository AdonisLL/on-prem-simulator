[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('DomainController', 'CertificateAuthority', 'DomainAccounts', 'DiscoveryAccess', 'DomainMember', 'Web', 'Sql', 'SqlDiscovery', 'Traffic')]
    [string]$Role,
    [Parameter(Mandatory)][string]$DomainName,
    [string]$NetbiosName = 'CONTOSO',
    [string]$DomainControllerIp = '10.50.2.4',
    [pscredential]$DomainCredential,
    [securestring]$SafeModePassword,
    [pscredential]$AppPoolCredential,
    [securestring]$WebServicePassword,
    [securestring]$DiscoveryPassword,
    [securestring]$SqlDiscoveryPassword,
    [string[]]$ComputerName,
    [string]$PackagePath,
    [string]$SchemaScript,
    [string]$SeedScript,
    [string[]]$WebUrl = @('http://web01.corp.contoso.local', 'http://web02.corp.contoso.local')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabConfiguration.psm1') -Force

switch ($Role) {
    'DomainController' {
        if (-not $SafeModePassword) { throw 'SafeModePassword is required.' }
        Install-LabDomainController -DomainName $DomainName -NetbiosName $NetbiosName -SafeModePassword $SafeModePassword
    }
    'CertificateAuthority' {
        Install-LabCertificateAuthority -CommonName "$NetbiosName Lab Root CA"
        Enable-LabWinRmHttps -DnsName "$env:COMPUTERNAME.$DomainName"
    }
    'DomainAccounts' {
        if (-not $WebServicePassword -or -not $DiscoveryPassword) { throw 'Both service-account passwords are required.' }
        New-LabDomainAccounts -WebServicePassword $WebServicePassword -DiscoveryPassword $DiscoveryPassword
    }
    'DiscoveryAccess' {
        if (-not $DiscoveryPassword -or -not $ComputerName) { throw 'DiscoveryPassword and ComputerName are required.' }
        New-LabDiscoveryIdentity -SamAccountName 'svc-migrate' -Password $DiscoveryPassword -ComputerName $ComputerName
    }
    'DomainMember' {
        if (-not $DomainCredential) { throw 'DomainCredential is required.' }
        Join-LabDomain -DomainName $DomainName -Credential $DomainCredential -DomainControllerIp $DomainControllerIp
    }
    'Web' {
        if (-not $PackagePath -or -not $AppPoolCredential) { throw 'PackagePath and AppPoolCredential are required.' }
        Install-LabIisApplication -PackagePath $PackagePath -AppPoolCredential $AppPoolCredential
        Enable-LabWinRmHttps -DnsName "$env:COMPUTERNAME.$DomainName"
    }
    'Sql' {
        if (-not $SchemaScript -or -not $SeedScript) { throw 'SchemaScript and SeedScript are required.' }
        Install-LabDatabase -SchemaScript $SchemaScript -SeedScript $SeedScript -WebServiceAccount "$NetbiosName\svc-legacyweb"
        Enable-LabWinRmHttps -DnsName "$env:COMPUTERNAME.$DomainName"
    }
    'SqlDiscovery' {
        if (-not $SqlDiscoveryPassword) { throw 'SqlDiscoveryPassword is required.' }
        New-LabSqlDiscoveryLogin -LoginName 'migrate_discovery' -Password $SqlDiscoveryPassword
    }
    'Traffic' {
        Install-LabSyntheticTraffic -WebUrl $WebUrl
    }
}
