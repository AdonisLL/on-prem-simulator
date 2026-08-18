param location string
param tags object
param names object
param prefixes object
param domainControllerIp string
param enableBastion bool

resource natPip 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
  name: names.natPip
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource nat 'Microsoft.Network/natGateways@2024-07-01' = {
  name: names.nat
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: {
    idleTimeoutInMinutes: 10
    publicIpAddresses: [
      { id: natPip.id }
    ]
  }
}

resource managementNsg 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: 'nsg-management'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowRdpFromBastion'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: prefixes.bastion
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
      {
        name: 'DenyUnlistedVnetInbound'
        properties: {
          priority: 4096
          access: 'Deny'
          direction: 'Inbound'
          protocol: '*'
          sourceAddressPrefix: prefixes.vnet
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource identityNsg 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: 'nsg-identity'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowRdpFromBastion'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: prefixes.bastion
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
      {
        name: 'AllowWinRmFromManagement'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefixes: [
            prefixes.management
            prefixes.identity
          ]
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5986'
        }
      }
      {
        name: 'AllowDomainServices'
        properties: {
          priority: 120
          access: 'Allow'
          direction: 'Inbound'
          protocol: '*'
          sourceAddressPrefix: prefixes.vnet
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '53'
            '88'
            '123'
            '135'
            '389'
            '445'
            '464'
            '636'
            '3268-3269'
            '49152-65535'
          ]
        }
      }
      {
        name: 'DenyUnlistedVnetInbound'
        properties: {
          priority: 4096
          access: 'Deny'
          direction: 'Inbound'
          protocol: '*'
          sourceAddressPrefix: prefixes.vnet
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource webNsg 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: 'nsg-web'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowRdpFromBastion'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: prefixes.bastion
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
      {
        name: 'AllowWinRmFromManagement'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefixes: [
            prefixes.management
            prefixes.identity
          ]
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5986'
        }
      }
      {
        name: 'AllowHttpFromIdentity'
        properties: {
          priority: 120
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: prefixes.identity
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRanges: [
            '80'
            '443'
          ]
        }
      }
      {
        name: 'DenyUnlistedVnetInbound'
        properties: {
          priority: 4096
          access: 'Deny'
          direction: 'Inbound'
          protocol: '*'
          sourceAddressPrefix: prefixes.vnet
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource dataNsg 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: 'nsg-data'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowRdpFromBastion'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: prefixes.bastion
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
      {
        name: 'AllowWinRmFromManagement'
        properties: {
          priority: 110
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefixes: [
            prefixes.management
            prefixes.identity
          ]
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5986'
        }
      }
      {
        name: 'AllowSqlFromWebAndManagement'
        properties: {
          priority: 120
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefixes: [
            prefixes.web
            prefixes.management
          ]
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '1433'
        }
      }
      {
        name: 'DenyUnlistedVnetInbound'
        properties: {
          priority: 4096
          access: 'Deny'
          direction: 'Inbound'
          protocol: '*'
          sourceAddressPrefix: prefixes.vnet
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: names.vnet
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [prefixes.vnet] }
    dhcpOptions: { dnsServers: [domainControllerIp] }
    subnets: [
      {
        name: 'AzureBastionSubnet'
        properties: { addressPrefix: prefixes.bastion }
      }
      {
        name: 'snet-management'
        properties: {
          addressPrefix: prefixes.management
          networkSecurityGroup: { id: managementNsg.id }
          natGateway: { id: nat.id }
          defaultOutboundAccess: false
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-identity'
        properties: {
          addressPrefix: prefixes.identity
          networkSecurityGroup: { id: identityNsg.id }
          natGateway: { id: nat.id }
          defaultOutboundAccess: false
        }
      }
      {
        name: 'snet-web'
        properties: {
          addressPrefix: prefixes.web
          networkSecurityGroup: { id: webNsg.id }
          natGateway: { id: nat.id }
          defaultOutboundAccess: false
        }
      }
      {
        name: 'snet-data'
        properties: {
          addressPrefix: prefixes.data
          networkSecurityGroup: { id: dataNsg.id }
          natGateway: { id: nat.id }
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

resource bastionPip 'Microsoft.Network/publicIPAddresses@2024-07-01' = if (enableBastion) {
  name: names.bastionPip
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-07-01' = if (enableBastion) {
  name: names.bastion
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: {
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          subnet: { id: resourceId('Microsoft.Network/virtualNetworks/subnets', names.vnet, 'AzureBastionSubnet') }
          publicIPAddress: { id: bastionPip.id }
        }
      }
    ]
  }
  dependsOn: [vnet]
}

output vnetId string = vnet.id
output managementSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', names.vnet, 'snet-management')
output identitySubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', names.vnet, 'snet-identity')
output webSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', names.vnet, 'snet-web')
output dataSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', names.vnet, 'snet-data')
output bastionId string = enableBastion ? bastion.id : ''
