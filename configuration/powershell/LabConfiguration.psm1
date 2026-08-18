Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This configuration must run from an elevated PowerShell session.'
    }
}

function Wait-LabCondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Condition,
        [Parameter(Mandatory)][string]$FailureMessage,
        [int]$TimeoutSeconds = 600,
        [int]$IntervalSeconds = 10
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (& $Condition) {
            return
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
    throw $FailureMessage
}

function Install-LabDomainController {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DomainName,
        [Parameter(Mandatory)][string]$NetbiosName,
        [Parameter(Mandatory)][securestring]$SafeModePassword
    )

    Assert-Administrator
    if ((Get-CimInstance Win32_ComputerSystem).Domain -ieq $DomainName) {
        return
    }

    $adapter = Get-NetAdapter | Where-Object Status -eq Up | Sort-Object ifIndex | Select-Object -First 1
    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses '127.0.0.1'
    Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools | Out-Null
    Import-Module ADDSDeployment
    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetbiosName $NetbiosName `
        -SafeModeAdministratorPassword $SafeModePassword `
        -InstallDns `
        -NoRebootOnCompletion `
        -Force
}

function Install-LabCertificateAuthority {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CommonName)

    Assert-Administrator
    if (Get-Service CertSvc -ErrorAction SilentlyContinue) {
        return
    }

    Import-Module ActiveDirectory
    Wait-LabCondition `
        -Condition {
            try {
                Get-ADDomain -ErrorAction Stop | Out-Null
                $true
            } catch {
                $false
            }
        } `
        -FailureMessage 'Active Directory did not become ready before certificate authority configuration.'
    Install-WindowsFeature ADCS-Cert-Authority, ADCS-Web-Enrollment, GPMC -IncludeManagementTools | Out-Null
    Install-AdcsCertificationAuthority `
        -CAType EnterpriseRootCA `
        -CACommonName $CommonName `
        -KeyLength 2048 `
        -HashAlgorithmName SHA256 `
        -ValidityPeriod Years `
        -ValidityPeriodUnits 5 `
        -Force | Out-Null

    Import-Module GroupPolicy
    Set-GPRegistryValue `
        -Name 'Default Domain Policy' `
        -Key 'HKLM\SOFTWARE\Policies\Microsoft\Cryptography\AutoEnrollment' `
        -ValueName AEPolicy `
        -Type DWord `
        -Value 7 | Out-Null
    gpupdate.exe /force | Out-Null
}

function Join-LabDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$DomainName,
        [Parameter(Mandatory)][pscredential]$Credential,
        [Parameter(Mandatory)][string]$DomainControllerIp
    )

    Assert-Administrator
    $adapter = Get-NetAdapter | Where-Object Status -eq Up | Sort-Object ifIndex | Select-Object -First 1
    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses $DomainControllerIp

    if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
        return
    }

    Wait-LabCondition `
        -Condition { Test-NetConnection -ComputerName $DomainControllerIp -Port 389 -InformationLevel Quiet } `
        -FailureMessage "Domain controller $DomainControllerIp did not expose LDAP within the timeout."
    Add-Computer -DomainName $DomainName -Credential $Credential -Force
}

function New-LabDiscoveryIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SamAccountName,
        [Parameter(Mandatory)][securestring]$Password,
        [Parameter(Mandatory)][string[]]$ComputerName
    )

    Assert-Administrator
    Import-Module ActiveDirectory
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'")) {
        New-ADUser `
            -Name 'Azure Migrate Discovery' `
            -SamAccountName $SamAccountName `
            -AccountPassword $Password `
            -Enabled $true `
            -PasswordNeverExpires $true `
            -Description 'Least-privilege account for the ephemeral modernization lab'
    }

    function New-LabDomainAccounts {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][securestring]$WebServicePassword,
            [Parameter(Mandatory)][securestring]$DiscoveryPassword
        )

        Assert-Administrator
        Import-Module ActiveDirectory
        $accounts = @(
            @{ Name = 'Legacy Web Service'; Sam = 'svc-legacyweb'; Password = $WebServicePassword },
            @{ Name = 'Azure Migrate Discovery'; Sam = 'svc-migrate'; Password = $DiscoveryPassword }
        )
        foreach ($account in $accounts) {
            if (-not (Get-ADUser -Filter "SamAccountName -eq '$($account.Sam)'")) {
                New-ADUser `
                    -Name $account.Name `
                    -SamAccountName $account.Sam `
                    -AccountPassword $account.Password `
                    -Enabled $true `
                    -PasswordNeverExpires $true `
                    -Description 'Ephemeral modernization lab service identity'
            }
        }
        foreach ($groupName in 'Remote Management Users', 'Performance Monitor Users', 'Performance Log Users') {
            Add-ADGroupMember -Identity $groupName -Members 'svc-migrate' -ErrorAction SilentlyContinue
        }
    }

    foreach ($computer in $ComputerName) {
        Invoke-Command -ComputerName $computer -UseSSL -ScriptBlock {
            param($DomainUser)
            foreach ($group in 'Remote Management Users', 'Performance Monitor Users', 'Performance Log Users') {
                Add-LocalGroupMember -Group $group -Member $DomainUser -ErrorAction SilentlyContinue
            }
            if (Get-LocalGroup -Name 'IIS_IUSRS' -ErrorAction SilentlyContinue) {
                Add-LocalGroupMember -Group 'IIS_IUSRS' -Member $DomainUser -ErrorAction SilentlyContinue
                icacls.exe 'C:\Windows\System32\inetsrv\config' /grant "${DomainUser}:(OI)(CI)R" /T /C | Out-Null
            }

            $sid = ([Security.Principal.NTAccount]$DomainUser).Translate([Security.Principal.SecurityIdentifier]).Value
            $cfg = Join-Path $env:TEMP "$([Guid]::NewGuid()).inf"
            $db = Join-Path $env:TEMP "$([Guid]::NewGuid()).sdb"
            try {
                secedit.exe /export /cfg $cfg /areas USER_RIGHTS | Out-Null
                $content = Get-Content $cfg
                $line = $content | Where-Object { $_ -match '^SeBatchLogonRight\s*=' } | Select-Object -First 1
                if ($line -notmatch [Regex]::Escape("*$sid")) {
                    if ($line) {
                        $replacement = "$line,*$sid"
                        $content = $content | ForEach-Object { if ($_ -eq $line) { $replacement } else { $_ } }
                    } else {
                        $content += "SeBatchLogonRight = *$sid"
                    }
                    $content | Set-Content $cfg -Encoding Unicode
                    secedit.exe /configure /db $db /cfg $cfg /areas USER_RIGHTS | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "Failed to grant log on as a batch job to $DomainUser." }
                }
            } finally {
                Remove-Item $cfg, $db -Force -ErrorAction SilentlyContinue
            }
        } -ArgumentList "$env:USERDOMAIN\$SamAccountName"
    }
}

function Enable-LabWinRmHttps {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$DnsName)

    Assert-Administrator
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    gpupdate.exe /force | Out-Null
    certutil.exe -pulse | Out-Null

    $certificate = Get-ChildItem Cert:\LocalMachine\My |
        Where-Object {
            $_.NotAfter -gt [DateTime]::UtcNow -and
            $_.HasPrivateKey -and
            $_.EnhancedKeyUsageList.ObjectId -contains '1.3.6.1.5.5.7.3.1' -and
            $_.DnsNameList.Unicode -contains $DnsName
        } |
        Sort-Object NotAfter -Descending |
        Select-Object -First 1
    if (-not $certificate) {
        throw "No CA-issued Server Authentication certificate was found for $DnsName."
    }

    $existing = Get-ChildItem WSMan:\localhost\Listener |
        Where-Object { $_.Keys -contains 'Transport=HTTPS' }
    if (-not $existing) {
        New-WSManInstance `
            -ResourceURI winrm/config/Listener `
            -SelectorSet @{ Address = '*'; Transport = 'HTTPS' } `
            -ValueSet @{ Hostname = $DnsName; CertificateThumbprint = $certificate.Thumbprint } | Out-Null
    }

    Get-NetFirewallRule -DisplayName 'Azure Migrate WinRM HTTPS' -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule
    New-NetFirewallRule `
        -DisplayName 'Azure Migrate WinRM HTTPS' `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort 5986 `
        -Action Allow | Out-Null

    Get-ChildItem WSMan:\localhost\Listener |
        Where-Object { $_.Keys -contains 'Transport=HTTP' } |
        Remove-Item -Recurse -Force
}

function Install-LabIisApplication {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackagePath,
        [string]$SiteName = 'LegacyWeb',
        [string]$Destination = 'C:\inetpub\LegacyWeb',
        [Parameter(Mandatory)][pscredential]$AppPoolCredential
    )

    Assert-Administrator
    Install-WindowsFeature Web-Server, Web-Windows-Auth, Web-Asp-Net45, Web-Mgmt-Tools -IncludeManagementTools | Out-Null
    if (Test-Path $Destination) {
        Remove-Item "$Destination\*" -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        New-Item -Path $Destination -ItemType Directory -Force | Out-Null
    }
    Expand-Archive -Path $PackagePath -DestinationPath $Destination -Force

    Import-Module WebAdministration
    if (-not (Test-Path "IIS:\AppPools\$SiteName")) {
        New-WebAppPool -Name $SiteName | Out-Null
    }
    Add-LocalGroupMember -Group 'IIS_IUSRS' -Member $AppPoolCredential.UserName -ErrorAction SilentlyContinue
    $uploadPath = Join-Path $Destination 'App_Data\Uploads'
    New-Item -Path $uploadPath -ItemType Directory -Force | Out-Null
    icacls.exe $uploadPath /grant "$($AppPoolCredential.UserName):(OI)(CI)M" /T /C | Out-Null
    Set-ItemProperty "IIS:\AppPools\$SiteName" -Name managedRuntimeVersion -Value 'v4.0'
    Set-ItemProperty "IIS:\AppPools\$SiteName" -Name processModel.identityType -Value 3
    Set-ItemProperty "IIS:\AppPools\$SiteName" -Name processModel.userName -Value $AppPoolCredential.UserName
    Set-ItemProperty "IIS:\AppPools\$SiteName" -Name processModel.password -Value $AppPoolCredential.GetNetworkCredential().Password

    if (Test-Path "IIS:\Sites\Default Web Site") {
        Remove-Website -Name 'Default Web Site'
    }
    if (-not (Test-Path "IIS:\Sites\$SiteName")) {
        New-Website -Name $SiteName -Port 80 -PhysicalPath $Destination -ApplicationPool $SiteName | Out-Null
    }
    Set-WebConfigurationProperty `
        -Filter '/system.webServer/security/authentication/anonymousAuthentication' `
        -Name enabled -Value true -PSPath 'IIS:\' -Location $SiteName
}

function Install-LabDatabase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SchemaScript,
        [Parameter(Mandatory)][string]$SeedScript,
        [Parameter(Mandatory)][string]$WebServiceAccount
    )

    Assert-Administrator
    $tcpPath = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQLServer\SuperSocketNetLib\Tcp\IPAll'
    if (-not (Test-Path $tcpPath)) {
        throw 'SQL Server 2016 default instance registry settings were not found.'
    }
    Set-ItemProperty -Path $tcpPath -Name TcpDynamicPorts -Value ''
    Set-ItemProperty -Path $tcpPath -Name TcpPort -Value '1433'
    Restart-Service MSSQLSERVER -Force

    Get-NetFirewallRule -DisplayName 'Legacy Lab SQL' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName 'Legacy Lab SQL' -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow | Out-Null

    $sqlcmd = Get-Command sqlcmd.exe -ErrorAction Stop
    $rawDisk = Get-Disk | Where-Object PartitionStyle -eq RAW | Sort-Object Number | Select-Object -First 1
    if ($rawDisk) {
        $rawDisk | Initialize-Disk -PartitionStyle GPT -PassThru |
            New-Partition -DriveLetter D -UseMaximumSize |
            Format-Volume -FileSystem NTFS -NewFileSystemLabel 'SQLData' -Confirm:$false | Out-Null
    }
    if (Test-Path 'D:\') {
        New-Item 'D:\SQLData', 'D:\SQLLog' -ItemType Directory -Force | Out-Null
        icacls.exe 'D:\SQLData' /grant 'NT SERVICE\MSSQLSERVER:(OI)(CI)F' /T /C | Out-Null
        icacls.exe 'D:\SQLLog' /grant 'NT SERVICE\MSSQLSERVER:(OI)(CI)F' /T /C | Out-Null
        @"
ALTER SERVER CONFIGURATION SET DEFAULT_DATA_PATH = 'D:\SQLData';
ALTER SERVER CONFIGURATION SET DEFAULT_LOG_PATH = 'D:\SQLLog';
"@ | & $sqlcmd.Source -S localhost -E -b
        if ($LASTEXITCODE -ne 0) { throw 'Configuring SQL data and log paths failed.' }
    }
    & $sqlcmd.Source -S localhost -E -b -i $SchemaScript
    if ($LASTEXITCODE -ne 0) { throw 'The schema script failed.' }
    & $sqlcmd.Source -S localhost -E -b -i $SeedScript
    if ($LASTEXITCODE -ne 0) { throw 'The seed script failed.' }

    $escapedAccount = $WebServiceAccount.Replace(']', ']]')
    $grantScript = @"
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$WebServiceAccount')
    CREATE LOGIN [$escapedAccount] FROM WINDOWS;
USE LegacyLab;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$WebServiceAccount')
    CREATE USER [$escapedAccount] FOR LOGIN [$escapedAccount];
ALTER ROLE db_datareader ADD MEMBER [$escapedAccount];
ALTER ROLE db_datawriter ADD MEMBER [$escapedAccount];
"@
    $grantScript | & $sqlcmd.Source -S localhost -E -b
    if ($LASTEXITCODE -ne 0) { throw 'Granting the web service account failed.' }
}

function New-LabSqlDiscoveryLogin {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LoginName,
        [Parameter(Mandatory)][securestring]$Password
    )

    Assert-Administrator
    $plainPassword = [Net.NetworkCredential]::new('', $Password).Password.Replace("'", "''")
    try {
        $statement = @"
IF NOT EXISTS (SELECT 1 FROM sys.sql_logins WHERE name = N'$LoginName')
BEGIN
    CREATE LOGIN [$LoginName] WITH PASSWORD = N'$plainPassword', CHECK_POLICY = ON;
    GRANT VIEW SERVER STATE TO [$LoginName];
    GRANT VIEW ANY DEFINITION TO [$LoginName];
    GRANT CONNECT ANY DATABASE TO [$LoginName];
END;
"@
        $statement | sqlcmd.exe -S localhost -E -b
        if ($LASTEXITCODE -ne 0) { throw 'Creating the SQL discovery login failed.' }
    } finally {
        $plainPassword = $null
    }
}

function Install-LabSyntheticTraffic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$WebUrl,
        [int]$IntervalMinutes = 2
    )

    Assert-Administrator
    $scriptPath = 'C:\ProgramData\OnPremLab\Invoke-SyntheticTraffic.ps1'
    New-Item -Path (Split-Path $scriptPath) -ItemType Directory -Force | Out-Null
    $urls = ($WebUrl | ForEach-Object { "'$($_.Replace("'", "''"))'" }) -join ','
    @"
`$ErrorActionPreference = 'Stop'
foreach (`$url in @($urls)) {
    Invoke-WebRequest -Uri `$url -UseBasicParsing -TimeoutSec 30 | Out-Null
}
"@ | Set-Content -Path $scriptPath -Encoding UTF8

    $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
        -RepetitionDuration (New-TimeSpan -Days 365)
    Register-ScheduledTask -TaskName 'OnPremLab-SyntheticTraffic' -Action $action -Trigger $trigger -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
}

Export-ModuleMember -Function *
