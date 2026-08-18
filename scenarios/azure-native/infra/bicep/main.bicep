  targetScope = 'resourceGroup'

@description('Lowercase prefix used for Azure resources and Windows computer names.')
@minLength(3)
@maxLength(10)
param namePrefix string = 'opmlab'

param location string = resourceGroup().location
@description('Stable within one lab lifetime and regenerated after teardown to avoid soft-deleted Key Vault name collisions.')
param deploymentId string = utcNow('yyyyMMddHHmmss')
param tags object = {
  workload: 'on-prem-modernization-lab'
  environment: 'lab'
}

param vnetAddressPrefix string = '10.50.0.0/16'
param bastionSubnetPrefix string = '10.50.0.0/26'
param managementSubnetPrefix string = '10.50.1.0/24'
param identitySubnetPrefix string = '10.50.2.0/24'
param webSubnetPrefix string = '10.50.3.0/24'
param dataSubnetPrefix string = '10.50.4.0/24'

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
param enableBastion bool = true

var suffix = toLower(uniqueString(subscription().subscriptionId, resourceGroup().id, namePrefix, deploymentId))
var names = {
  vnet: 'vnet-${namePrefix}'
  bastionPip: 'pip-${namePrefix}-bastion'
  natPip: 'pip-${namePrefix}-nat'
  nat: 'ng-${namePrefix}'
  bastion: 'bas-${namePrefix}'
  keyVault: take('kv-${namePrefix}-${suffix}', 24)
  storage: take(replace('st${namePrefix}${suffix}', '-', ''), 24)
}

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    tags: tags
    names: names
    prefixes: {
      vnet: vnetAddressPrefix
      bastion: bastionSubnetPrefix
      management: managementSubnetPrefix
      identity: identitySubnetPrefix
      web: webSubnetPrefix
      data: dataSubnetPrefix
    }
    domainControllerIp: '10.50.2.4'
    enableBastion: enableBastion
  }
}

module shared 'modules/shared.bicep' = {
  name: 'shared'
  params: {
    location: location
    tags: tags
    keyVaultName: names.keyVault
    storageAccountName: names.storage
    vnetId: network.outputs.vnetId
    privateEndpointSubnetId: network.outputs.managementSubnetId
  }
}

module dc 'modules/windows-vm.bicep' = {
  name: 'vm-dc01'
  params: {
    location: location
    tags: union(tags, { role: 'identity' })
    vmName: 'dc01'
    computerName: 'dc01'
    vmSize: vmSizeDc
    adminUsername: adminUsername
    adminPassword: adminPassword
    subnetId: network.outputs.identitySubnetId
    privateIpAddress: '10.50.2.4'
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
    tags: union(tags, { role: 'web' })
    vmName: 'web01'
    computerName: 'web01'
    vmSize: vmSizeWeb
    adminUsername: adminUsername
    adminPassword: adminPassword
    subnetId: network.outputs.webSubnetId
    privateIpAddress: '10.50.3.4'
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
    tags: union(tags, { role: 'web' })
    vmName: 'web02'
    computerName: 'web02'
    vmSize: vmSizeWeb
    adminUsername: adminUsername
    adminPassword: adminPassword
    subnetId: network.outputs.webSubnetId
    privateIpAddress: '10.50.3.5'
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
    tags: union(tags, { role: 'data' })
    vmName: 'sql01'
    computerName: 'sql01'
    vmSize: vmSizeSql
    adminUsername: adminUsername
    adminPassword: adminPassword
    subnetId: network.outputs.dataSubnetId
    privateIpAddress: '10.50.4.4'
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
    tags: union(tags, { role: 'discovery' })
    vmName: 'migrate01'
    computerName: 'migrate01'
    vmSize: vmSizeAppliance
    adminUsername: adminUsername
    adminPassword: adminPassword
    subnetId: network.outputs.managementSubnetId
    privateIpAddress: '10.50.1.4'
    imageReference: windowsImage
    enableTrustedLaunch: true
    osDiskSizeGb: 128
    autoShutdownTime: autoShutdownTime
    autoShutdownTimeZone: autoShutdownTimeZone
  }
}

output vnetId string = network.outputs.vnetId
output bastionId string = network.outputs.bastionId
output keyVaultName string = shared.outputs.keyVaultName
output stagingStorageAccountName string = shared.outputs.storageAccountName
output discoveryInventory array = [
  {
    fqdn: 'dc01.corp.contoso.local'
    ipAddress: '10.50.2.4'
    operatingSystem: 'Windows Server'
  }
  {
    fqdn: 'web01.corp.contoso.local'
    ipAddress: '10.50.3.4'
    operatingSystem: 'Windows Server'
  }
  {
    fqdn: 'web02.corp.contoso.local'
    ipAddress: '10.50.3.5'
    operatingSystem: 'Windows Server'
  }
  {
    fqdn: 'sql01.corp.contoso.local'
    ipAddress: '10.50.4.4'
    operatingSystem: 'Windows Server'
  }
]
output webUrls array = [
  'http://web01.corp.contoso.local'
  'http://web02.corp.contoso.local'
]
