param location string
param tags object
param names object
param prefixes object
param deployerAddressPrefix string
param privateAddresses object

resource web01PublicIp 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
  name: names.web01Pip
  location: location
  tags: union(tags, {
    role: 'public-endpoint'
    target: 'web01'
  })
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource web02PublicIp 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
  name: names.web02Pip
  location: location
  tags: union(tags, {
    role: 'public-endpoint'
    target: 'web02'
  })
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource sqlPublicIp 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
  name: names.sqlPip
  location: location
  tags: union(tags, {
    role: 'public-endpoint'
    target: 'sql01'
  })
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: names.vnet
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [prefixes.vnet]
    }
    dhcpOptions: {
      dnsServers: [privateAddresses.dc01]
    }
  }
}

resource firewallSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  parent: vnet
  name: 'AzureFirewallSubnet'
  properties: {
    addressPrefix: prefixes.firewall
  }
}

resource firewall 'Microsoft.Network/azureFirewalls@2024-07-01' = {
  name: names.firewall
  location: location
  tags: union(tags, { role: 'firewall' })
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    threatIntelMode: 'Deny'
    ipConfigurations: [
      {
        name: 'cfg-web01'
        properties: {
          subnet: {
            id: firewallSubnet.id
          }
          publicIPAddress: {
            id: web01PublicIp.id
          }
        }
      }
      {
        name: 'cfg-web02'
        properties: {
          publicIPAddress: {
            id: web02PublicIp.id
          }
        }
      }
      {
        name: 'cfg-sql01'
        properties: {
          publicIPAddress: {
            id: sqlPublicIp.id
          }
        }
      }
    ]
    natRuleCollections: [
      {
        name: 'ingress'
        properties: {
          priority: 100
          action: {
            type: 'Dnat'
          }
          rules: [
            {
              name: 'web01-http'
              description: 'Restrict public HTTP to web01 to the explicit deployer CIDR.'
              sourceAddresses: [deployerAddressPrefix]
              destinationAddresses: [web01PublicIp.properties.ipAddress]
              destinationPorts: ['80']
              translatedAddress: privateAddresses.web01
              translatedPort: '80'
              protocols: ['TCP']
            }
            {
              name: 'web02-http'
              description: 'Restrict public HTTP to web02 to the explicit deployer CIDR.'
              sourceAddresses: [deployerAddressPrefix]
              destinationAddresses: [web02PublicIp.properties.ipAddress]
              destinationPorts: ['80']
              translatedAddress: privateAddresses.web02
              translatedPort: '80'
              protocols: ['TCP']
            }
            {
              name: 'sql01-tcp'
              description: 'Restrict public SQL access to sql01 to the explicit deployer CIDR.'
              sourceAddresses: [deployerAddressPrefix]
              destinationAddresses: [sqlPublicIp.properties.ipAddress]
              destinationPorts: ['1633']
              translatedAddress: privateAddresses.sql01
              translatedPort: '1433'
              protocols: ['TCP']
            }
          ]
        }
      }
    ]
    applicationRuleCollections: [
      {
        name: 'egress-https'
        properties: {
          priority: 200
          action: {
            type: 'Allow'
          }
          rules: [
            {
              name: 'allow-workload-https'
              description: 'Permit controlled outbound HTTPS for workload and appliance subnets.'
              sourceAddresses: [
                prefixes.management
                prefixes.identity
                prefixes.web
                prefixes.data
              ]
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              targetFqdns: [
                'aka.ms'
                'go.microsoft.com'
                'download.microsoft.com'
                'packages.microsoft.com'
                'management.azure.com'
                'login.microsoftonline.com'
                'login.windows.net'
                '*.microsoft.com'
                '*.microsoftonline.com'
                '*.windowsupdate.com'
                '*.update.microsoft.com'
                '*.delivery.mp.microsoft.com'
                '*.do.dsp.mp.microsoft.com'
                '*.blob.core.windows.net'
                '*.vault.azure.net'
                '*.vaultcore.azure.net'
                'dc.services.visualstudio.com'
              ]
            }
            {
              name: 'allow-azure-migrate'
              description: 'Permit Azure Migrate appliance service dependencies.'
              sourceAddresses: [prefixes.management]
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              targetFqdns: [
                '*.servicebus.windows.net'
                '*.azurewebsites.net'
                '*.migration.windowsazure.com'
                '*.sitecatalyst.omniture.com'
              ]
            }
          ]
        }
      }
    ]
  }
}

var firewallPrivateIpAddress = firewall.properties.ipConfigurations[0].properties.privateIPAddress

resource managementRouteTable 'Microsoft.Network/routeTables@2024-07-01' = {
  name: 'rt-management-via-firewall'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'default-via-firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIpAddress
        }
      }
    ]
  }
}

resource identityRouteTable 'Microsoft.Network/routeTables@2024-07-01' = {
  name: 'rt-identity-via-firewall'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'default-via-firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIpAddress
        }
      }
    ]
  }
}

resource webRouteTable 'Microsoft.Network/routeTables@2024-07-01' = {
  name: 'rt-web-via-firewall'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'default-via-firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIpAddress
        }
      }
    ]
  }
}

resource dataRouteTable 'Microsoft.Network/routeTables@2024-07-01' = {
  name: 'rt-data-via-firewall'
  location: location
  tags: tags
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'default-via-firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIpAddress
        }
      }
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
        name: 'AllowWinRmFromIdentityAndManagement'
        properties: {
          priority: 100
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
        name: 'AllowWinRmFromIdentityAndManagement'
        properties: {
          priority: 100
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
          priority: 110
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
        name: 'AllowHttpFromFirewallDnat'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: firewallPrivateIpAddress
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
      {
        name: 'AllowHttpFromIdentity'
        properties: {
          priority: 110
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
        name: 'AllowWinRmFromIdentityAndManagement'
        properties: {
          priority: 120
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
    // Azure Firewall DNAT SNATs inbound sessions to the firewall private IP, so
    // the workload NSG must trust the firewall source rather than the external client.
    securityRules: [
      {
        name: 'AllowSqlFromFirewallDnat'
        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: firewallPrivateIpAddress
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '1433'
        }
      }
      {
        name: 'AllowSqlFromWebAndManagement'
        properties: {
          priority: 110
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
        name: 'AllowWinRmFromIdentityAndManagement'
        properties: {
          priority: 120
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

resource managementSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  parent: vnet
  name: 'management'
  properties: {
    addressPrefix: prefixes.management
    networkSecurityGroup: {
      id: managementNsg.id
    }
    routeTable: {
      id: managementRouteTable.id
    }
    defaultOutboundAccess: false
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

resource identitySubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  parent: vnet
  name: 'identity'
  properties: {
    addressPrefix: prefixes.identity
    networkSecurityGroup: {
      id: identityNsg.id
    }
    routeTable: {
      id: identityRouteTable.id
    }
    defaultOutboundAccess: false
  }
}

resource webSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  parent: vnet
  name: 'web'
  properties: {
    addressPrefix: prefixes.web
    networkSecurityGroup: {
      id: webNsg.id
    }
    routeTable: {
      id: webRouteTable.id
    }
    defaultOutboundAccess: false
  }
}

resource dataSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  parent: vnet
  name: 'data'
  properties: {
    addressPrefix: prefixes.data
    networkSecurityGroup: {
      id: dataNsg.id
    }
    routeTable: {
      id: dataRouteTable.id
    }
    defaultOutboundAccess: false
  }
}

resource privateEndpointsSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  parent: vnet
  name: 'private-endpoints'
  properties: {
    addressPrefix: prefixes.privateEndpoints
    defaultOutboundAccess: false
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

output vnetId string = vnet.id
output firewallId string = firewall.id
output firewallPrivateIpAddress string = firewallPrivateIpAddress
output managementSubnetId string = managementSubnet.id
output identitySubnetId string = identitySubnet.id
output webSubnetId string = webSubnet.id
output dataSubnetId string = dataSubnet.id
output privateEndpointsSubnetId string = privateEndpointsSubnet.id
output subnetNames array = [
  firewallSubnet.name
  managementSubnet.name
  identitySubnet.name
  webSubnet.name
  dataSubnet.name
  privateEndpointsSubnet.name
]
output firewallPublicIpAddresses object = {
  web01: web01PublicIp.properties.ipAddress
  web02: web02PublicIp.properties.ipAddress
  sql01: sqlPublicIp.properties.ipAddress
}
output firewallEgressPublicIpAddresses array = [
  web01PublicIp.properties.ipAddress
  web02PublicIp.properties.ipAddress
  sqlPublicIp.properties.ipAddress
]
