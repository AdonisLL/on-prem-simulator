param(
    [Parameter(Mandatory)][string]$ScenarioDefinitionBase64,
    [string]$GuestMediaManifestBase64,
    [string]$SkipGuestConfiguration = 'False'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-Base64Json {
    param([Parameter(Mandatory)][string]$Value)
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value)) | ConvertFrom-Json
}

$definition = ConvertFrom-Base64Json $ScenarioDefinitionBase64
$driveLetter = $definition.host.storageDriveLetter
$volume = Get-Volume -DriveLetter $driveLetter -ErrorAction SilentlyContinue
if (-not $volume) {
    $rawDisk = Get-Disk | Where-Object PartitionStyle -eq RAW | Sort-Object Number | Select-Object -First 1
    if (-not $rawDisk) {
        throw "No $driveLetter volume or RAW data disk was found."
    }
    $rawDisk | Initialize-Disk -PartitionStyle GPT -PassThru |
        New-Partition -DriveLetter $driveLetter -UseMaximumSize |
        Format-Volume -FileSystem NTFS -NewFileSystemLabel NestedLabData -Confirm:$false -Force | Out-Null
}

$feature = Install-WindowsFeature Hyper-V -IncludeManagementTools
if ($feature.RestartNeeded -ne 'No') {
    Write-Host 'NESTED_HOST_RESTART_REQUIRED'
    return
}

$switch = Get-VMSwitch -Name $definition.host.internalSwitch -ErrorAction SilentlyContinue
if (-not $switch) {
    New-VMSwitch -Name $definition.host.internalSwitch -SwitchType Internal | Out-Null
}
$alias = "vEthernet ($($definition.host.internalSwitch))"
$address = Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object IPAddress -eq $definition.host.hostAddress
if (-not $address) {
    New-NetIPAddress -InterfaceAlias $alias -IPAddress $definition.host.hostAddress -PrefixLength 24 | Out-Null
}
$nat = Get-NetNat -Name $definition.host.natName -ErrorAction SilentlyContinue
if (-not $nat) {
    New-NetNat -Name $definition.host.natName -InternalIPInterfaceAddressPrefix $definition.host.prefix | Out-Null
}

if ([Convert]::ToBoolean($SkipGuestConfiguration)) {
    Write-Host 'NESTED_HOST_INFRASTRUCTURE_READY'
    return
}
if (-not $GuestMediaManifestBase64) {
    throw 'Guest media manifest is required for guest creation.'
}
$manifest = ConvertFrom-Base64Json $GuestMediaManifestBase64
foreach ($entry in $manifest.serverBaseVhdx, $manifest.migrateApplianceVhd) {
    if (-not (Test-Path $entry.hostPath -PathType Leaf)) {
        throw "Approved host media is missing: $($entry.hostPath)"
    }
    if ($entry.sha256 -and $entry.sha256 -notlike 'REPLACE_*') {
        if ((Get-FileHash $entry.hostPath -Algorithm SHA256).Hash -ne $entry.sha256) {
            throw "Approved media hash mismatch: $($entry.hostPath)"
        }
    }
}
if (-not (Test-Path $manifest.sharedContent.hostPath -PathType Container)) {
    throw "Shared repository content is not staged at $($manifest.sharedContent.hostPath)."
}

$labRoot = "$driveLetter`:\NestedLab"
New-Item "$labRoot\VMs", "$labRoot\VHDX" -ItemType Directory -Force | Out-Null
foreach ($role in $definition.innerVms) {
    $media = if ($role.media -eq 'migrateApplianceVhd') {
        $manifest.migrateApplianceVhd.hostPath
    } else {
        $manifest.serverBaseVhdx.hostPath
    }
    $extension = [IO.Path]::GetExtension($media)
    $diskPath = "$labRoot\VHDX\$($role.name)$extension"
    if (-not (Test-Path $diskPath)) {
        Copy-Item $media $diskPath
    }
    $vm = Get-VM -Name $role.name -ErrorAction SilentlyContinue
    if (-not $vm) {
        New-VM -Name $role.name -Generation $role.generation `
            -MemoryStartupBytes ($role.memoryMb * 1MB) `
            -Path "$labRoot\VMs\$($role.name)" -VHDPath $diskPath `
            -SwitchName $definition.host.internalSwitch | Out-Null
    }
    Set-VM -Name $role.name -ProcessorCount $role.processors `
        -MemoryStartupBytes ($role.memoryMb * 1MB) -StaticMemory `
        -CheckpointType Disabled -AutomaticStartAction Start `
        -AutomaticStartDelay $role.startDelay | Out-Null
    if ((Get-VM $role.name).State -ne 'Running') {
        Start-VM $role.name | Out-Null
    }
}

Write-Host 'NESTED_GUESTS_CREATED'
Write-Warning 'Complete approved guest specialization, apply the documented static IPs, run shared role configuration, and register the Azure Migrate appliance interactively.'
