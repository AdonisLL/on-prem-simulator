targetScope = 'resourceGroup'

param location string = resourceGroup().location
param namePrefix string = 'opmlab'
param adminUsername string = 'labadmin'

@secure()
param adminPassword string

param hostVmSize string = 'Standard_D32s_v5'
param hostImage object = {
  publisher: 'MicrosoftWindowsServer'
  offer: 'WindowsServer'
  sku: '2022-datacenter-azure-edition'
  version: 'latest'
}
param hostDataDiskSizeGb int = 1024
param hostSubnetName string = 'snet-hyperv-host'
param hostSubnetPrefix string = '10.240.0.0/24'
param hostPrivateAddress string = '10.240.0.10'
param autoShutdownTime string = '1900'
param autoShutdownTimeZone string = 'UTC'
param tags object = {}

var scenario = 'nested-virtualization'
var azureVmRoles = ['hyperv01']
var hostVmName = '${namePrefix}-hyperv01'
var mergedTags = union(tags, {
  scenario: scenario
  workload: 'on-prem-modernization-lab'
})

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${namePrefix}-nested-vnet'
  location: location
  tags: mergedTags
  properties: {
    addressSpace: {
      addressPrefixes: ['10.240.0.0/16']
    }
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${hostVmName}-nsg'
  location: location
  tags: mergedTags
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: hostSubnetName
  properties: {
    addressPrefix: hostSubnetPrefix
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: '${hostVmName}-nic'
  location: location
  tags: mergedTags
  properties: {
    ipConfigurations: [
      {
        name: 'primary'
        properties: {
          privateIPAddress: hostPrivateAddress
          privateIPAllocationMethod: 'Static'
          subnet: {
            id: subnet.id
          }
        }
      }
    ]
  }
}

resource host 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: hostVmName
  location: location
  tags: mergedTags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: hostVmSize
    }
    osProfile: {
      computerName: 'hyperv01'
      adminUsername: adminUsername
      adminPassword: adminPassword
      windowsConfiguration: {
        enableAutomaticUpdates: true
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: hostImage
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
      dataDisks: [
        {
          lun: 0
          createOption: 'Empty'
          diskSizeGB: hostDataDiskSizeGb
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
        }
      ]
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

resource shutdown 'Microsoft.DevTestLab/schedules@2018-09-15' = {
  name: 'shutdown-computevm-${host.name}'
  location: location
  tags: mergedTags
  properties: {
    status: 'Enabled'
    taskType: 'ComputeVmShutdownTask'
    dailyRecurrence: {
      time: autoShutdownTime
    }
    timeZoneId: autoShutdownTimeZone
    targetResourceId: host.id
    notificationSettings: {
      status: 'Disabled'
    }
  }
}

output scenario string = scenario
output azureVmRoles array = azureVmRoles
output subnets array = [hostSubnetName]
output hostVmName string = host.name
output hostPrivateAddress string = hostPrivateAddress
