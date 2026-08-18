param([Parameter(Mandatory)][string]$ScenarioDefinitionBase64)

$ErrorActionPreference = 'Stop'
$definition = [Text.Encoding]::UTF8.GetString(
    [Convert]::FromBase64String($ScenarioDefinitionBase64)
) | ConvertFrom-Json

$failures = [Collections.Generic.List[string]]::new()
if (-not (Get-WindowsFeature Hyper-V).Installed) { $failures.Add('Hyper-V is not installed.') }
if (-not (Get-VMSwitch -Name $definition.host.internalSwitch -ErrorAction SilentlyContinue)) {
    $failures.Add('Internal switch is missing.')
}
if (-not (Get-NetNat -Name $definition.host.natName -ErrorAction SilentlyContinue)) {
    $failures.Add('Inner NAT is missing.')
}
foreach ($role in $definition.innerVms) {
    $vm = Get-VM -Name $role.name -ErrorAction SilentlyContinue
    if (-not $vm) { $failures.Add("$($role.name) is missing."); continue }
    if ($vm.State -ne 'Running') { $failures.Add("$($role.name) is not running.") }
}
if ($failures.Count) { throw ($failures -join [Environment]::NewLine) }
Write-Host 'Nested Hyper-V host readiness checks passed.'
