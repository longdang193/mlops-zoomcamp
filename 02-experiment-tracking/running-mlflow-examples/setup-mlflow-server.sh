#!/bin/bash
# Install and configure MLflow server on Azure VM
# Run this script after SSH'ing into the VM created by setup-azure-resources.sh

set -e  # Exit on error

# === Colors ===
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== MLflow Server Setup on Azure VM ===${NC}\n"

# === Configuration ===
read -p "PostgreSQL host (e.g., pg-mlflow-1234.postgres.database.azure.com): " POSTGRES_HOST
read -p "PostgreSQL user [mlflow]: " POSTGRES_USER
POSTGRES_USER=${POSTGRES_USER:-mlflow}
read -sp "PostgreSQL password: " POSTGRES_PASSWORD
echo ""
read -p "PostgreSQL database [mlflow]: " POSTGRES_DB
POSTGRES_DB=${POSTGRES_DB:-mlflow}

ARTIFACT_ROOT="/home/$(whoami)/mlruns-artifacts"

# === Step 1: System update ===
echo -e "\n${YELLOW}Updating system packages...${NC}"
sudo apt update && sudo apt upgrade -y

# === Step 2: Install dependencies ===
echo -e "\n${YELLOW}Installing Python, pip, and dependencies...${NC}"
sudo apt install -y python3 python3-pip python3-venv postgresql-client

# === Step 3: Install MLflow ===
echo -e "\n${YELLOW}Installing MLflow and PostgreSQL driver...${NC}"
# Note: pip3 installs latest MLflow (3.x) which requires Python 3.10+
# If you have Python 3.9, you'll get a version mismatch with this server
pip3 install --user mlflow psycopg2-binary

# Ensure ~/.local/bin is in PATH
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/.local/bin:$PATH"
fi

# === Step 4: Setup MLflow server script ===
echo -e "\n${YELLOW}Setting up MLflow server script...${NC}"
mkdir -p "$ARTIFACT_ROOT"
# Ensure the artifact directory is owned by the current user (azureuser)
# This prevents permission errors when MLflow writes artifacts
sudo chown -R "$(whoami):$(whoami)" "$ARTIFACT_ROOT"

cat > ~/start-mlflow-server.sh << EOF
#!/bin/bash
# Start MLflow server

export BACKEND_URI="postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:5432/${POSTGRES_DB}?sslmode=require"
export PATH="\$HOME/.local/bin:\$PATH"
# Disable host header validation for public IP access
export MLFLOW_ALLOWED_HOSTS="*"
export ALLOWED_HOSTS="*"

echo "Starting MLflow server..."
echo "Backend URI: postgresql+psycopg2://${POSTGRES_USER}:***@${POSTGRES_HOST}:5432/${POSTGRES_DB}"
echo "Artifacts directory: $ARTIFACT_ROOT"
echo "Access UI at: http://\$(curl -s ifconfig.me):5000"
echo ""

mlflow server \\
  --backend-store-uri "\$BACKEND_URI" \\
  --default-artifact-root mlflow-artifacts:/ \\
  --artifacts-destination "$ARTIFACT_ROOT" \\
  --host 0.0.0.0 \\
  --port 5000 \\
  --allowed-hosts "*"
EOF

chmod +x ~/start-mlflow-server.sh

# === Test DB connection ===
echo -e "\n${YELLOW}Testing PostgreSQL connection...${NC}"
export PGPASSWORD="$POSTGRES_PASSWORD"
if psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT version();" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Database connection successful!${NC}"
else
    echo -e "${RED}✗ Database connection failed. Check credentials or firewall rules.${NC}"
    exit 1
fi
unset PGPASSWORD

# === Done ===
echo -e "\n${GREEN}=== MLflow setup complete! ===${NC}\n"
echo "To start MLflow: ~/start-mlflow-server.sh"
echo "Run in background: nohup ~/start-mlflow-server.sh > mlflow-server.log 2>&1 &"
echo "Check health: curl http://localhost:5000/health"
echo "UI: http://<VM_PUBLIC_IP>:5000"
echo -e "${YELLOW}Ensure port 5000 is open in the VM's network security group.${NC}"
