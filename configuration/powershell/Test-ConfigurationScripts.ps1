[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$failures = [Collections.Generic.List[string]]::new()
Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1' -Recurse | ForEach-Object {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($errorRecord in $errors) {
        $failures.Add("$($_.FullName): $($errorRecord.Message)")
    }
}
Get-ChildItem -Path $PSScriptRoot -Filter '*.psm1' -Recurse | ForEach-Object {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($errorRecord in $errors) {
        $failures.Add("$($_.FullName): $($errorRecord.Message)")
    }
}
$configurationModule = Get-Content (Join-Path $PSScriptRoot 'LabConfiguration.psm1') -Raw
if ($configurationModule -notmatch "Set-DnsServerForwarder\s+-IPAddress\s+'168\.63\.129\.16'") {
    $failures.Add('Domain DNS does not forward private Azure service lookups to the Azure DNS virtual IP.')
}
if ($configurationModule -match 'EnhancedKeyUsageList\.ObjectId') {
    $failures.Add('Certificate selection uses strict-mode-unsafe EnhancedKeyUsageList property enumeration.')
}
if ($configurationModule -match 'New-WSManInstance' -or
    $configurationModule -notmatch 'New-Item\s+`\s+-Path WSMan:\\localhost\\Listener[\s\S]*?-CertificateThumbPrint') {
    $failures.Add('WinRM HTTPS configuration does not use the WSMan provider certificate binding.')
}
if ($configurationModule -notmatch 'Get-Certificate -Template Machine -CertStoreLocation Cert:\\LocalMachine\\My') {
    $failures.Add('WinRM HTTPS configuration does not actively enroll missing machine certificates.')
}
if (-not $configurationModule.Contains('$_.Location -match ''(?i)\bLUN\s+0$''') -or
    $configurationModule -notmatch '\.PartitionStyle -eq ''RAW''[\s\S]*?\$dataPartitions\.Count -eq 0' -or
    $configurationModule -notmatch 'uninitialized managed SQL data disk attached at LUN 0 was not found') {
    $failures.Add('SQL setup does not select the managed data disk by attachment LUN.')
}
if ($configurationModule -notmatch "Where-Object Name -eq 'CertificateThumbprint'[\s\S]*?\`$existing \| Remove-Item -Recurse -Force") {
    $failures.Add('WinRM HTTPS configuration does not replace stale certificate bindings.')
}
if ($configurationModule -notmatch '(?m)^function New-LabDomainAccounts \{') {
    $failures.Add('Domain account configuration is not callable from module scope.')
}
if ($configurationModule -notmatch 'Invoke-Command -ComputerName \$computer -UseSSL -Credential \$Credential') {
    $failures.Add('Discovery access configuration does not authenticate its member-server remoting hop.')
}
if ($configurationModule -match "icacls\.exe 'C:\\Windows\\System32\\inetsrv\\config'") {
    $failures.Add('Discovery access configuration recursively mutates protected IIS schema ACLs.')
}
if ($configurationModule -match 'Get-NetAdapter\s*\|\s*Where-Object Status -eq Up' -or
    $configurationModule -notmatch 'function Get-LabPrimaryInterfaceIndex') {
    $failures.Add('Guest DNS configuration does not select the routed IPv4 interface.')
}
if ($configurationModule -match 'New-Partition\s+-DriveLetter D' -or
    $configurationModule -notmatch 'New-Partition\s+-DiskNumber \$dataDisk\.Number\s+-AssignDriveLetter') {
    $failures.Add('SQL data disk configuration assumes a fixed drive letter.')
}
if ($configurationModule -match 'ALTER SERVER CONFIGURATION SET DEFAULT_(?:DATA|LOG)_PATH' -or
    $configurationModule -notmatch 'Set-ItemProperty -Path \$instancePath -Name DefaultData') {
    $failures.Add('SQL default paths are not configured through SQL Server 2016 instance settings.')
}
$azureBootstrap = Get-Content (Join-Path $PSScriptRoot 'Invoke-AzureBootstrap.ps1') -Raw
if ($azureBootstrap -match '\$Name\?api-version') {
    $failures.Add('Azure bootstrap contains an ambiguous strict-mode Key Vault URI variable.')
}
if ($azureBootstrap -match 'Get-NetAdapter\s*\|\s*Where-Object Status -eq Up') {
    $failures.Add('Azure bootstrap DNS configuration may select an accelerated-networking virtual function.')
}
if ($azureBootstrap -notmatch "\`$Role -in 'Sql', 'SqlDiscovery'[\s\S]*?Credential\s*=\s*\`$localAdministratorCredential[\s\S]*?Invoke-Command") {
    $failures.Add('SQL roles do not run as the SQL image administrator.')
}
if ($azureBootstrap -notmatch "'DiscoveryAccess'\s*\{[\s\S]*?DomainCredential\s*=\s*\`$domainCredential") {
    $failures.Add('Discovery access bootstrap does not pass the domain administrator credential.')
}
$roleConfiguration = Get-Content (Join-Path $PSScriptRoot 'Invoke-RoleConfiguration.ps1') -Raw
if ($roleConfiguration -match "'Sql'\s*\{[\s\S]*?Install-LabDatabase[\s\S]*?Enable-LabWinRmHttps" -or
    $azureBootstrap -notmatch "Invoke-Command @invokeParameters[\s\S]*?\`$Role -eq 'Sql'[\s\S]*?Enable-LabWinRmHttps") {
    $failures.Add('SQL WinRM hardening can terminate its own privileged remoting session.')
}
if ($failures.Count -gt 0) {
    throw ($failures -join [Environment]::NewLine)
}
Write-Host 'PowerShell configuration scripts parsed successfully.'
