#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- Variables ---
REGION="eastus"
USERNAME="kk_lab_user_main-cb7eb4fc072146fc@azurekmlprodkodekloud.onmicrosoft.com"
PASSWORD="8F97FXLSWVJ#D@+&"
VM_SIZE="Standard_B1s"
OS_DISK_SKU="Standard_LRS"     # Explicit SKU definition to comply with Azure Policy
OS_DISK_SIZE=30                # Explicit size under 128 GB to satisfy lab restrictions

# Dynamic Resource Group Name with current date
RG_NAME="kml_rg_main-5113e54225244669"
VNET_NAME="eus-web-dev"

# Helper color functions
print_yellow() { echo -e "\e[40m\e[33m$1\e[0m"; }
print_status() { echo -e "\e[43m\e[37m$1\e[0m"; }

# --- Create Resource Group ---
print_yellow "Creating Resource Group: $RG_NAME"
#az group create --name "$RG_NAME" --location "$REGION" --output none

# --- Create Networking Infrastructure ---
print_yellow "Adding subnet configuration & Creating $VNET_NAME"
az network vnet create \
  --resource-group "$RG_NAME" \
  --name "$VNET_NAME" \
  --location "$REGION" \
  --address-prefixes 10.0.0.0/16 \
  --subnet-name "jumpboxSubnet" \
  --subnet-prefixes 10.0.1.0/24 \
  --output none

# Create the second subnet explicitly
az network vnet subnet create \
  --resource-group "$RG_NAME" \
  --vnet-name "$VNET_NAME" \
  --name "webSubnet" \
  --address-prefixes 10.0.2.0/24 \
  --output none

# Create Network Security Group (NSG) and Security Rule
print_yellow "Creating webNSG and adding web-rule"
az network nsg create \
  --resource-group "$RG_NAME" \
  --location "$REGION" \
  --name "webNSG" \
  --output none

az network nsg rule create \
  --resource-group "$RG_NAME" \
  --nsg-name "webNSG" \
  --name "web-rule" \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes Internet \
  --source-port-ranges '*' \
  --destination-address-prefixes '*' \
  --destination-port-ranges 80 \
  --description "Allow HTTP" \
  --output none

# Associate NSG with webSubnet
az network vnet subnet update \
  --resource-group "$RG_NAME" \
  --vnet-name "$VNET_NAME" \
  --name "webSubnet" \
  --network-security-group "webNSG" \
  --output none

# --- Create Availability Set ---
print_yellow "Creating availability set"
az vm availability-set create \
  --resource-group "$RG_NAME" \
  --name "az-web-set" \
  --location "$REGION" \
  --platform-update-domain-count 3 \
  --platform-fault-domain-count 3 \
  --output none

# --- Deploy Web Servers Loop ---
for i in {1..3}; do
    print_yellow "----------------------------------------------------"
    print_yellow "Creating NIC: webserver-0$i-nic"
    
    az network nic create \
      --resource-group "$RG_NAME" \
      --name "webserver-0$i-nic" \
      --location "$REGION" \
      --vnet-name "$VNET_NAME" \
      --subnet "webSubnet" \
      --output none

    print_yellow "Creating VM webserver-0$i"
    az vm create \
      --resource-group "$RG_NAME" \
      --name "webserver-0$i" \
      --location "$REGION" \
      --nics "webserver-0$i-nic" \
      --availability-set "az-web-set" \
      --size "$VM_SIZE" \
      --admin-username "mgopi1982" \
      --admin-password "$PASSWORD" \
      --image "Canonical:0001-com-ubuntu-server-jammy:22_04-lts-gen2:latest" \
      --os-disk-name "webserver-0$i-osdisk" \
      --storage-sku "$OS_DISK_SKU" \
      --os-disk-size-gb "$OS_DISK_SIZE" \
      --output none
done

# --- Deploy Jumpbox VM ---
print_yellow "Creating jumpbox VM"
az vm create \
  --resource-group "$RG_NAME" \
  --name "jumpbox-vm" \
  --location "$REGION" \
  --vnet-name "$VNET_NAME" \
  --subnet "jumpboxSubnet" \
  --size "Standard_B1s" \
  --admin-username "mgopi1982" \
  --admin-password "$PASSWORD" \
  --image "Ubuntu2204" \
  --public-ip-address "jumpbox-pip" \
  --public-ip-sku "Standard" \
  --storage-sku "$OS_DISK_SKU" \
  --os-disk-size-gb "$OS_DISK_SIZE" \
  --output none

# --- Configure Jumpbox via Custom Script Extension ---
print_status "Configuring VMs..."
az vm extension set \
  --resource-group "$RG_NAME" \
  --vm-name "jumpbox-vm" \
  --name "CustomScript" \
  --publisher "Microsoft.Azure.Extensions" \
  --version "2.1" \
  --settings '{"fileUris": ["https://raw.githubusercontent.com/rithinskaria/kodekloud-az500/main/000-Code%20files/Azure%20Load%20Balancer/jumpbox.sh"], "commandToExecute": "./jumpbox.sh"}' \
  --output none

print_status "Deployment Completed!!"

# --- Print Outputs ---
JUMPBOX_IP=$(az network public-ip show --resource-group "$RG_NAME" --name "jumpbox-pip" --query "ipAddress" -o tsv)
echo "Jumpbox VM Public IP: $JUMPBOX_IP"

for i in {1..3}; do
    VM_IP=$(az network nic show --resource-group "$RG_NAME" --name "webserver-0$i-nic" --query "ipConfigurations[0].privateIpAddress" -o tsv)
    echo "Private IP (webserver-0$i) : $VM_IP"
done
