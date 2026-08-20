[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$scenarioRoot = Join-Path $root 'scenarios\public-firewall'
$bicep = Get-Content (Join-Path $scenarioRoot 'infra\bicep\main.bicep') -Raw
$bicepNetwork = Get-Content (Join-Path $scenarioRoot 'infra\bicep\modules\network.bicep') -Raw
$terraform = Get-Content (Join-Path $scenarioRoot 'infra\terraform\main.tf') -Raw
$deploy = Get-Content (Join-Path $scenarioRoot 'scripts\Deploy-Lab.ps1') -Raw
$test = Get-Content (Join-Path $scenarioRoot 'scripts\Test-Lab.ps1') -Raw
$failures = [Collections.Generic.List[string]]::new()

$requiredBicepPatterns = @{
    'required deployer CIDR parameter' = 'param deployerAddressPrefix string'
    'web01 DNAT port'                  = "destinationPorts:\s*\['80'\][\s\S]*?translatedAddress:\s*privateAddresses\.web01[\s\S]*?translatedPort:\s*'80'"
    'web02 DNAT port'                  = "destinationPorts:\s*\['80'\][\s\S]*?translatedAddress:\s*privateAddresses\.web02[\s\S]*?translatedPort:\s*'80'"
    'SQL DNAT translation'             = "destinationPorts:\s*\['1633'\][\s\S]*?translatedAddress:\s*privateAddresses\.sql01[\s\S]*?translatedPort:\s*'1433'"
}
foreach ($requirement in $requiredBicepPatterns.GetEnumerator()) {
    $content = if ($requirement.Key -eq 'required deployer CIDR parameter') { $bicep } else { $bicepNetwork }
    if ($content -notmatch $requirement.Value) {
        $failures.Add("Bicep is missing $($requirement.Key).")
    }
}

$requiredTerraformPatterns = @{
    'required deployer CIDR variable' = 'variable "deployer_address_prefix"'
    'web01 DNAT port'                 = 'name\s*=\s*"web01-http"[\s\S]*?destination_ports\s*=\s*\["80"\][\s\S]*?translated_port\s*=\s*"80"'
    'web02 DNAT port'                 = 'name\s*=\s*"web02-http"[\s\S]*?destination_ports\s*=\s*\["80"\][\s\S]*?translated_port\s*=\s*"80"'
    'SQL DNAT translation'            = 'name\s*=\s*"sql01-(?:tds|dnat)"[\s\S]*?destination_ports\s*=\s*\["1633"\][\s\S]*?translated_port\s*=\s*"1433"'
}
$terraformVariables = Get-Content (Join-Path $scenarioRoot 'infra\terraform\variables.tf') -Raw
foreach ($requirement in $requiredTerraformPatterns.GetEnumerator()) {
    $content = if ($requirement.Key -eq 'required deployer CIDR variable') { $terraformVariables } else { $terraform }
    if ($content -notmatch $requirement.Value) {
        $failures.Add("Terraform is missing $($requirement.Key).")
    }
}

if ($bicepNetwork -notmatch 'sourceAddresses:\s*\[deployerAddressPrefix\]') {
    $failures.Add('Bicep DNAT does not use the deployer CIDR as its source.')
}
if ($bicepNetwork -notmatch "name:\s*'AllowHttpFromFirewallDnat'[\s\S]*?sourceAddressPrefix:\s*firewallPrivateIpAddress") {
    $failures.Add('Bicep web NSG does not allow the Azure Firewall DNAT source.')
}
if ($bicepNetwork -notmatch "name:\s*'AllowSqlFromFirewallDnat'[\s\S]*?sourceAddressPrefix:\s*firewallPrivateIpAddress") {
    $failures.Add('Bicep SQL NSG does not allow the Azure Firewall DNAT source.')
}
if ($terraform -notmatch 'source_addresses\s*=\s*\[var\.deployer_address_prefix\]') {
    $failures.Add('Terraform DNAT does not use the deployer CIDR as its source.')
}
if ($terraform -notmatch 'name\s*=\s*"AllowHttpFromFirewallDnat"[\s\S]*?source_address_prefix\s*=\s*azurerm_firewall\.this\.ip_configuration\[0\]\.private_ip_address') {
    $failures.Add('Terraform web NSG does not allow the Azure Firewall DNAT source.')
}
if ($terraform -notmatch 'name\s*=\s*"AllowSqlFromFirewallDnat"[\s\S]*?source_address_prefix\s*=\s*azurerm_firewall\.this\.ip_configuration\[0\]\.private_ip_address') {
    $failures.Add('Terraform SQL NSG does not allow the Azure Firewall DNAT source.')
}
if ($bicepNetwork -match "targetFqdns:\s*\['\*'\]") {
    $failures.Add('Bicep permits unrestricted HTTPS egress.')
}
if ($bicepNetwork -notmatch 'ipConfigurations:\s*\[[\s\S]*?cfg-web01[\s\S]*?cfg-web02[\s\S]*?cfg-sql01') {
    $failures.Add('Bicep does not declare three role-specific firewall public IP configurations.')
}
$serializedSubnetDependencies = @(
    "identitySubnet[\s\S]*?dependsOn:\s*\[managementSubnet\]"
    "webSubnet[\s\S]*?dependsOn:\s*\[identitySubnet\]"
    "dataSubnet[\s\S]*?dependsOn:\s*\[webSubnet\]"
    "privateEndpointsSubnet[\s\S]*?dependsOn:\s*\[dataSubnet\]"
)
if ($serializedSubnetDependencies | Where-Object { $bicepNetwork -notmatch $_ }) {
    $failures.Add('Bicep subnet deployments are not serialized and may race on the shared VNet.')
}
if ($terraform -notmatch 'public_ip_configs\s*=\s*\["web01",\s*"web02",\s*"sql01"\]') {
    $failures.Add('Terraform does not declare exactly three role-specific firewall public IPs.')
}
if ($deploy -notmatch "SecurityControl\s*=\s*'Ignore'" -or $deploy -notmatch '--operation Delete') {
    $failures.Add('Lifecycle deployment does not apply and remove the temporary SecurityControl tag.')
}
if ($deploy -notmatch '--public-network-access Disabled' -or $deploy -notmatch '--default-action Deny') {
    $failures.Add('Lifecycle cleanup does not restore PaaS public access to disabled/default-deny.')
}
if ($test -notmatch 'unexpectedly has a public IP' -or $test -notmatch 'SecurityControl tag is still Ignore') {
    $failures.Add('Readiness validation does not check private VM NICs and policy-tag cleanup.')
}

if ($failures.Count) {
    throw ($failures -join [Environment]::NewLine)
}

Write-Host 'Public firewall scenario contract passed.'
