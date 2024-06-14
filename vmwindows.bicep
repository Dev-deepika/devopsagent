@description('Username for the Virtual Machine.')
param adminUsername string

@description('Password for the Virtual Machine.')
@minLength(12)
@secure()
param adminPassword string

@description('Allocation method for the Public IP used to access the Virtual Machine.')
@allowed([
  'Dynamic'
  'Static'
])
param publicIPAllocationMethod string = 'Dynamic'

@description('SKU for the Public IP used to access the Virtual Machine.')
@allowed([
  'Basic'
  'Standard'
])
param publicIpSku string = 'Basic'

@description('The Windows version for the VM. This will pick a fully patched image of this given Windows version.')
@allowed([
  '20_04-lts-gen2'
])
param OSVersion string = '20_04-lts-gen2'

@description('Size of the virtual machine.')
param vmSize string = 'Standard_D4ads_v5'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Name of the virtual machine.')
param vmName string = 'devopsagent'

@description('Indicator to guide whether the CI/CD agent script should be run or not')
param deployAgent bool = true

@description('The Azure DevOps or GitHub account name')
param accountName string = ''

@description('The personal access token to connect to Azure DevOps or Github')
@secure()
param personalAccessToken string = ''

@description('The name Azure DevOps or GitHub pool for this build agent to join. Use \'Default\' if you don\'t have a separate pool.')
param poolName string = 'Default'

@description('The CI/CD platform to be used, and for which an agent will be configured for the ASE deployment. Specify \'none\' if no agent needed')
@allowed([
  'azuredevops'
])
param CICDAgentType string = 'azuredevops'

@allowed(['linux', 'windows'])
param os string = 'linux'

var vmNameWithOs = '${vmName}-${os}'
var agentName = 'agent-${vmNameWithOs}'
var nicName = 'myVMNic-${vmNameWithOs}'
var addressPrefix = '10.0.0.0/16'
var subnetName = 'Subnet'
var subnetPrefix = '10.0.0.0/24'
var virtualNetworkName = 'MyVNET-${vmNameWithOs}'
var networkSecurityGroupName = 'default-NSG-${vmNameWithOs}'
var publicIpName = 'myPublicIP-${vmNameWithOs}'

var dnsLabelPrefix = toLower('${vmName}-${take(os, 3)}-${uniqueString(resourceGroup().id, vmName)}')

var osSettings = {
  linux: {
    image: {
      publisher: 'canonical'
      offer: '0001-com-ubuntu-server-focal'
      sku: OSVersion
      version: 'latest'
    }
    script: {
      file: 'https://raw.githubusercontent.com/martins-vds/devopsagent/master/agentsetup.sh'
      settings: {
        skipDos2Unix: false
        fileUris: [
          'https://raw.githubusercontent.com/martins-vds/devopsagent/master/agentsetup.sh'
        ]
      }
      command: 'chmod +x agentsetup.sh | ./agentsetup.sh ${accountName} ${personalAccessToken} ${poolName} ${agentName} ${CICDAgentType} '
    }
  }
  windows: {
    image: {
      publisher: 'MicrosoftWindowsServer'
      offer: 'WindowsServer'
      sku: '2022-datacenter-azure-edition'
      version: 'latest'
    }
    script: {
      file: 'https://raw.githubusercontent.com/martins-vds/devopsagent/master/agentsetup.ps1'
      settings: {}
      command: 'powershell -ExecutionPolicy Unrestricted -File agentsetup.ps1 -URL ${accountName} -PAT ${personalAccessToken} -POOL ${poolName} -AGENT ${agentName} -AGENTTYPE ${CICDAgentType}'
    }
  }
}

resource pip 'Microsoft.Network/publicIPAddresses@2021-02-01' = {
  name: publicIpName
  location: location
  sku: {
    name: publicIpSku
  }
  properties: {
    publicIPAllocationMethod: publicIPAllocationMethod
    dnsSettings: {
      domainNameLabel: dnsLabelPrefix
    }
  }
}

resource securityGroup 'Microsoft.Network/networkSecurityGroups@2021-02-01' = {
  name: networkSecurityGroupName
  location: location
  properties: {
    securityRules: [
      {
        name: 'default-allow-22'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '22'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource vn 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetPrefix
          networkSecurityGroup: {
            id: securityGroup.id
          }
        }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2021-02-01' = {
  name: nicName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: pip.id
          }
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vn.name, subnetName)
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2021-03-01' = {
  name: vmNameWithOs
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: take(vmNameWithOs, 15)
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: osSettings[os].image
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
        diskSizeGB: 256
      }
      dataDisks: [
        {
          diskSizeGB: 1023
          lun: 0
          createOption: 'Empty'
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
        enabled: false
      }
    }
  }
}

// deploy CI/CD agent, if required
resource vm_CustomScript 'Microsoft.Compute/virtualMachines/extensions@2021-04-01' = if (deployAgent) {
  parent: vm
  name: 'CustomScript'
  location: location
  properties: {
    publisher: (os == 'linux' ? 'Microsoft.Azure.Extensions' : 'Microsoft.Compute')
    type: (os == 'linux' ? 'CustomScript' : 'CustomScriptExtension')
    typeHandlerVersion: (os == 'linux' ? '2.1' : '1.10')
    autoUpgradeMinorVersion: true
    settings: osSettings[os].script.settings
    protectedSettings: {
      fileUris: [
        osSettings[os].script.file
      ]
      commandToExecute: osSettings[os].script.command
    }
  }
}

// outputs
output id string = vm.id

output hostname string = pip.properties.dnsSettings.fqdn
