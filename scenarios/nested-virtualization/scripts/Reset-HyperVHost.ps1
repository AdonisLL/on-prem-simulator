param([Parameter(Mandatory)][string]$ScenarioDefinitionBase64)

$ErrorActionPreference = 'Stop'
$definition = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($ScenarioDefinitionBase64)
) | ConvertFrom-Json
foreach ($role in $definition.innerVms | Sort-Object startDelay -Descending) {
    $vm = Get-VM -Name $role.name -ErrorAction SilentlyContinue
    if ($vm -and $vm.State -eq 'Running') {
        Stop-VM $role.name -Force -TurnOff | Out-Null
    }
}
foreach ($role in $definition.innerVms | Sort-Object startDelay) {
    if (Get-VM -Name $role.name -ErrorAction SilentlyContinue) {
        Start-VM $role.name | Out-Null
    }
}
Write-Host 'Nested guests restarted in dependency order.'
