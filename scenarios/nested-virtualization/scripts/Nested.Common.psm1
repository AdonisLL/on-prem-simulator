Set-StrictMode -Version Latest

function Get-NestedScenarioRoot {
    Split-Path $PSScriptRoot -Parent
}

function Get-NestedRepositoryRoot {
    $scenarioRoot = Get-NestedScenarioRoot
    Split-Path (Split-Path $scenarioRoot -Parent) -Parent
}

function Assert-NestedCommand {
    param([Parameter(Mandatory)][string]$Name, [string]$Hint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is required. $Hint"
    }
}

function Get-NestedDefinition {
    Get-Content (Join-Path (Get-NestedScenarioRoot) 'scenario-definition.json') -Raw | ConvertFrom-Json
}

function Get-NestedHostVmName {
    param([Parameter(Mandatory)][string]$NamePrefix)
    "$NamePrefix-hyperv01"
}

function ConvertTo-NestedBase64 {
    param([Parameter(Mandatory)][string]$Value)
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

function Resolve-NestedMediaManifest {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = Resolve-Path $Path -ErrorAction Stop
    $manifest = Get-Content $resolved -Raw | ConvertFrom-Json
    foreach ($name in 'serverBaseVhdx','migrateApplianceVhd','sharedContent') {
        if (-not $manifest.PSObject.Properties[$name]) {
            throw "Guest media manifest is missing $name."
        }
    }
    foreach ($name in 'serverBaseVhdx','migrateApplianceVhd') {
        $validationPath = $manifest.$name.workstationValidationPath
        if ($validationPath -and -not (Test-Path $validationPath -PathType Leaf)) {
            throw "Approved media validation path does not exist: $validationPath"
        }
        $expectedHash = $manifest.$name.sha256
        if ($validationPath -and $expectedHash -and $expectedHash -notlike 'REPLACE_*') {
            $actualHash = (Get-FileHash $validationPath -Algorithm SHA256).Hash
            if ($actualHash -ne $expectedHash) {
                throw "SHA256 validation failed for $validationPath."
            }
        }
    }
    [pscustomobject]@{
        Path = $resolved.Path
        Json = $manifest | ConvertTo-Json -Depth 20 -Compress
    }
}

function Assert-NestedAzurePreflight {
    param(
        [Parameter(Mandatory)][string]$Location,
        [Parameter(Mandatory)][string]$HostVmSize,
        [Parameter(Mandatory)][string]$HostImageUrn
    )

    Assert-NestedCommand az 'Install Azure CLI and authenticate with az login.'
    $accountId = & az account show --query id --output tsv --only-show-errors
    if ($LASTEXITCODE -ne 0 -or -not $accountId) {
        throw 'Azure CLI is not authenticated.'
    }

    $sku = & az vm list-skus --location $Location --size $HostVmSize --all --output json --only-show-errors | ConvertFrom-Json
    $sku = $sku | Where-Object name -eq $HostVmSize | Select-Object -First 1
    if (-not $sku) {
        throw "$HostVmSize is unavailable in $Location."
    }
    $capabilities = @{}
    foreach ($capability in $sku.capabilities) {
        $capabilities[$capability.name] = $capability.value
    }
    $apiAdvertisesNested = (
        $capabilities.ContainsKey('NestedVirtualization') -and
        $capabilities['NestedVirtualization'] -eq 'True'
    )
    # Azure's SKU API omits the nested capability for some documented families.
    $documentedNestedFamily = $HostVmSize -match '^Standard_D\d+s_v5$'
    if (-not $apiAdvertisesNested -and -not $documentedNestedFamily) {
        throw "$HostVmSize does not advertise NestedVirtualization=True in $Location."
    }
    if (
        -not $capabilities.ContainsKey('vCPUs') -or
        -not $capabilities.ContainsKey('MemoryGB') -or
        [int]$capabilities['vCPUs'] -lt 22 -or
        [decimal]$capabilities['MemoryGB'] -lt 60
    ) {
        throw "$HostVmSize is below the scenario floor of 22 vCPUs and 60 GB RAM."
    }

    $regionalUsage = & az vm list-usage --location $Location --output json --only-show-errors | ConvertFrom-Json
    $regionalVcpu = $regionalUsage | Where-Object { $_.name.value -eq 'cores' } | Select-Object -First 1
    if (
        -not $regionalVcpu -or
        ($regionalVcpu.limit - $regionalVcpu.currentValue) -lt [int]$capabilities['vCPUs']
    ) {
        throw "Insufficient regional vCPU quota for $HostVmSize in $Location."
    }

    & az vm image show --location $Location --urn $HostImageUrn --output none --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        throw "Host image $HostImageUrn is unavailable in $Location."
    }
}

function Invoke-NestedHostScript {
    param(
        [Parameter(Mandatory)][string]$ResourceGroupName,
        [Parameter(Mandatory)][string]$HostVmName,
        [Parameter(Mandatory)][string]$ScriptName,
        [string[]]$Parameters
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    $arguments = @(
        'vm','run-command','invoke',
        '--resource-group',$ResourceGroupName,
        '--name',$HostVmName,
        '--command-id','RunPowerShellScript',
        '--scripts',"@$scriptPath",
        '--only-show-errors',
        '--output','json'
    )
    if ($Parameters) {
        $arguments += '--parameters'
        $arguments += $Parameters
    }

    function Wait-NestedAzureVmReady {
        param(
            [Parameter(Mandatory)][string]$ResourceGroupName,
            [Parameter(Mandatory)][string]$HostVmName
        )

        $deadline = [DateTime]::UtcNow.AddMinutes(15)
        do {
            $state = & az vm get-instance-view --resource-group $ResourceGroupName `
                --name $HostVmName `
                --query "instanceView.statuses[?starts_with(code, 'PowerState/')].code | [0]" `
                --output tsv --only-show-errors
            if ($state -eq 'PowerState/running') {
                Start-Sleep -Seconds 30
                return
            }
            Start-Sleep -Seconds 15
        } while ([DateTime]::UtcNow -lt $deadline)
        throw "$HostVmName did not return to a running state."
    }
    $result = & az @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$ScriptName failed on $HostVmName."
    }
    $result | ConvertFrom-Json
}

Export-ModuleMember -Function *
