#!/bin/bash
# Setup Azure Machine Learning workspace for MLflow tracking
# Creates: Resource Group and Azure ML Workspace

set -e  # Exit on error

# === Configuration ===
RESOURCE_GROUP="rg-azureml-mlflow"
LOCATION="southeastasia"
WORKSPACE_NAME="aml-mlflow-$(date +%s | tail -c 5)"

# === Colors ===
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Azure ML Workspace Setup ===${NC}\n"

# === Check resource providers ===
echo -e "${YELLOW}Checking required Azure resource providers...${NC}"
ML_STATE=$(az provider show --namespace Microsoft.MachineLearningServices --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
STORAGE_STATE=$(az provider show --namespace Microsoft.Storage --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")

if [ "$ML_STATE" != "Registered" ] || [ "$STORAGE_STATE" != "Registered" ]; then
    echo -e "${RED}Error: Required resource providers are not registered!${NC}"
    echo "Machine Learning: $ML_STATE"
    echo "Storage: $STORAGE_STATE"
    echo ""
    echo "Please run these commands to register them:"
    echo "  az provider register --namespace Microsoft.MachineLearningServices --wait"
    echo "  az provider register --namespace Microsoft.Storage --wait"
    exit 1
fi
echo -e "${GREEN}✓ All resource providers are registered${NC}\n"

echo "This script will create:"
echo "  - Resource Group: $RESOURCE_GROUP"
echo "  - Azure ML Workspace: $WORKSPACE_NAME"
echo "  - Storage Account (auto-created by workspace)"
echo ""

# === Step 1: Resource Group ===
echo -e "\n${YELLOW}Creating resource group...${NC}"
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output json

# === Step 2: Azure ML Workspace ===
echo -e "\n${YELLOW}Creating Azure Machine Learning workspace...${NC}"
az ml workspace create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$WORKSPACE_NAME" \
    --location "$LOCATION" \
    --output json

# === Summary ===
echo -e "\n${GREEN}=== Setup Complete! ===${NC}\n"

echo -e "${GREEN}Workspace Details:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Workspace Name: $WORKSPACE_NAME"
echo "  Location: $LOCATION"
echo ""

echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Install Azure ML SDK:"
echo "   pip install azure-ai-ml azure-identity azureml-mlflow"
echo ""
echo "2. Get your subscription ID:"
echo "   az account show --query id -o tsv"
echo ""
echo "3. Use the workspace in your notebook (see scenario-azureml.ipynb)"
echo ""
echo -e "${YELLOW}Cost Management:${NC}"
echo "- Azure ML workspace: ~$0/month (free tier available)"
echo "- You only pay for compute resources when running experiments"
echo "- Check credit: az account show"
echo "- Delete when done: az group delete -n $RESOURCE_GROUP --yes --no-wait"
echo ""
echo -e "${GREEN}Save these details:${NC}"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Workspace Name: $WORKSPACE_NAME"
echo ""


