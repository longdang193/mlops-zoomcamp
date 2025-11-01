#!/bin/bash
# Install and configure MLflow server on Azure VM with Azure Blob Storage
# Run this script after SSH'ing into the VM created by setup-azure-resources-blob.sh

set -e  # Exit on error

# === Colors ===
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== MLflow Server Setup on Azure VM (with Blob Storage) ===${NC}\n"

# === Configuration ===
read -p "PostgreSQL host (e.g., pg-mlflow-1234.postgres.database.azure.com): " POSTGRES_HOST
read -p "PostgreSQL user [mlflow]: " POSTGRES_USER
POSTGRES_USER=${POSTGRES_USER:-mlflow}
read -sp "PostgreSQL password: " POSTGRES_PASSWORD
echo ""
read -p "PostgreSQL database [mlflow]: " POSTGRES_DB
POSTGRES_DB=${POSTGRES_DB:-mlflow}

echo ""
read -p "Azure Storage Account Name: " STORAGE_ACCOUNT_NAME
read -sp "Azure Storage Account Key: " STORAGE_KEY
echo ""
read -p "Blob Container Name [mlflow-artifacts]: " CONTAINER_NAME
CONTAINER_NAME=${CONTAINER_NAME:-mlflow-artifacts}

# Build the artifact URI
ARTIFACT_URI="wasbs://${CONTAINER_NAME}@${STORAGE_ACCOUNT_NAME}.blob.core.windows.net/"

# === Step 1: System update ===
echo -e "\n${YELLOW}Updating system packages...${NC}"
sudo apt update && sudo apt upgrade -y

# === Step 2: Install dependencies ===
echo -e "\n${YELLOW}Installing Python, pip, and dependencies...${NC}"
sudo apt install -y python3 python3-pip python3-venv postgresql-client

# === Step 3: Install MLflow and Azure Storage dependencies ===
echo -e "\n${YELLOW}Installing MLflow, PostgreSQL driver, and Azure Storage Blob...${NC}"
# Note: pip3 installs latest MLflow (3.x) which requires Python 3.10+
# If you have Python 3.9, you'll get a version mismatch with this server
pip3 install --user mlflow psycopg2-binary azure-storage-blob

# Ensure ~/.local/bin is in PATH
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/.local/bin:$PATH"
fi

# === Step 4: Setup environment variables file ===
echo -e "\n${YELLOW}Setting up MLflow environment configuration...${NC}"
cat > ~/.mlflow-env << EOF
# MLflow Configuration for Azure Blob Storage
export MLFLOW_BACKEND_STORE_URI="postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:5432/${POSTGRES_DB}?sslmode=require"
export AZURE_STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCOUNT_NAME};AccountKey=${STORAGE_KEY};EndpointSuffix=core.windows.net"
export MLFLOW_DEFAULT_ARTIFACT_ROOT="${ARTIFACT_URI}"
export MLFLOW_ALLOWED_HOSTS="*"
export ALLOWED_HOSTS="*"
EOF

chmod 600 ~/.mlflow-env  # Restrict access to protect credentials

# === Step 5: Setup MLflow server script ===
echo -e "\n${YELLOW}Setting up MLflow server script...${NC}"

cat > ~/start-mlflow-server-blob.sh << 'SCRIPT_EOF'
#!/bin/bash
# Start MLflow server with Azure Blob Storage

# Load environment variables
source ~/.mlflow-env

export PATH="$HOME/.local/bin:$PATH"

echo "Starting MLflow server..."
echo "Backend URI: postgresql+psycopg2://$(echo $MLFLOW_BACKEND_STORE_URI | sed 's/:[^:@]*@/:***@/')"
echo "Artifact URI: $MLFLOW_DEFAULT_ARTIFACT_ROOT"
echo "Access UI at: http://$(curl -s ifconfig.me):5000"
echo ""

mlflow server \
  --backend-store-uri "$MLFLOW_BACKEND_STORE_URI" \
  --default-artifact-root "$MLFLOW_DEFAULT_ARTIFACT_ROOT" \
  --host 0.0.0.0 \
  --port 5000 \
  --allowed-hosts "*"
SCRIPT_EOF

chmod +x ~/start-mlflow-server-blob.sh

# === Step 6: Test DB connection ===
echo -e "\n${YELLOW}Testing PostgreSQL connection...${NC}"
export PGPASSWORD="$POSTGRES_PASSWORD"
if psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT version();" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Database connection successful!${NC}"
else
    echo -e "${RED}✗ Database connection failed. Check credentials or firewall rules.${NC}"
    exit 1
fi
unset PGPASSWORD

# === Step 7: Test Azure Blob Storage connection ===
echo -e "\n${YELLOW}Testing Azure Blob Storage connection...${NC}"
python3 << PYTHON_EOF
from azure.storage.blob import BlobServiceClient
import sys

try:
    connection_string = "DefaultEndpointsProtocol=https;AccountName=${STORAGE_ACCOUNT_NAME};AccountKey=${STORAGE_KEY};EndpointSuffix=core.windows.net"
    blob_service_client = BlobServiceClient.from_connection_string(connection_string)
    container_client = blob_service_client.get_container_client("${CONTAINER_NAME}")
    
    # Verify container exists and is accessible by getting its properties
    # This is more reliable than listing blobs and works with all azure-storage-blob versions
    container_properties = container_client.get_container_properties()
    print("✓ Azure Blob Storage connection successful!")
    print(f"  Container: ${CONTAINER_NAME} (last modified: {container_properties.last_modified})")
except Exception as e:
    print(f"✗ Azure Blob Storage connection failed: {e}")
    sys.exit(1)
PYTHON_EOF

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to connect to Azure Blob Storage. Check credentials and container name.${NC}"
    exit 1
fi

# === Done ===
echo -e "\n${GREEN}=== MLflow setup complete! ===${NC}\n"
echo "To start MLflow: ~/start-mlflow-server-blob.sh"
echo "Run in background: nohup ~/start-mlflow-server-blob.sh > mlflow-server.log 2>&1 &"
echo "Check health: curl http://localhost:5000/health"
echo "UI: http://<VM_PUBLIC_IP>:5000"
echo ""
echo -e "${YELLOW}Artifact Storage:${NC}"
echo "  URI: $ARTIFACT_URI"
echo "  Storage Account: $STORAGE_ACCOUNT_NAME"
echo "  Container: $CONTAINER_NAME"
echo ""
echo -e "${YELLOW}Note:${NC}"
echo "- Artifacts are stored in Azure Blob Storage"
echo "- No local artifact directory needed"
echo "- Ensure port 5000 is open in the VM's network security group"

