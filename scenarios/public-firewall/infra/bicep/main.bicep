targetScope = 'resourceGroup'

@description('Lowercase prefix used for Azure resources and Windows computer names.')
@minLength(3)
@maxLength(10)
param namePrefix string = 'opmlab'

param location string = resourceGroup().location

@description('Stable within one lab lifetime and regenerated after teardown to avoid soft-deleted Key Vault name collisions.')
param deploymentId string = utcNow('yyyyMMddHHmmss')

@description('Base tags applied to all scenario resources.')
param tags object = {
  workload: 'on-prem-modernization-lab'
  environment: 'lab'
  scenario: 'public-firewall'
}

@description('Required deployer IPv4 CIDR. A /32 is expected and becomes the only public DNAT source.')
param deployerAddressPrefix string

@description('Applies the approved SecurityControl=Ignore tagging contract to scenario resources. Lifecycle automation is expected to tag the resource group separately when the exemption path is used.')
param enablePolicyExemption bool = false

param vnetAddressPrefix string = '10.50.0.0/16'
param firewallSubnetPrefix string = '10.50.0.0/26'
param managementSubnetPrefix string = '10.50.1.0/24'
param identitySubnetPrefix string = '10.50.2.0/24'
param webSubnetPrefix string = '10.50.3.0/24'
param dataSubnetPrefix string = '10.50.4.0/24'
param privateEndpointSubnetPrefix string = '10.50.5.0/27'

@secure()
param adminPassword string

param adminUsername string = 'labadmin'

param vmSizeDc string = 'Standard_B2ms'
param vmSizeWeb string = 'Standard_B2ms'
param vmSizeSql string = 'Standard_D4s_v5'

@description('Azure Migrate physical appliance currently requires 8 vCPU, 32 GB RAM, and 80 GB disk or greater.')
param vmSizeAppliance string = 'Standard_D8s_v5'

param windowsImage object = {
  publisher: 'MicrosoftWindowsServer'
  offer: 'WindowsServer'
  sku: '2022-datacenter-azure-edition'
  version: 'latest'
}

param sqlImage object = {
  publisher: 'MicrosoftSQLServer'
  offer: 'sql2016sp3-ws2019'
  sku: 'sqldev'
  version: 'latest'
}

param autoShutdownTime string = '1900'
param autoShutdownTimeZone string = 'UTC'

@description('Temporarily permits authenticated deployer and firewall-egress access to Key Vault and Storage. Lifecycle cleanup is expected to disable it in finally.')
param enableTemporaryDeploymentAccess bool = false

var scenario = 'public-firewall'
var deployerAddressCidr = contains(deployerAddressPrefix, ':')
  ? fail('deployerAddressPrefix must be an IPv4 CIDR, typically /32.')
  : parseCidr(deployerAddressPrefix)
var validatedDeployerAddressPrefix = '${deployerAddressCidr.network}/${deployerAddressCidr.cidr}'
var vmRoles = [
  'dc01'
  'web01'
  'web02'
  'sql01'
  'migrate01'
]
var privateAddresses = {
  dc01: '10.50.2.4'
  web01: '10.50.3.4'
  web02: '10.50.3.5'
  sql01: '10.50.4.4'
  migrate01: '10.50.1.4'
}
var mergedTags = union(tags, enablePolicyExemption ? { SecurityControl: 'Ignore' } : {})
var suffix = toLower(uniqueString(subscription().subscriptionId, resourceGroup().id, namePrefix, deploymentId))
var names = {
  vnet: 'vnet-${namePrefix}-pfw'
  firewall: 'afw-${namePrefix}'
  web01Pip: 'pip-${namePrefix}-web01'
  web02Pip: 'pip-${namePrefix}-web02'
  sqlPip: 'pip-${namePrefix}-sql01'
  keyVault: take('kv-${namePrefix}-${suffix}', 24)
  storage: take(replace('st${namePrefix}${suffix}', '-', ''), 24)
}

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    tags: mergedTags
    names: names
    prefixes: {
      vnet: vnetAddressPrefix
      firewall: firewallSubnetPrefix
      management: managementSubnetPrefix
      identity: identitySubnetPrefix
      web: webSubnetPrefix
      data: dataSubnetPrefix
      privateEndpoints: privateEndpointSubnetPrefix
    }
    deployerAddressPrefix: validatedDeployerAddressPrefix
    privateAddresses: privateAddresses
  }
}

module shared 'modules/shared.bicep' = {
  name: 'shared'
  params: {
    location: location
    tags: mergedTags
    keyVaultName: names.keyVault
    storageAccountName: names.storage
    vnetId: network.outputs.vnetId
    privateEndpointSubnetId: network.outputs.privateEndpointsSubnetId
    enableTemporaryDeploymentAccess: enableTemporaryDeploymentAccess
    deployerAddressPrefix: validatedDeployerAddressPrefix
    firewallEgressPublicIpAddresses: network.outputs.firewallEgressPublicIpAddresses
  }
}

module dc 'modules/windows-vm.bicep' = {
  name: 'vm-dc01'
  params: {
    location: location
    tags: union(mergedTags, { role: 'identity' })
    vmName: 'dc01'
    computerName: 'dc01'
    vmSize: vmSizeDc
    adminUsername: adminUsername
    adminPassword: adminPassword
    subnetId: network.outputs.identitySubnetId
    privateIpAddress: privateAddresses.dc01
    imageReference: windowsImage
    enableTrustedLaunch: true
    autoShutdownTime: autoShutdownTime
    autoShutdownTimeZone: autoShutdownTimeZone
  }
}

module web01 'modules/windows-vm.bicep' = {
  name: 'vm-web01'
  params: {
    location: location
    tags: union(mergedTags, { role: 'web' })
    vmName: 'web01'
    computerName: 'web01'
    vmSize: vmSizeWeb
    adminUsername: adminUsername
    adminPassword: adminPassword
    subnetId: network.outputs.webSubnetId
    privateIpAddress: privateAddresses.web01
    imageReference: windowsImage
    enableTrustedLaunch: true
    autoShutdownTime: autoShutdownTime
    autoShutdownTimeZone: autoShutdownTimeZone
  }
}

module web02 'modules/windows-vm.bicep' = {
  name: 'vm-web02'
  params: {
    location: location
    tags: union(mergedTags, { role: 'web' })
    vmName: 'web02'
    computerName: 'web02'
    vmSize: vmSizeWeb
    adminUsername: adminUsername
    adminPassword: adminPassword
    subnetId: network.outputs.webSubnetId
    privateIpAddress: privateAddresses.web02
    imageReference: windowsImage
    enableTrustedLaunch: true
    autoShutdownTime: autoShutdownTime
    autoShutdownTimeZone: autoShutdownTimeZone
  }
}

module sql01 'modules/windows-vm.bicep' = {
  name: 'vm-sql01'
  params: {
    location: location
    tags: union(mergedTags, { role: 'data' })
    vmName: 'sql01'
    computerName: 'sql01'
    vmSize: vmSizeSql
    adminUsername: adminUsername
    adminPassword: adminPassword
    subnetId: network.outputs.dataSubnetId
    privateIpAddress: privateAddresses.sql01
    imageReference: sqlImage
    enableTrustedLaunch: false
    osDiskSizeGb: 128
    dataDiskSizeGb: 128
    autoShutdownTime: autoShutdownTime
    autoShutdownTimeZone: autoShutdownTimeZone
  }
}

module appliance 'modules/windows-vm.bicep' = {
  name: 'vm-migrate01'
  params: {
    location: location
    tags: union(mergedTags, { role: 'discovery' })
    vmName: 'migrate01'
    computerName: 'migrate01'
    vmSize: vmSizeAppliance
    adminUsername: adminUsername
    adminPassword: adminPassword
    subnetId: network.outputs.managementSubnetId
    privateIpAddress: privateAddresses.migrate01
    imageReference: windowsImage
    enableTrustedLaunch: true
    osDiskSizeGb: 128
    autoShutdownTime: autoShutdownTime
    autoShutdownTimeZone: autoShutdownTimeZone
  }
}

output scenario string = scenario
output azureVmRoles array = vmRoles
output vmRoles array = vmRoles
output subnets array = network.outputs.subnetNames
output deployerAddressPrefix string = validatedDeployerAddressPrefix
output vnetId string = network.outputs.vnetId
output firewall object = {
  id: network.outputs.firewallId
  name: names.firewall
  tier: 'Standard'
  privateIpAddress: network.outputs.firewallPrivateIpAddress
  publicIpAddresses: network.outputs.firewallPublicIpAddresses
  egressPublicIpAddresses: network.outputs.firewallEgressPublicIpAddresses
}
output keyVaultName string = shared.outputs.keyVaultName
output keyVaultUri string = shared.outputs.keyVaultUri
output stagingStorageAccountName string = shared.outputs.storageAccountName
output stagingStorageBlobEndpoint string = shared.outputs.storageBlobEndpoint
output publicEndpoints object = {
  web01: {
    protocol: 'http'
    address: network.outputs.firewallPublicIpAddresses.web01
    port: 80
    url: 'http://${network.outputs.firewallPublicIpAddresses.web01}'
    sourceAddressPrefix: validatedDeployerAddressPrefix
    translatedAddress: privateAddresses.web01
    translatedPort: 80
  }
  web02: {
    protocol: 'http'
    address: network.outputs.firewallPublicIpAddresses.web02
    port: 80
    url: 'http://${network.outputs.firewallPublicIpAddresses.web02}'
    sourceAddressPrefix: validatedDeployerAddressPrefix
    translatedAddress: privateAddresses.web02
    translatedPort: 80
  }
  sql01: {
    protocol: 'tcp'
    address: network.outputs.firewallPublicIpAddresses.sql01
    port: 1633
    sourceAddressPrefix: validatedDeployerAddressPrefix
    translatedAddress: privateAddresses.sql01
    translatedPort: 1433
  }
}
output publicEndpointUrls array = [
  'http://${network.outputs.firewallPublicIpAddresses.web01}'
  'http://${network.outputs.firewallPublicIpAddresses.web02}'
]
output privateInventory array = [
  {
    role: 'dc01'
    fqdn: 'dc01.corp.contoso.local'
    ipAddress: privateAddresses.dc01
    subnet: 'identity'
    operatingSystem: 'Windows Server'
    intent: 'Active Directory Domain Services, DNS, AD CS, and synthetic workload origin'
  }
  {
    role: 'web01'
    fqdn: 'web01.corp.contoso.local'
    ipAddress: privateAddresses.web01
    subnet: 'web'
    operatingSystem: 'Windows Server'
    intent: 'Independent IIS application server behind Azure Firewall DNAT'
  }
  {
    role: 'web02'
    fqdn: 'web02.corp.contoso.local'
    ipAddress: privateAddresses.web02
    subnet: 'web'
    operatingSystem: 'Windows Server'
    intent: 'Independent IIS application server behind Azure Firewall DNAT'
  }
  {
    role: 'sql01'
    fqdn: 'sql01.corp.contoso.local'
    ipAddress: privateAddresses.sql01
    subnet: 'data'
    operatingSystem: 'SQL Server 2016 SP3 Developer on Windows Server'
    intent: 'Shared SQL backend exposed only through private access and restricted Firewall DNAT'
  }
  {
    role: 'migrate01'
    fqdn: 'migrate01.corp.contoso.local'
    ipAddress: privateAddresses.migrate01
    subnet: 'management'
    operatingSystem: 'Windows Server'
    intent: 'Azure Migrate physical appliance and management node'
  }
]
output temporaryDeploymentAccess object = {
  enabled: enableTemporaryDeploymentAccess
  allowedPublicSources: shared.outputs.allowedPublicSources
  keyVaultPublicNetworkAccess: enableTemporaryDeploymentAccess ? 'Enabled' : 'Disabled'
  storagePublicNetworkAccess: enableTemporaryDeploymentAccess ? 'Enabled' : 'Disabled'
}
