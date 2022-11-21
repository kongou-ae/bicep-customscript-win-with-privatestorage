param location string = 'japaneast'
param storageAcountName string = 'sta${uniqueString(resourceGroup().name)}'
param adminUserName string
@secure()
param adminPassword string

resource customStorage 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: storageAcountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
     allowBlobPublicAccess: false
  }
  resource blobServices 'blobServices' = {
    name: 'default'
    properties: {
    }
    resource container 'containers' = {
      name: 'customscript'
      properties: {
      }
    }
  }
}

resource userManagedId 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  location: location
  name: 'customScriptStorageAccess'
}

resource contributor 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: 'b24988ac-6180-42a0-ab88-20f7382dd24c'
}

resource rbacContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, userManagedId.id, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  scope: customStorage
  properties: {
    principalType: 'ServicePrincipal'
    principalId: userManagedId.properties.principalId
    roleDefinitionId: contributor.id
  }
}

resource UploadCustomScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  kind: 'AzureCLI'
  location: location
  name: 'UploadCustomScript'
  dependsOn: [
    rbacContributor
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userManagedId.id}': {
      }
    }
  }
  properties: {
    timeout: 'PT10M'
    azCliVersion: '2.9.1'
    retentionInterval: 'PT1H'
    environmentVariables: [
      {
        name: 'AZURE_STORAGE_KEY'
        secureValue: customStorage.listKeys().keys[0].value
      }
      {
        name: 'CONTENTS'
        value: loadTextContent('./customScript.ps1')
      }
    ]
    scriptContent: 'echo $CONTENTS > customScript.ps1 && az storage blob upload --account-name ${storageAcountName} -f customScript.ps1 -c customscript -n customScript.ps1'
  }
}

resource DisablePublicAccess 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  kind: 'AzureCLI'
  location: location
  name: 'DisablePublicAccess'
  dependsOn: [
    UploadCustomScript
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userManagedId.id}': {
      }
    }
  }
  properties: {
    environmentVariables: [
      {
        name: 'AZURE_STORAGE_KEY'
        secureValue: customStorage.listKeys().keys[0].value
      }
    ]    
    timeout: 'PT10M'
    azCliVersion: '2.9.1'
    retentionInterval: 'PT1H'
    scriptContent: 'az storage account update -n ${storageAcountName} -g ${resourceGroup().name} --default-action Deny'
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: 'custom-je-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'iaas'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
      {
        name: 'storagePe'
        properties: {
          addressPrefix: '10.0.2.0/24'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.3.0/24'
        }
      }
    ]
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2022-05-01' = {
  name: 'custom-je-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Out-Allow-PE'
        properties: {
          access: 'Allow'
          protocol: 'Tcp'
          direction: 'Outbound'
          priority: 110
          destinationAddressPrefix: '10.0.2.4/32'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
        }
      }
      {
        name: 'Out-Deny-All'
        properties: {
          access: 'Deny'
          protocol: '*'
          direction: 'Outbound'
          priority: 120
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
        }
      }

    ]
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2022-05-01' = {
  name: 'custom-je-pe'
  location: location
  properties: {
    subnet: {
      id: '${vnet.id}/subnets/storagePe'
    }
    customNetworkInterfaceName: 'custom-je-pe-nic'
    privateLinkServiceConnections: [
      {
        name: 'connection'
        properties: {
          privateLinkServiceId: customStorage.id
          groupIds: [
            'blob'
          ]
          privateLinkServiceConnectionState: {
            actionsRequired: 'None'
            status: 'Approved'
            description: 'Auto-Approved'
          }
        }

      }
    ]
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
  location: 'global'
}

resource privateDnsZoneVnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: 'custom-je-dns-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2021-05-01' = {
  parent: privateEndpoint
  name: 'custom-je-dns-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

resource vmnic 'Microsoft.Network/networkInterfaces@2022-05-01' = {
  name: 'custom-je-vmnic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/iaas'
          }
          primary: true
          privateIPAddressVersion: 'IPv4'
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource customVm 'Microsoft.Compute/virtualMachines@2022-08-01' = {
  name: 'customVm01'
  location: location
  dependsOn: [
    DisablePublicAccess
    privateDnsZoneVnetLink
  ]
  properties: {
    networkProfile: {
      networkInterfaces: [
        {
          id: vmnic.id
          properties: {
            primary: true
          }
        }
      ]
    }
    hardwareProfile: {
      vmSize: 'Standard_B2ms'
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        osType: 'Windows'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2022-Datacenter'
        version: 'latest'
      }
    }
    osProfile: {
      computerName: 'customVm01'
      adminUsername: adminUserName
      adminPassword: adminPassword
    }
     diagnosticsProfile: {
       bootDiagnostics: {
         enabled: true
       }
     }
  }
}

resource customScript 'Microsoft.Compute/virtualMachines/extensions@2022-08-01' = {
  parent: customVm
  location: location
  name: 'customScript'
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.7'
    autoUpgradeMinorVersion: true
    protectedSettings:{
      storageAccountName: customStorage.name
      storageAccountKey: customStorage.listKeys().keys[0].value
      fileUris: [
        '${customStorage.properties.primaryEndpoints.blob}customscript/customScript.ps1'
      ]
      commandToExecute: 'powershell.exe -ExecutionPolicy Unrestricted -File customScript.ps1'
    }
  }
}
