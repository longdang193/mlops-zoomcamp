#!/bin/bash
# Setup minimal-cost MLflow infrastructure on Azure for Students with Blob Storage
# Creates: Resource Group, PostgreSQL Flexible Server, Azure Storage Account, Blob Container, and Ubuntu VM

set -e  # Exit on error

# === Configuration ===
RESOURCE_GROUP="rg-mlflow-blob"
LOCATION="southeastasia"
POSTGRES_SERVER_NAME="pg-mlflow-$(date +%s | tail -c 5)"
STORAGE_ACCOUNT_NAME="stmlflow$(date +%s | tail -c 8 | tr '[:upper:]' '[:lower:]')"
CONTAINER_NAME="mlflow-artifacts"
VM_NAME="vm-mlflow-blob"
POSTGRES_ADMIN_USER="mlflow"
VM_ADMIN_USER="azureuser"

# === Colors ===
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== MLflow Azure Setup Script (with Blob Storage) ===${NC}\n"

# === Check resource providers ===
echo -e "${YELLOW}Checking required Azure resource providers...${NC}"
POSTGRES_STATE=$(az provider show --namespace Microsoft.DBforPostgreSQL --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
COMPUTE_STATE=$(az provider show --namespace Microsoft.Compute --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
STORAGE_STATE=$(az provider show --namespace Microsoft.Storage --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")

if [ "$POSTGRES_STATE" != "Registered" ] || [ "$COMPUTE_STATE" != "Registered" ] || [ "$STORAGE_STATE" != "Registered" ]; then
    echo -e "${RED}Error: Required resource providers are not registered!${NC}"
    echo "PostgreSQL: $POSTGRES_STATE"
    echo "Compute: $COMPUTE_STATE"
    echo "Storage: $STORAGE_STATE"
    echo ""
    echo "Please run these commands to register them:"
    echo "  az provider register --namespace Microsoft.DBforPostgreSQL --wait"
    echo "  az provider register --namespace Microsoft.Compute --wait"
    echo "  az provider register --namespace Microsoft.Network --wait"
    echo "  az provider register --namespace Microsoft.Storage --wait"
    echo ""
    echo "Or run: ./check-providers.sh"
    exit 1
fi
echo -e "${GREEN}✓ All resource providers are registered${NC}\n"

echo "This script will create:"
echo "  - Resource Group: $RESOURCE_GROUP"
echo "  - PostgreSQL Server: $POSTGRES_SERVER_NAME"
echo "  - Storage Account: $STORAGE_ACCOUNT_NAME"
echo "  - Blob Container: $CONTAINER_NAME"
echo "  - Ubuntu VM: $VM_NAME (region: $LOCATION)"
echo ""

# === Prompt for PostgreSQL password ===
read -sp "Enter PostgreSQL password for '$POSTGRES_ADMIN_USER': " POSTGRES_PASSWORD
echo ""
read -sp "Confirm password: " POSTGRES_PASSWORD_CONFIRM
echo ""

if [ "$POSTGRES_PASSWORD" != "$POSTGRES_PASSWORD_CONFIRM" ]; then
    echo -e "${RED}Error: Passwords do not match!${NC}"
    exit 1
fi

if [ ${#POSTGRES_PASSWORD} -lt 8 ]; then
    echo -e "${RED}Error: Password must be at least 8 characters long!${NC}"
    exit 1
fi

# === Step 1: Resource Group ===
echo -e "\n${YELLOW}Creating resource group...${NC}"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output json

# === Step 2: PostgreSQL Server ===
echo -e "\n${YELLOW}Creating PostgreSQL Flexible Server (B1ms)...${NC}"
az postgres flexible-server create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$POSTGRES_SERVER_NAME" \
    --location "$LOCATION" \
    --admin-user "$POSTGRES_ADMIN_USER" \
    --admin-password "$POSTGRES_PASSWORD" \
    --sku-name Standard_B1ms \
    --tier Burstable \
    --storage-size 32 \
    --version 14 \
    --public-access 0.0.0.0-255.255.255.255 \
    --output json

# === Step 3: Database ===
echo -e "\n${YELLOW}Creating database 'mlflow'...${NC}"
az postgres flexible-server db create \
    --resource-group "$RESOURCE_GROUP" \
    --server-name "$POSTGRES_SERVER_NAME" \
    --database-name mlflow \
    --output json

# === Step 4: Storage Account ===
echo -e "\n${YELLOW}Creating Azure Storage Account...${NC}"
az storage account create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$STORAGE_ACCOUNT_NAME" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --access-tier Hot \
    --https-only true \
    --output json

# === Step 5: Blob Container ===
echo -e "\n${YELLOW}Creating blob container '$CONTAINER_NAME'...${NC}"
STORAGE_KEY=$(az storage account keys list \
    --resource-group "$RESOURCE_GROUP" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --query "[0].value" \
    --output tsv)

az storage container create \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --account-key "$STORAGE_KEY" \
    --auth-mode key \
    --public-access off \
    --output json

# === Step 6: VM ===
echo -e "\n${YELLOW}Creating Ubuntu VM (D2s_v3)...${NC}"
az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --image Ubuntu2204 \
    --size Standard_D2s_v3 \
    --admin-username "$VM_ADMIN_USER" \
    --generate-ssh-keys \
    --public-ip-sku Standard \
    --output json

# === Step 7: Open Port for MLflow ===
echo -e "\n${YELLOW}Opening port 5000 for MLflow server...${NC}"
az vm open-port \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --port 5000 \
    --priority 1010 \
    --output json

# === Summary ===
echo -e "\n${GREEN}=== Setup Complete! ===${NC}\n"

VM_IP=$(az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --show-details \
    --query publicIps \
    --output tsv)

POSTGRES_HOST="${POSTGRES_SERVER_NAME}.postgres.database.azure.com"

echo -e "${GREEN}Resource Details:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  PostgreSQL Server: $POSTGRES_HOST"
echo "  Database: mlflow"
echo "  User: $POSTGRES_ADMIN_USER"
echo "  Storage Account: $STORAGE_ACCOUNT_NAME"
echo "  Container: $CONTAINER_NAME"
echo "  Storage Key: $STORAGE_KEY"
echo "  VM: $VM_NAME"
echo "  VM IP: $VM_IP"
echo ""

echo -e "${YELLOW}Connection Strings:${NC}"
echo "PostgreSQL URI:"
echo "  postgresql+psycopg2://${POSTGRES_ADMIN_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:5432/mlflow?sslmode=require"
echo ""
echo "Azure Blob Storage URI:"
echo "  wasbs://${CONTAINER_NAME}@${STORAGE_ACCOUNT_NAME}.blob.core.windows.net/"
echo ""
echo "Storage Account Connection String:"
CONNECTION_STRING=$(az storage account show-connection-string \
    --resource-group "$RESOURCE_GROUP" \
    --name "$STORAGE_ACCOUNT_NAME" \
    --query connectionString \
    --output tsv)
echo "  $CONNECTION_STRING"
echo ""

echo -e "${YELLOW}Next Steps:${NC}"
echo "1. SSH into VM: ssh ${VM_ADMIN_USER}@${VM_IP}"
echo "2. Run: ./setup-mlflow-server-blob.sh"
echo "3. You will need to provide:"
echo "   - PostgreSQL credentials (above)"
echo "   - Storage Account Name: $STORAGE_ACCOUNT_NAME"
echo "   - Storage Account Key: $STORAGE_KEY"
echo "   - Container Name: $CONTAINER_NAME"

