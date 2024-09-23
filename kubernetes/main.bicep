// Parameters

param dnsPrefix string = 'ClusterDnsprefix'
@minValue(0)
@maxValue(1023)
param osDiskSizeGB int = 0
@minValue(1)
@maxValue(50)
param agentCount int = 3
param agentVMSize string = 'standard_d2s_v3'
param linuxAdminUsername string = 'GT-test'
param location string = resourceGroup().location
param clusterName string = 'GT-AKSCluster'
param appGatewayPublicIpName string = 'GT-AppGatewayPublicIP'
param vnetName string = 'GT-VNet'
param vnetAddressPrefix string = '192.168.0.0/16'
param aksSubnetName string = 'GT-aksSubnet'
param aksSubnetPrefix string = '192.168.1.0/24'
param wafSubnetName string = 'wafSubnet'
param wafSubnetPrefix string = '192.168.2.0/26'
param keyVaultName string = 'GTkeyvault673645'
param acrName string = 'GTAzureContainerRegistry'

// New parameters for Key Vault Private Link
param keyVaultPrivateEndpointName string = 'GT-KeyVaultPrivateEndpoint'
param keyVaultPrivateDnsZoneName string = 'privatelink.vaultcore.azure.net'

// Updated CIDR ranges for AKS
param podCidr string = '10.244.0.0/16'
param serviceCidr string = '10.0.0.0/16'  // Changed to avoid overlap
param dnsServiceIP string = '10.0.0.10' 
// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
  }
}

// AKS Subnet
resource aksSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: aksSubnetName
  properties: {
    addressPrefix: aksSubnetPrefix
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

// WAF Subnet
resource wafSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: wafSubnetName
  properties: {
    addressPrefix: wafSubnetPrefix
  }
}

//public-ip
resource appGatewayPublicIP 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: appGatewayPublicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// AKS Cluster
resource aks 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: dnsPrefix
    networkProfile: {
      networkPlugin: 'kubenet'
      podCidr: podCidr
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIP
    }
    agentPoolProfiles: [
      {
        name: 'agentpool'
        osDiskSizeGB: osDiskSizeGB
        count: agentCount
        vmSize: agentVMSize
        osType: 'Linux'
        mode: 'System'
        vnetSubnetID:  aksSubnet.id
      }
    ]
    linuxProfile: {
      adminUsername: linuxAdminUsername
      ssh: {
        publicKeys: [
          {
            keyData: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDCKEV7ViBbOnZyuYWZAXdCFEISzQWTYqJrQgYbPTvFx5SseWtNwMMJ7LUnrKFmuzrt6X9obmmqOpCdNBCqz0+Imxhm9A+mY3bBkGYZBtbvm0H533IoEQRBDOnVjsh0TraLav4HdIE6jVIri3mBVleRUG5NB05rcXJMuYVetWOOGGeIJplG/zl5a/+V0LS3E+cJ+GeuX9tq1m5QbllX6u0aNqCnsH4ec5jHBa/xJ1/rGTigcwEAsxZ1i0UBPm0wG5sH1Hxbk1iDHy6blU8lcNVvLUikOOo3Y7Rf1GuJLiUzTVTjiTOffIOKSkkjD+1v27FH5KaUqD7mnis1jwAMnbzv olukorede fawemimo@Anommynous'
          }
        ]
      }
    }
  }
}

// Application Gateway (WAF)
resource myAppGateway 'Microsoft.Network/applicationGateways@2024-01-01' = {
  name: 'GTAppgateway'
  location: location
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: 2
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: wafSubnet.id
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: appGatewayPublicIP.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'myBackendPool'
        properties: {
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'myHTTPSetting'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: false
          requestTimeout: 20
        }
      }
    ]
    httpListeners: [
      {
        name: 'myListener'
        properties: {
          firewallPolicy: {
            id: Webappfirewallpolicy.id
          }
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', 'GTAppgateway', 'appGwPublicFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', 'GTAppgateway', 'port_80')
          }
          protocol: 'Http'
          requireServerNameIndication: false
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'myRoutingRule'
        properties: {
          ruleType: 'Basic'
          priority: 10
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', 'GTAppgateway', 'myListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', 'GTAppgateway', 'myBackendPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', 'GTAppgateway', 'myHTTPSetting')
          }
        }
      }
    ]
    enableHttp2: false
    firewallPolicy: {
      id: Webappfirewallpolicy.id
    }
  }
  dependsOn: [
  ]
}

resource Webappfirewallpolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2024-01-01' = {
  name: 'GT-webFirewall'
  location: location
  properties: {
    customRules: [
      {
        name: 'CustRule01'
        priority: 100
        ruleType: 'MatchRule'
        action: 'Block'
        matchConditions: [
          {
            matchVariables: [
              {
                variableName: 'RemoteAddr'
              }
            ]
            operator: 'IPMatch'
            negationConditon: true
            matchValues: [
              '10.10.10.0/24'
            ]
          }
        ]
      }
    ]
    policySettings: {
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
      state: 'Enabled'
      mode: 'Prevention'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.1'
        }
      ]
    }
  }
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
  name: keyVaultName
  location: location
  properties: {
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: aks.identity.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Disabled'
  }
}

// Grant AKS pull access to ACR
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aks.id, acr.id, 'acrpull')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: aks.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
  scope: keyVault
}

// Private DNS Zone for ACR
resource acrPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'GT-privatelink.azurecr.io'
  location: 'global'
}

// Private Endpoint for ACR
resource acrPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: '${acrName}-endpoint'
  location: location
  properties: {
    subnet: {
      id: aksSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${acrName}-connection'
        properties: {
          privateLinkServiceId: acr.id
          groupIds: [
            'registry'
          ]
        }
      }
    ]
  }
}

// Private DNS Zone Group for ACR
resource acrPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: acrPrivateEndpoint
  name: 'GT-acrPrivateDnsZoneGroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: acrPrivateDnsZone.id
        }
      }
    ]
  }
}

// Key Vault Private DNS Zone
resource keyVaultPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: keyVaultPrivateDnsZoneName
  location: 'global'
}

// Key Vault Private Endpoint
resource keyVaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-01-01' = {
  name: keyVaultPrivateEndpointName
  location: location
  properties: {
    subnet: {
      id: aksSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: '${keyVaultName}-connection'
        properties: {
          privateLinkServiceId: keyVault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

// Key Vault Private DNS Zone Group
resource keyVaultPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-01-01' = {
  parent: keyVaultPrivateEndpoint
  name: 'keyVaultPrivateDnsZoneGroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config'
        properties: {
          privateDnsZoneId: keyVaultPrivateDnsZone.id
        }
      }
    ]
  }
}

// Outputs
output aksName string = aks.name
output acrLoginServer string = acr.properties.loginServer
output keyVaultName string = keyVault.name
output vnetName string = vnet.name
output aksSubnetName string = aksSubnet.name
output wafSubnetName string = wafSubnet.name
output controlPlaneFQDN string = aks.properties.fqdn
