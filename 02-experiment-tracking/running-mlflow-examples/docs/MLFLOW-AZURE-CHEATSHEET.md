Quick reference for MLflow server configuration and troubleshooting on Azure.

## Setup Options Overview

**Option 1: Local Disk Storage** (~$20-25/month)
- Artifacts stored on VM local disk
- Simpler setup, no Storage Account needed
- Scripts: `setup-azure-resources.sh`, `setup-mlflow-server.sh`
- Resource Group: `rg-mlflow`
- VM: `vm-mlflow`

**Option 2: Azure Blob Storage** (~$50-65/month)
- Artifacts stored in Azure Blob Storage
- Scalable, persistent storage
- Scripts: `setup-azure-resources-blob.sh`, `setup-mlflow-server-blob.sh`
- Resource Group: `rg-mlflow-blob`
- VM: `vm-mlflow-blob`

## Critical MLflow Server Configuration

### Option 1: Local Disk

```bash
mlflow server \
  --backend-store-uri "postgresql+psycopg2://USER:PASSWORD@HOST:5432/DB?sslmode=require" \
  --default-artifact-root mlflow-artifacts:/ \
  --artifacts-destination /home/azureuser/mlruns-artifacts \
  --host 0.0.0.0 \
  --port 5000 \
  --allowed-hosts "*"
```

**Key Flags:**
- `--default-artifact-root mlflow-artifacts:/` - ⚠️ **CRITICAL**: Enables HTTP proxying for artifacts
- `--artifacts-destination` - Where server stores artifact files on local disk
- Both flags required for proper remote artifact handling

### Option 2: Azure Blob Storage

```bash
mlflow server \
  --backend-store-uri "postgresql+psycopg2://USER:PASSWORD@HOST:5432/DB?sslmode=require" \
  --default-artifact-root "wasbs://CONTAINER@STORAGE_ACCOUNT.blob.core.windows.net/" \
  --host 0.0.0.0 \
  --port 5000 \
  --allowed-hosts "*"
```

**Key Flags:**
- `--default-artifact-root wasbs://...` - Direct Azure Blob Storage URI
- Artifacts stored directly in Blob Storage, not on VM
- Requires `AZURE_STORAGE_CONNECTION_STRING` environment variable

## When You Forget Connection Details

**Get VM IP:**

```bash
# Option 1
az vm show -g rg-mlflow -n vm-mlflow --show-details --query publicIps -o tsv

# Option 2
az vm show -g rg-mlflow-blob -n vm-mlflow-blob --show-details --query publicIps -o tsv
```

**Get PostgreSQL Host:**

```bash
# Option 1
az postgres flexible-server list -g rg-mlflow --query "[0].fullyQualifiedDomainName" -o tsv

# Option 2
az postgres flexible-server list -g rg-mlflow-blob --query "[0].fullyQualifiedDomainName" -o tsv
```

**Get Storage Account (Option 2 only):**

```bash
az storage account list -g rg-mlflow-blob --query "[0].name" -o tsv
```

**Find resource group if you forgot the name:**

```bash
az group list --query "[?contains(name, 'mlflow')].name" -o tsv
```

## Common Commands

### Azure CLI - Resource Management

**Option 1 (Local Disk):**

```bash
# Create resources
./setup-azure-resources.sh

# Delete resource group
az group delete -n rg-mlflow --yes --no-wait

# Stop/start VM
az vm deallocate -g rg-mlflow -n vm-mlflow
az vm start -g rg-mlflow -n vm-mlflow

# Get VM IP
az vm show -g rg-mlflow -n vm-mlflow --show-details --query publicIps -o tsv

# Restart VM
az vm restart -g rg-mlflow -n vm-mlflow
```

**Option 2 (Blob Storage):**

```bash
# Create resources
./setup-azure-resources-blob.sh

# Delete resource group (deletes Storage Account and all blobs!)
az group delete -n rg-mlflow-blob --yes --no-wait

# Stop/start VM
az vm deallocate -g rg-mlflow-blob -n vm-mlflow-blob
az vm start -g rg-mlflow-blob -n vm-mlflow-blob

# Get VM IP
az vm show -g rg-mlflow-blob -n vm-mlflow-blob --show-details --query publicIps -o tsv

# Restart VM
az vm restart -g rg-mlflow-blob -n vm-mlflow-blob
```

**Common Commands:**

```bash
# Check resource providers
az provider show --namespace Microsoft.DBforPostgreSQL --query "registrationState" -o tsv
az provider show --namespace Microsoft.Compute --query "registrationState" -o tsv
az provider show --namespace Microsoft.Storage --query "registrationState" -o tsv  # Option 2 only

# Register providers
az provider register --namespace Microsoft.DBforPostgreSQL --wait
az provider register --namespace Microsoft.Compute --wait
az provider register --namespace Microsoft.Storage --wait  # Option 2 only

# List resource groups
az group list --query "[?contains(name, 'mlflow')].{Name:name, Location:location}" -o table

# Check current subscription
az account show
```

### Azure Storage Account Commands (Option 2 Only)

```bash
# List storage accounts
az storage account list -g rg-mlflow-blob --query "[].{Name:name, Location:location}" -o table

# Get storage account keys
az storage account keys list \
  --resource-group rg-mlflow-blob \
  --account-name <STORAGE_ACCOUNT_NAME> \
  --query "[0].value" \
  --output tsv

# Get connection string
az storage account show-connection-string \
  --resource-group rg-mlflow-blob \
  --name <STORAGE_ACCOUNT_NAME> \
  --query connectionString \
  --output tsv

# List containers
az storage container list \
  --account-name <STORAGE_ACCOUNT_NAME> \
  --account-key <KEY> \
  --auth-mode key \
  --query "[].{Name:name, LastModified:properties.lastModified}" -o table

# Create container
az storage container create \
  --name mlflow-artifacts \
  --account-name <STORAGE_ACCOUNT_NAME> \
  --account-key <KEY> \
  --auth-mode key

# List blobs in container
az storage blob list \
  --container-name mlflow-artifacts \
  --account-name <STORAGE_ACCOUNT_NAME> \
  --account-key <KEY> \
  --auth-mode key \
  --output table
```

### SSH & File Transfer

```bash
# Connect to VM
ssh azureuser@<VM_PUBLIC_IP>

# Transfer setup script to VM
# Option 1:
scp setup-mlflow-server.sh azureuser@<VM_PUBLIC_IP>:~/

# Option 2:
scp setup-mlflow-server-blob.sh azureuser@<VM_PUBLIC_IP>:~/

# Add SSH key if connection denied
# Option 1:
az vm user update --resource-group rg-mlflow --name vm-mlflow --username azureuser --ssh-key-value "$(cat ~/.ssh/id_rsa.pub)"

# Option 2:
az vm user update --resource-group rg-mlflow-blob --name vm-mlflow-blob --username azureuser --ssh-key-value "$(cat ~/.ssh/id_rsa.pub)"
```

### VM Management (On VM)

```bash
# Find and kill process on port
sudo lsof -ti :5000 | xargs sudo kill -9

# Check if port is in use
sudo lsof -i :5000

# Check disk space (important for Option 1)
df -h

# Check artifact directory size (Option 1)
du -sh ~/mlruns-artifacts/

# View system resources
htop  # or: top
free -h  # memory
```

### MLflow Server Management

**Option 1:**

```bash
# Start server in background
nohup ~/start-mlflow-server.sh > mlflow-server.log 2>&1 &

# Check if server is running
pgrep -f "mlflow server"

# View server logs
tail -f mlflow-server.log

# View last 50 lines of logs
tail -n 50 mlflow-server.log

# Test server health
curl http://localhost:5000/health

# Stop server
pkill -f "mlflow server"
```

**Option 2:**

```bash
# Start server in background
nohup ~/start-mlflow-server-blob.sh > mlflow-server.log 2>&1 &

# Check if server is running
pgrep -f "mlflow server"

# View server logs
tail -f mlflow-server.log

# View last 50 lines of logs
tail -n 50 mlflow-server.log

# Test server health
curl http://localhost:5000/health

# Check environment variables
source ~/.mlflow-env
echo $MLFLOW_DEFAULT_ARTIFACT_ROOT

# Stop server
pkill -f "mlflow server"
```

### PostgreSQL

```bash
# Test connection
export PGPASSWORD="password"
psql -h <HOSTNAME> -U mlflow -d mlflow -c "SELECT version();"

# Check experiment artifact locations
psql "postgresql://mlflow:PASSWORD@HOST:5432/mlflow?sslmode=require" \
  -c "SELECT experiment_id, name, artifact_location FROM experiments;"

# List all experiments
psql "postgresql://mlflow:PASSWORD@HOST:5432/mlflow?sslmode=require" \
  -c "SELECT * FROM experiments ORDER BY creation_time DESC;"

# Check runs count
psql "postgresql://mlflow:PASSWORD@HOST:5432/mlflow?sslmode=require" \
  -c "SELECT experiment_id, COUNT(*) as run_count FROM runs GROUP BY experiment_id;"

# Check Azure firewall rules
az postgres flexible-server firewall-rule list \
  -g rg-mlflow -s <SERVER_NAME> --output table
  # or: -g rg-mlflow-blob -s <SERVER_NAME>
```

## Client Configuration

### Option 1: Local Disk (Simple Setup)

```python
import mlflow

# Set tracking URI
mlflow.set_tracking_uri("http://<VM_IP>:5000")

# Set timeout (optional, for slow connections)
import os
os.environ["MLFLOW_HTTP_REQUEST_TIMEOUT"] = "30"

# Verify connection
print(mlflow.get_tracking_uri())

# List experiments
experiments = mlflow.search_experiments()
```

### Option 2: Blob Storage (Requires .env Configuration)

**Step 1: Create .env file**

```bash
cd /workspaces/mlops-zoomcamp/02-experiment-tracking/running-mlflow-examples
cp env.template .env
```

**Step 2: Edit .env file**

```bash
# .env file contents
MLFLOW_TRACKING_URI=http://<VM_IP>:5000
AZURE_STORAGE_ACCOUNT=stmlflowXXXXX
AZURE_STORAGE_KEY=your_storage_account_key_here
```

**Step 3: Use in Python/Notebook**

```python
import os
import mlflow

# Load .env file
from dotenv import load_dotenv
load_dotenv('.env')

# Set tracking URI
tracking_uri = os.environ.get('MLFLOW_TRACKING_URI', '')
mlflow.set_tracking_uri(tracking_uri)

# Set timeout
os.environ["MLFLOW_HTTP_REQUEST_TIMEOUT"] = "30"

# Build connection string from .env
storage_account = os.environ.get('AZURE_STORAGE_ACCOUNT', '')
storage_key = os.environ.get('AZURE_STORAGE_KEY', '')

if storage_account and storage_key:
    os.environ['AZURE_STORAGE_CONNECTION_STRING'] = \
        f'DefaultEndpointsProtocol=https;AccountName={storage_account};AccountKey={storage_key};EndpointSuffix=core.windows.net'

# Verify connection
print(f"Tracking URI: {mlflow.get_tracking_uri()}")
print(f"Storage configured: {bool(os.environ.get('AZURE_STORAGE_CONNECTION_STRING'))}")
```

## Troubleshooting

### Permission Error on Artifact Upload (Option 1)

**Error:** `PermissionError: [Errno 13] Permission denied: '/home/azureuser'`

**Cause:** Server configured with local paths instead of `mlflow-artifacts:/` URIs

**Solution:**

```bash
# Stop server
pkill -f "mlflow server"

# Update startup script
cat > ~/start-mlflow-server.sh << 'EOF'
#!/bin/bash
export BACKEND_URI="postgresql+psycopg2://mlflow:PASSWORD@HOST:5432/mlflow?sslmode=require"
export PATH="$HOME/.local/bin:$PATH"
export MLFLOW_ALLOWED_HOSTS="*"
export ALLOWED_HOSTS="*"

mlflow server \
  --backend-store-uri "$BACKEND_URI" \
  --default-artifact-root mlflow-artifacts:/ \
  --artifacts-destination /home/azureuser/mlruns-artifacts \
  --host 0.0.0.0 \
  --port 5000 \
  --allowed-hosts "*"
EOF

chmod +x ~/start-mlflow-server.sh
nohup ~/start-mlflow-server.sh > mlflow-server.log 2>&1 &
```

### Authorization Permission Mismatch (Option 2)

**Error:** `HttpResponseError: This request is not authorized to perform this operation using this permission.`

**Cause:** Missing or incorrect Storage Account credentials

**Solution:**

```bash
# Verify .env file exists and has correct values
cat .env

# Check if connection string is set in environment
python3 -c "import os; from dotenv import load_dotenv; load_dotenv('.env'); print('STORAGE_ACCOUNT:', os.environ.get('AZURE_STORAGE_ACCOUNT', 'NOT SET')); print('STORAGE_KEY:', 'SET' if os.environ.get('AZURE_STORAGE_KEY') else 'NOT SET')"

# Rebuild connection string
storage_account="stmlflowXXXXX"
storage_key="your_key"
export AZURE_STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=${storage_account};AccountKey=${storage_key};EndpointSuffix=core.windows.net"

# Test connection
python3 << EOF
from azure.storage.blob import BlobServiceClient
conn_str = "${AZURE_STORAGE_CONNECTION_STRING}"
client = BlobServiceClient.from_connection_string(conn_str)
container = client.get_container_client("mlflow-artifacts")
props = container.get_container_properties()
print("✓ Connection successful!")
EOF
```

### ModuleNotFoundError: azure (Option 2)

**Error:** `ModuleNotFoundError: No module named 'azure'`

**Solution:**

```bash
# Install Azure packages
pip install azure-storage-blob azure-identity

# Or in notebook
import subprocess, sys
subprocess.check_call([sys.executable, "-m", "pip", "install", "azure-storage-blob", "azure-identity", "-q"])
```

### Port Already in Use

```bash
# Find process using port 5000
sudo lsof -i :5000

# Kill it
sudo lsof -ti :5000 | xargs sudo kill -9

# Or use pkill
pkill -9 -f "mlflow"

# Verify port is free
sudo lsof -i :5000  # Should return nothing
```

### Database Connection Failed

```bash
# Test connection manually
export PGPASSWORD="your_password"
psql -h <HOST> -U mlflow -d mlflow -c "SELECT version();"

# Check Azure firewall rules
az postgres flexible-server firewall-rule list \
  -g rg-mlflow -s <SERVER_NAME> --output table
  # or: -g rg-mlflow-blob -s <SERVER_NAME>

# Add firewall rule for VM IP
VM_IP=$(curl -s ifconfig.me)
az postgres flexible-server firewall-rule create \
  -g rg-mlflow \
  -s <SERVER_NAME> \
  -n "allow-vm-ip" \
  --start-ip-address $VM_IP \
  --end-ip-address $VM_IP

# Verify database exists
az postgres flexible-server db show \
  -g rg-mlflow \
  -s <SERVER_NAME> \
  -d mlflow
```

### Invalid Host Header

**Error:** `Invalid Host header` when accessing MLflow UI

**Solution:**

```bash
# Ensure these are in startup script
export MLFLOW_ALLOWED_HOSTS="*"
export ALLOWED_HOSTS="*"

# And in mlflow server command
--allowed-hosts "*"

# Verify in startup script
cat ~/start-mlflow-server.sh | grep allowed
cat ~/start-mlflow-server-blob.sh | grep allowed
```

### Server Unreachable / Timeout

```bash
# Check if server is running
pgrep -f "mlflow server"

# Check server logs
tail -50 mlflow-server.log

# Test from VM
curl -v http://localhost:5000/health

# Test from local machine
curl -v http://<VM_IP>:5000/health

# Check firewall/NSG rules
az network nsg rule list \
  --resource-group rg-mlflow \
  --nsg-name <NSG_NAME> \
  --query "[?destinationPortRanges[0]=='5000']" -o table

# Verify port 5000 is open
az vm show -g rg-mlflow -n vm-mlflow --query networkProfile.networkSecurityGroup
```

### Disk Space Full (Option 1)

```bash
# Check disk usage
df -h

# Check artifact directory size
du -sh ~/mlruns-artifacts/

# Find largest directories
du -h ~/mlruns-artifacts/ | sort -rh | head -10

# Clean up old artifacts (be careful!)
# Option: Archive old runs, then delete
find ~/mlruns-artifacts/ -type f -mtime +30 -delete  # Delete files older than 30 days
```

## Verification Commands

### Python / Notebook

**Option 1:**

```python
import mlflow
import os

# Set tracking URI
mlflow.set_tracking_uri("http://<VM_IP>:5000")
os.environ["MLFLOW_HTTP_REQUEST_TIMEOUT"] = "30"

# Verify URI
print(f"Tracking URI: {mlflow.get_tracking_uri()}")

# Check experiments
experiments = mlflow.search_experiments()
for exp in experiments:
    print(f"{exp.name}: {exp.artifact_location}")
    # Should show: mlflow-artifacts:/...

# Test artifact upload
with mlflow.start_run():
    mlflow.log_param("test", "value")
    mlflow.log_metric("accuracy", 0.95)
    artifact_uri = mlflow.get_artifact_uri()
    print(f"Artifact URI: {artifact_uri}")
    # Should show: mlflow-artifacts:/...
```

**Option 2:**

```python
import os
import mlflow

# Load .env
from dotenv import load_dotenv
load_dotenv('.env')

# Set tracking URI
tracking_uri = os.environ.get('MLFLOW_TRACKING_URI', '')
mlflow.set_tracking_uri(tracking_uri)
os.environ["MLFLOW_HTTP_REQUEST_TIMEOUT"] = "30"

# Verify Storage configuration
storage_account = os.environ.get('AZURE_STORAGE_ACCOUNT', '')
storage_key = os.environ.get('AZURE_STORAGE_KEY', '')

if storage_account and storage_key:
    os.environ['AZURE_STORAGE_CONNECTION_STRING'] = \
        f'DefaultEndpointsProtocol=https;AccountName={storage_account};AccountKey={storage_key};EndpointSuffix=core.windows.net'
    print(f"✓ Storage configured: {storage_account}")

# Verify URI
print(f"Tracking URI: {mlflow.get_tracking_uri()}")

# Check experiments
experiments = mlflow.search_experiments()
for exp in experiments:
    print(f"{exp.name}: {exp.artifact_location}")
    # Should show: wasbs://mlflow-artifacts@...

# Test artifact upload
with mlflow.start_run():
    mlflow.log_param("test", "value")
    mlflow.log_metric("accuracy", 0.95)
    artifact_uri = mlflow.get_artifact_uri()
    print(f"Artifact URI: {artifact_uri}")
    # Should show: wasbs://mlflow-artifacts@...
```

### Shell Commands

```bash
# Check server process
ps aux | grep "mlflow server"

# Verify MLflow version
mlflow --version

# Test HTTP connectivity
curl -s http://<VM_IP>:5000/health
# Expected: {"status":"ok"}

# Check server flags (Option 1)
cat ~/start-mlflow-server.sh

# Check server flags (Option 2)
cat ~/start-mlflow-server-blob.sh
cat ~/.mlflow-env

# Test PostgreSQL connection
export PGPASSWORD="password"
psql -h <HOST> -U mlflow -d mlflow -c "SELECT COUNT(*) FROM experiments;"
```

### Verify Artifact Storage

**Option 1:**

```bash
# On VM, check local artifact directory
ls -lah ~/mlruns-artifacts/
du -sh ~/mlruns-artifacts/

# Check artifact URI in database
psql "postgresql://mlflow:PASSWORD@HOST:5432/mlflow?sslmode=require" \
  -c "SELECT artifact_location FROM runs LIMIT 5;"
# Should show: mlflow-artifacts:/...
```

**Option 2:**

```bash
# Check blob container
az storage blob list \
  --container-name mlflow-artifacts \
  --account-name <STORAGE_ACCOUNT> \
  --account-key <KEY> \
  --auth-mode key \
  --output table

# Count blobs
az storage blob list \
  --container-name mlflow-artifacts \
  --account-name <STORAGE_ACCOUNT> \
  --account-key <KEY> \
  --auth-mode key \
  --query "[].name" -o tsv | wc -l

# Check artifact URI in database
psql "postgresql://mlflow:PASSWORD@HOST:5432/mlflow?sslmode=require" \
  -c "SELECT artifact_location FROM runs LIMIT 5;"
# Should show: wasbs://mlflow-artifacts@...
```

## Key Concepts

### Artifact URI Schemes

| URI Format | Description | Client Behavior | Used In |
|------------|-------------|-----------------|---------|
| `mlflow-artifacts:/` | HTTP proxy scheme | Uploads via HTTP to server | Option 1 |
| `/home/user/mlruns/` | Local file path | ❌ Tries local write → Permission error | ❌ Avoid |
| `wasbs://container@account/path` | Azure Blob Storage | Direct Azure upload (requires credentials) | Option 2 |
| `s3://bucket/path` | AWS S3 storage | Direct S3 upload (requires credentials) | Alternative |

### Server Flags

| Flag | Purpose | Option 1 Example | Option 2 Example |
|------|---------|------------------|------------------|
| `--backend-store-uri` | Database for metadata | `postgresql+psycopg2://...` | `postgresql+psycopg2://...` |
| `--default-artifact-root` | URI scheme for clients | `mlflow-artifacts:/` | `wasbs://mlflow-artifacts@...` |
| `--artifacts-destination` | Where server stores files | `/home/user/mlruns-artifacts` | (Not used) |
| `--host` | Bind address | `0.0.0.0` | `0.0.0.0` |
| `--port` | Listen port | `5000` | `5000` |
| `--allowed-hosts` | Host header validation | `"*"` | `"*"` |

## Quick Start Templates

### Option 1: Local Disk Server Startup Script

```bash
#!/bin/bash
# ~/start-mlflow-server.sh

export BACKEND_URI="postgresql+psycopg2://mlflow:PASSWORD@HOST:5432/mlflow?sslmode=require"
export PATH="$HOME/.local/bin:$PATH"
export MLFLOW_ALLOWED_HOSTS="*"
export ALLOWED_HOSTS="*"

mlflow server \
  --backend-store-uri "$BACKEND_URI" \
  --default-artifact-root mlflow-artifacts:/ \
  --artifacts-destination /home/azureuser/mlruns-artifacts \
  --host 0.0.0.0 \
  --port 5000 \
  --allowed-hosts "*"
```

### Option 2: Blob Storage Server Startup Script

```bash
#!/bin/bash
# ~/start-mlflow-server-blob.sh

# Load environment variables
source ~/.mlflow-env

export PATH="$HOME/.local/bin:$PATH"

mlflow server \
  --backend-store-uri "$MLFLOW_BACKEND_STORE_URI" \
  --default-artifact-root "$MLFLOW_DEFAULT_ARTIFACT_ROOT" \
  --host 0.0.0.0 \
  --port 5000 \
  --allowed-hosts "*"
```

Where `~/.mlflow-env` contains:

```bash
export MLFLOW_BACKEND_STORE_URI="postgresql+psycopg2://mlflow:PASSWORD@HOST:5432/mlflow?sslmode=require"
export AZURE_STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;AccountName=ACCOUNT;AccountKey=KEY;EndpointSuffix=core.windows.net"
export MLFLOW_DEFAULT_ARTIFACT_ROOT="wasbs://mlflow-artifacts@ACCOUNT.blob.core.windows.net/"
export MLFLOW_ALLOWED_HOSTS="*"
export ALLOWED_HOSTS="*"
```

### Client Configuration Template (Option 2)

```python
# notebook_client.py
import os
import mlflow

# Load .env
from dotenv import load_dotenv
load_dotenv('.env')

# Configure tracking
tracking_uri = os.environ.get('MLFLOW_TRACKING_URI', '')
mlflow.set_tracking_uri(tracking_uri)
os.environ["MLFLOW_HTTP_REQUEST_TIMEOUT"] = "30"

# Configure Azure Storage
storage_account = os.environ.get('AZURE_STORAGE_ACCOUNT', '')
storage_key = os.environ.get('AZURE_STORAGE_KEY', '')

if storage_account and storage_key:
    os.environ['AZURE_STORAGE_CONNECTION_STRING'] = \
        f'DefaultEndpointsProtocol=https;AccountName={storage_account};AccountKey={storage_key};EndpointSuffix=core.windows.net'

# Verify
print(f"✓ Tracking URI: {mlflow.get_tracking_uri()}")
print(f"✓ Storage: {storage_account if storage_account else 'Not configured'}")
```

## Environment Variables Reference

### Option 1 (Server-side only)

```bash
BACKEND_URI="postgresql+psycopg2://..."
MLFLOW_ALLOWED_HOSTS="*"
ALLOWED_HOSTS="*"
PATH="$HOME/.local/bin:$PATH"
```

### Option 2 (Server-side)

```bash
MLFLOW_BACKEND_STORE_URI="postgresql+psycopg2://..."
AZURE_STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;..."
MLFLOW_DEFAULT_ARTIFACT_ROOT="wasbs://..."
MLFLOW_ALLOWED_HOSTS="*"
ALLOWED_HOSTS="*"
PATH="$HOME/.local/bin:$PATH"
```

### Option 2 (Client-side .env file)

```bash
MLFLOW_TRACKING_URI="http://<VM_IP>:5000"
AZURE_STORAGE_ACCOUNT="stmlflowXXXXX"
AZURE_STORAGE_KEY="your_key_here"
# Optional: direct connection string
# AZURE_STORAGE_CONNECTION_STRING="DefaultEndpointsProtocol=https;..."
```

## Cost Management

```bash
# Check current resource costs (approximate)
# Option 1: ~$20-25/month (VM + PostgreSQL)
# Option 2: ~$50-65/month (VM + PostgreSQL + Storage Account)

# Stop VM to save costs (you still pay for storage)
az vm deallocate -g rg-mlflow -n vm-mlflow
az vm deallocate -g rg-mlflow-blob -n vm-mlflow-blob

# ⚠️ Important: Option 1 artifacts not accessible when VM stopped!
# Option 2 artifacts remain accessible in Blob Storage

# Check Azure credits balance
az account show --query "properties.availableBalances" -o table

# List all resources to audit
az resource list --resource-group rg-mlflow --query "[].{Name:name, Type:type, Location:location}" -o table
az resource list --resource-group rg-mlflow-blob --query "[].{Name:name, Type:type, Location:location}" -o table
```

## Quick Decision Guide

**Choose Option 1 (Local Disk) if:**
- Learning or experimenting
- Budget limited (~$20-25/month)
- Small artifacts (< 10 GB)
- Don't need artifacts when VM stopped
- Want simplest setup

**Choose Option 2 (Blob Storage) if:**
- Production environment
- Team collaboration needed
- Large artifacts or many models (> 10 GB)
- Need artifacts accessible when VM stopped
- Scalability important
- Can afford ~$50-65/month