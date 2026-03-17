// ========== Jump Box VM ========== //
// A small Linux VM inside the VNet that you connect to via Azure Bastion.
// Once connected, you can:
//   - Run Python scripts (build_solution, test_agent, etc.)
//   - Access Key Vault, Cosmos DB, AI Services (all via private endpoints)
//   - Push Docker images to ACR
//   - Basically anything that requires being "inside the network"
//
// The VM uses a cloud-init script to pre-install Python, pip, git, Docker CLI,
// and the Azure CLI — so it's ready to go when you first connect.

@description('Name of the jump box VM.')
param vmName string

@description('Location for the VM.')
param solutionLocation string

@description('Subnet ID where the VM NIC will be placed.')
param subnetId string

@description('Admin username for SSH login.')
param adminUsername string = 'azureuser'

@description('SSH public key for authentication (recommended over passwords).')
@secure()
param adminSshPublicKey string = ''

@description('Admin password (used only if no SSH key is provided).')
@secure()
param adminPassword string = ''

@description('VM size. Standard_D2s_v5 = 2 vCPU, 8 GB RAM — enough for XFCE desktop + Edge + scripts.')
param vmSize string = 'Standard_D2s_v5'

@description('User-assigned Managed Identity resource ID to attach to the VM. This lets the VM authenticate to Azure services without storing credentials.')
param userAssignedIdentityId string = ''

// ---------- Network Interface ---------- //
// The NIC connects the VM to the jumpbox subnet. No public IP — access is via Bastion only.
resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: 'nic-${vmName}'
  location: solutionLocation
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          // No publicIPAddress — VM is only reachable via Bastion.
        }
      }
    ]
  }
}

// ---------- Cloud-init script ---------- //
// This runs automatically on first boot to install the tools you need.
// Includes XFCE desktop + Edge browser + xrdp so you can RDP in via Bastion.
var cloudInit = '''#!/bin/bash
set -e

# Update packages
apt-get update && apt-get upgrade -y

# Python + pip + venv (for running your build scripts)
apt-get install -y python3 python3-pip python3-venv

# Git (to clone your repo onto the VM)
apt-get install -y git

# Azure CLI (to interact with Azure resources from the VM)
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Docker CLI (to build and push images to ACR)
apt-get install -y docker.io
systemctl enable docker
systemctl start docker
usermod -aG docker azureuser

# ---- Desktop environment (XFCE) ----
# XFCE is lightweight — uses ~200MB RAM vs 1GB+ for GNOME.
# This gives you a full desktop with file manager, terminal, etc.
apt-get install -y xfce4 xfce4-goodies

# ---- xrdp (RDP server) ----
# This lets Bastion connect via RDP (not just SSH).
# In the portal: VM → Connect → Bastion → choose "RDP" → get a desktop.
apt-get install -y xrdp
systemctl enable xrdp
# Tell xrdp to use XFCE as the desktop
echo "xfce4-session" > /home/azureuser/.xsession
chown azureuser:azureuser /home/azureuser/.xsession
# Fix permissions so xrdp can create sessions
adduser xrdp ssl-cert
systemctl restart xrdp

# ---- Microsoft Edge browser ----
# Add Microsoft's package repo, then install Edge stable.
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-edge.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-edge.gpg] https://packages.microsoft.com/repos/edge stable main" > /etc/apt/sources.list.d/microsoft-edge.list
apt-get update
apt-get install -y microsoft-edge-stable

echo "Jump box setup complete — desktop + Edge + dev tools ready!"
'''

// ---------- Virtual Machine ---------- //
// Use SSH key auth when possible (more secure). Falls back to password if no key provided.
var useSSHKey = !empty(adminSshPublicKey)

resource vm 'Microsoft.Compute/virtualMachines@2024-03-01' = {
  name: vmName
  location: solutionLocation
  identity: !empty(userAssignedIdentityId) ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  } : {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      // SSH key auth (preferred)
      linuxConfiguration: useSSHKey ? {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSshPublicKey
            }
          ]
        }
      } : {
        disablePasswordAuthentication: false
      }
      // Password auth (fallback) — only used if no SSH key is provided.
      adminPassword: useSSHKey ? null : adminPassword
      // Cloud-init runs on first boot to install Python, Azure CLI, Docker, etc.
      customData: base64(cloudInit)
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 128
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

// ---------- AAD Login Extension ---------- //
// Lets you SSH into the VM using your Azure AD credentials (az ssh vm).
// This means you don't even need to manage SSH keys or passwords —
// anyone with the "Virtual Machine User Login" role on the VM can connect.
resource aadLoginExtension 'Microsoft.Compute/virtualMachines/extensions@2024-03-01' = {
  parent: vm
  name: 'AADSSHLoginForLinux'
  location: solutionLocation
  properties: {
    publisher: 'Microsoft.Azure.ActiveDirectory'
    type: 'AADSSHLoginForLinux'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
  }
}

// ---------- Outputs ---------- //
output vmId string = vm.id
output vmName string = vm.name
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
