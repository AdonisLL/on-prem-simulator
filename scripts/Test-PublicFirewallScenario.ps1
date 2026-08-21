[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$scenarioRoot = Join-Path $root 'scenarios\public-firewall'
$bicep = Get-Content (Join-Path $scenarioRoot 'infra\bicep\main.bicep') -Raw
$bicepNetwork = Get-Content (Join-Path $scenarioRoot 'infra\bicep\modules\network.bicep') -Raw
$bicepShared = Get-Content (Join-Path $scenarioRoot 'infra\bicep\modules\shared.bicep') -Raw
$terraform = Get-Content (Join-Path $scenarioRoot 'infra\terraform\main.tf') -Raw
$deploy = Get-Content (Join-Path $scenarioRoot 'scripts\Deploy-Lab.ps1') -Raw
$initialize = Get-Content (Join-Path $scenarioRoot 'scripts\Initialize-Lab.ps1') -Raw
$test = Get-Content (Join-Path $scenarioRoot 'scripts\Test-Lab.ps1') -Raw
$common = Get-Content (Join-Path $scenarioRoot 'scripts\Lab.Common.psm1') -Raw
$rootDeployCommand = Get-Command (Join-Path $root 'scripts\Deploy-Lab.ps1')
$scenarioDeployCommand = Get-Command (Join-Path $scenarioRoot 'scripts\Deploy-Lab.ps1')
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

if ($bicepNetwork -notmatch 'sourceAddresses:\s*deployerAddressPrefixes') {
    $failures.Add('Bicep DNAT does not use the explicit deployer CIDRs as its source.')
}
if ($bicepNetwork -notmatch "name:\s*'AllowHttpFromFirewallDnat'[\s\S]*?sourceAddressPrefix:\s*prefixes\.firewall") {
    $failures.Add('Bicep web NSG does not allow Azure Firewall backend instance addresses.')
}
if ($bicepNetwork -notmatch "name:\s*'AllowSqlFromFirewallDnat'[\s\S]*?sourceAddressPrefix:\s*prefixes\.firewall") {
    $failures.Add('Bicep SQL NSG does not allow Azure Firewall backend instance addresses.')
}
if ($terraform -notmatch 'source_addresses\s*=\s*local\.deployer_address_prefixes') {
    $failures.Add('Terraform DNAT does not use the explicit deployer CIDRs as its source.')
}
if ($terraform -notmatch 'name\s*=\s*"AllowHttpFromFirewallDnat"[\s\S]*?source_address_prefix\s*=\s*var\.address_prefixes\.firewall') {
    $failures.Add('Terraform web NSG does not allow Azure Firewall backend instance addresses.')
}
if ($terraform -notmatch 'name\s*=\s*"AllowSqlFromFirewallDnat"[\s\S]*?source_address_prefix\s*=\s*var\.address_prefixes\.firewall') {
    $failures.Add('Terraform SQL NSG does not allow Azure Firewall backend instance addresses.')
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
if ($bicepShared -notmatch "storageAllowedPublicSources\s*=\s*\[for source in allowedPublicSources:\s*endsWith\(source,\s*'/32'\)\s*\?\s*split\(source,\s*'/'\)\[0\]\s*:\s*source\]" -or
    $bicepShared -notmatch 'ipRules:\s*\[for source in storageAllowedPublicSources:') {
    $failures.Add('Bicep Storage rules do not normalize unsupported single-host /32 CIDRs.')
}
if ($common -notmatch 'networkRuleSet\.ipRules\[\]\.ipAddressOrRange') {
    $failures.Add('Storage network-rule validation does not read the Azure CLI ipAddressOrRange property.')
}
if ([regex]::Matches($common, '(?m)^\s*& \$msbuildPath[\s\S]*?/nologo \| Out-Host').Count -ne 2) {
    $failures.Add('Artifact builds leak MSBuild output into the Build-LabArtifacts return value.')
}
if ($common -notmatch "packageRoot 'bin\\Microsoft\.Web\.Infrastructure\.dll'") {
    $failures.Add('Artifact validation does not require the MVC runtime dependency.')
}
if ($common -notmatch "ComponentStatus/StdErr/\*" -or
    $common -notmatch 'Guest configuration role \$Role failed on \$VmName') {
    $failures.Add('Azure Run Command guest errors are not promoted to deployment failures.')
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
if (-not $rootDeployCommand.Parameters.ContainsKey('AllowUnrestrictedTemporaryDeploymentAccess') -or
    -not $scenarioDeployCommand.Parameters.ContainsKey('AllowUnrestrictedTemporaryDeploymentAccess')) {
    $failures.Add('Deployment commands do not expose the explicit unrestricted bootstrap fallback.')
}
if (-not $rootDeployCommand.Parameters.ContainsKey('AdditionalDeployerAddressPrefix') -or
    -not $scenarioDeployCommand.Parameters.ContainsKey('AdditionalDeployerAddressPrefix') -or
    $bicep -notmatch 'param additionalDeployerAddressPrefixes array' -or
    $terraformVariables -notmatch 'variable "additional_deployer_address_prefixes"') {
    $failures.Add('Deployment surfaces do not consistently expose additional explicit deployer CIDRs.')
}
if ($deploy -notmatch 'AllowUnrestrictedTemporaryDeploymentAccess requires UseTemporaryPolicyExemption') {
    $failures.Add('Unrestricted bootstrap access is not guarded by the required Azure Policy exemption.')
}
if ($deploy -notmatch '\$isNetworkRuleRejection[\s\S]*?blocked by network rules[\s\S]*?ForbiddenByFirewall[\s\S]*?client address is not authorized' -or
    $deploy -notmatch '\(& \$isNetworkRuleRejection \$uploadError\)[\s\S]*?\$enableUnrestrictedStorageAccess') {
    $failures.Add('Storage upload does not restrict automatic fallback to confirmed network-rule rejection.')
}
if ($deploy -notmatch '\$attempt -ge 10[\s\S]*?AuthorizationFailure[\s\S]*?\$ambiguousAuthorizationFailure') {
    $failures.Add('Ambiguous Storage authorization failures do not receive bounded RBAC retries before fallback.')
}
if ($deploy -notmatch '\$setKeyVaultSecrets[\s\S]*?catch \{[\s\S]*?\$isNetworkRuleRejection[\s\S]*?\$enableUnrestrictedKeyVaultAccess') {
    $failures.Add('Key Vault does not independently restrict automatic fallback to confirmed network-rule rejection.')
}
$boundedUnrestrictedAccessPatterns = @(
    '\$storageAccessWidened[\s\S]*?try \{[\s\S]*?az storage account update[\s\S]*?--default-action Allow[\s\S]*?finally \{[\s\S]*?--default-action Deny'
    '\$keyVaultAccessWidened[\s\S]*?try \{[\s\S]*?az keyvault update[\s\S]*?--default-action Allow[\s\S]*?finally \{[\s\S]*?--default-action Deny'
)
if ($boundedUnrestrictedAccessPatterns | Where-Object { $deploy -notmatch $_ }) {
    $failures.Add('Unrestricted bootstrap access is not bounded by immediate default-deny cleanup.')
}
if ([regex]::Matches($initialize, 'Restart-LabVm').Count -ne 2 -or
    $common -notmatch 'function Restart-LabVm[\s\S]*?for \(\$attempt = 1; \$attempt -le 3; \$attempt\+\+\)[\s\S]*?az vm restart[\s\S]*?--output none') {
    $failures.Add('Guest restart operations do not retry transient ARM failures and suppress success payloads.')
}
if ($test -notmatch 'unexpectedly has a public IP' -or $test -notmatch 'SecurityControl tag is still Ignore') {
    $failures.Add('Readiness validation does not check private VM NICs and policy-tag cleanup.')
}

if ($failures.Count) {
    throw ($failures -join [Environment]::NewLine)
}

Write-Host 'Public firewall scenario contract passed.'
