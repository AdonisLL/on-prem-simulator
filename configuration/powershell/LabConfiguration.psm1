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

function Set-LabAzureDnsForwarder {
    Import-Module DnsServer
    Set-DnsServerForwarder -IPAddress '168.63.129.16'
}

function Get-LabPrimaryInterfaceIndex {
    $configuration = Get-NetIPConfiguration |
        Where-Object {
            $_.NetAdapter.Status -eq 'Up' -and
            $_.IPv4Address -and
            $_.IPv4DefaultGateway
        } |
        Sort-Object InterfaceIndex |
        Select-Object -First 1
    if (-not $configuration) {
        throw 'No active IPv4 interface with a default gateway was found.'
    }
    return [int]$configuration.InterfaceIndex
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
        Set-LabAzureDnsForwarder
        return
    }

    $interfaceIndex = Get-LabPrimaryInterfaceIndex
    Set-DnsClientServerAddress -InterfaceIndex $interfaceIndex -ServerAddresses '127.0.0.1'
    Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools | Out-Null
    Import-Module ADDSDeployment
    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetbiosName $NetbiosName `
        -SafeModeAdministratorPassword $SafeModePassword `
        -InstallDns `
        -NoRebootOnCompletion `
        -Force
    Set-LabAzureDnsForwarder
}

function Install-LabCertificateAuthority {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CommonName)

    Assert-Administrator
    Set-LabAzureDnsForwarder
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
    $interfaceIndex = Get-LabPrimaryInterfaceIndex
    Set-DnsClientServerAddress -InterfaceIndex $interfaceIndex -ServerAddresses $DomainControllerIp

    if ((Get-CimInstance Win32_ComputerSystem).PartOfDomain) {
        return
    }

    Wait-LabCondition `
        -Condition { Test-NetConnection -ComputerName $DomainControllerIp -Port 389 -InformationLevel Quiet } `
        -FailureMessage "Domain controller $DomainControllerIp did not expose LDAP within the timeout."
    Add-Computer -DomainName $DomainName -Credential $Credential -Force
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

function New-LabDiscoveryIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SamAccountName,
        [Parameter(Mandatory)][securestring]$Password,
        [Parameter(Mandatory)][pscredential]$Credential,
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

    foreach ($computer in $ComputerName) {
        Invoke-Command -ComputerName $computer -UseSSL -Credential $Credential -ScriptBlock {
            param($DomainUser)
            foreach ($group in 'Remote Management Users', 'Performance Monitor Users', 'Performance Log Users') {
                Add-LocalGroupMember -Group $group -Member $DomainUser -ErrorAction SilentlyContinue
            }
            if (Get-LocalGroup -Name 'IIS_IUSRS' -ErrorAction SilentlyContinue) {
                Add-LocalGroupMember -Group 'IIS_IUSRS' -Member $DomainUser -ErrorAction SilentlyContinue
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

    $getServerCertificate = {
        Get-ChildItem Cert:\LocalMachine\My |
            Where-Object {
                $enhancedKeyUsage = $_.Extensions |
                    Where-Object { $_.Oid.Value -eq '2.5.29.37' } |
                    Select-Object -First 1
                $hasServerAuthentication = $enhancedKeyUsage -and @(
                    $enhancedKeyUsage.EnhancedKeyUsages |
                    Where-Object { $_.Value -eq '1.3.6.1.5.5.7.3.1' }
                ).Count -gt 0

                $_.NotAfter -gt [DateTime]::UtcNow -and
                $_.HasPrivateKey -and
                $hasServerAuthentication -and
                $_.DnsNameList.Unicode -contains $DnsName
            } |
            Sort-Object NotAfter -Descending |
            Select-Object -First 1
    }
    $certificate = & $getServerCertificate
    if (-not $certificate) {
        Get-Certificate -Template Machine -CertStoreLocation Cert:\LocalMachine\My | Out-Null
        Wait-LabCondition `
            -Condition { [bool](& $getServerCertificate) } `
            -FailureMessage "Machine certificate enrollment did not complete for $DnsName." `
            -TimeoutSeconds 120 `
            -IntervalSeconds 5
        $certificate = & $getServerCertificate
    }
    if (-not $certificate) {
        throw "No CA-issued Server Authentication certificate was found for $DnsName."
    }

    $existing = @(
        Get-ChildItem WSMan:\localhost\Listener |
            Where-Object { $_.Keys -contains 'Transport=HTTPS' }
    )
    $matchingListener = $existing | Where-Object {
        $thumbprint = Get-ChildItem $_.PSPath |
            Where-Object Name -eq 'CertificateThumbprint' |
            Select-Object -ExpandProperty Value -First 1
        $thumbprint -eq $certificate.Thumbprint
    }
    if (-not $matchingListener) {
        $existing | Remove-Item -Recurse -Force
        New-Item `
            -Path WSMan:\localhost\Listener `
            -Address '*' `
            -Transport HTTPS `
            -CertificateThumbPrint $certificate.Thumbprint `
            -Force | Out-Null
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
    $dataVolume = Get-Volume |
        Where-Object FileSystemLabel -eq 'SQLData' |
        Select-Object -First 1
    if (-not $dataVolume) {
        $dataDisk = Get-Disk |
            Where-Object {
                -not $_.IsBoot -and
                -not $_.IsSystem -and
                $_.Location -match '(?i)\bLUN\s+0$'
            } |
            Where-Object {
                if ($_.PartitionStyle -eq 'RAW') {
                    return $true
                }

                $dataPartitions = @(
                    Get-Partition -DiskNumber $_.Number -ErrorAction SilentlyContinue |
                    Where-Object Type -ne 'Reserved'
                )
                return $dataPartitions.Count -eq 0
            } |
            Sort-Object Number |
            Select-Object -First 1
        if (-not $dataDisk) {
            throw 'An uninitialized managed SQL data disk attached at LUN 0 was not found.'
        }
        if ($dataDisk.PartitionStyle -eq 'RAW') {
            $dataDisk = $dataDisk | Initialize-Disk -PartitionStyle GPT -PassThru
        }
        $dataPartition = Get-Partition -DiskNumber $dataDisk.Number |
            Where-Object Type -ne 'Reserved' |
            Select-Object -First 1
        if (-not $dataPartition) {
            $dataPartition = New-Partition -DiskNumber $dataDisk.Number -AssignDriveLetter -UseMaximumSize
        } elseif (-not $dataPartition.DriveLetter) {
            $dataPartition | Add-PartitionAccessPath -AssignDriveLetter
            $dataPartition = Get-Partition -DiskNumber $dataDisk.Number -PartitionNumber $dataPartition.PartitionNumber
        }
        $dataVolume = $dataPartition | Format-Volume -FileSystem NTFS -NewFileSystemLabel 'SQLData' -Confirm:$false
    }
    if ($dataVolume -and $dataVolume.DriveLetter) {
        $dataRoot = "$($dataVolume.DriveLetter):\"
        $dataPath = Join-Path $dataRoot 'SQLData'
        $logPath = Join-Path $dataRoot 'SQLLog'
        New-Item $dataPath, $logPath -ItemType Directory -Force | Out-Null
        icacls.exe $dataPath /grant 'NT SERVICE\MSSQLSERVER:(OI)(CI)F' /T /C | Out-Null
        icacls.exe $logPath /grant 'NT SERVICE\MSSQLSERVER:(OI)(CI)F' /T /C | Out-Null
        $instancePath = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQLServer'
        Set-ItemProperty -Path $instancePath -Name DefaultData -Value $dataPath
        Set-ItemProperty -Path $instancePath -Name DefaultLog -Value $logPath
        Restart-Service MSSQLSERVER -Force
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
