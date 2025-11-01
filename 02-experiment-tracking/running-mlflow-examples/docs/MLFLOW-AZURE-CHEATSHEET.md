Quick reference for MLflow server configuration and troubleshooting on Azure.

## Critical MLflow Server Configuration

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
- `--artifacts-destination` - Where server stores artifact files
- Both flags required for proper remote artifact handling

## Common Commands

### Azure CLI

```bash
# Resource management
az group delete -n rg-mlflow --yes --no-wait
az vm deallocate -g rg-mlflow -n vm-mlflow
az vm start -g rg-mlflow -n vm-mlflow

# Get VM IP
az vm show -g rg-mlflow -n vm-mlflow --show-details --query publicIps -o tsv

# Check resource provider
az provider show --namespace Microsoft.DBforPostgreSQL --query "registrationState" -o tsv
```

### SSH & File Transfer

```bash
# Connect to VM
ssh azureuser@<VM_PUBLIC_IP>

# Transfer file to VM
scp setup-mlflow-server.sh azureuser@<VM_PUBLIC_IP>:~/

# Find and kill process on port
sudo lsof -ti :5000 | xargs sudo kill -9

# Check if port is in use
sudo lsof -i :5000
```

### MLflow Server Management

```bash
# Start server in background
nohup ~/start-mlflow-server.sh > mlflow-server.log 2>&1 &

# Check if server is running
pgrep -f "mlflow server"

# View server logs
tail -f mlflow-server.log

# Test server health
curl http://localhost:5000/health

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
```

## Troubleshooting

### Permission Error on Artifact Upload

**Error:** `PermissionError: [Errno 13] Permission denied: '/home/azureuser'`

**Cause:** Server configured with local paths instead of `mlflow-artifacts:/` URIs

**Solution:**

```bash
# Stop server
pkill -f "mlflow server"

# Update startup script to use mlflow-artifacts://
cat > ~/start-mlflow-server.sh << 'EOF'
#!/bin/bash
export BACKEND_URI="postgresql+psycopg2://..."
export PATH="$HOME/.local/bin:$PATH"

mlflow server \
  --backend-store-uri "$BACKEND_URI" \
  --default-artifact-root mlflow-artifacts:/ \
  --artifacts-destination /home/azureuser/mlruns-artifacts \
  --host 0.0.0.0 \
  --port 5000 \
  --allowed-hosts "*"
EOF

chmod +x ~/start-mlflow-server.sh
~/start-mlflow-server.sh > mlflow-server.log 2>&1 &
```

### Port Already in Use

```bash
# Find process using port 5000
sudo lsof -i :5000

# Kill it
sudo lsof -ti :5000 | xargs sudo kill -9

# Or use pkill
pkill -9 -f "mlflow"
```

### Database Connection Failed

```bash
# Test connection manually
psql -h <HOST> -U mlflow -d mlflow

# Check Azure firewall rules
az postgres flexible-server firewall-rule list \
  -g rg-mlflow \
  -s <SERVER_NAME> \
  --output table
```

### Invalid Host Header

```bash
# Ensure these are in startup script
export MLFLOW_ALLOWED_HOSTS="*"
export ALLOWED_HOSTS="*"

# And in mlflow server command
--allowed-hosts "*"
```

## Verification Commands

### Python / Notebook

```python
import mlflow

# Set tracking URI
mlflow.set_tracking_uri("http://<VM_IP>:5000")

# Verify URI
print(mlflow.get_tracking_uri())

# Check experiments
experiments = mlflow.search_experiments()
for exp in experiments:
    print(f"{exp.name}: {exp.artifact_location}")

# Test artifact upload
with mlflow.start_run():
    mlflow.log_param("test", "value")
    mlflow.log_metric("accuracy", 0.95)
    # Artifact URI should be mlflow-artifacts:/
```

### Shell

```bash
# Check server process
ps aux | grep "mlflow server"

# Verify MLflow version
mlflow --version

# Test HTTP connectivity
curl -s http://<VM_IP>:5000/health

# Check server flags
cat ~/start-mlflow-server.sh
```

## Key Concepts

### Artifact URI Schemes

| URI Format | Description | Client Behavior |
|------------|-------------|-----------------|
| `mlflow-artifacts:/` | HTTP proxy scheme | Uploads via HTTP to server |
| `/home/user/mlruns/` | Local file path | ❌ Tries local write → Permission error |
| `s3://bucket/path` | S3 storage | Direct S3 upload (requires credentials) |
| `wasbs://container@account/path` | Azure Blob | Direct Azure upload (requires credentials) |

### Server Flags

| Flag | Purpose | Example |
|------|---------|---------|
| `--backend-store-uri` | Database for metadata | `postgresql+psycopg2://...` |
| `--default-artifact-root` | URI scheme for clients | `mlflow-artifacts:/` or `s3://...` |
| `--artifacts-destination` | Where server stores files | `/home/user/mlruns-artifacts` |
| `--serve-artifacts` | Enable artifact proxy | Default: True |
| `--host` | Bind address | `0.0.0.0` (all interfaces) |
| `--port` | Listen port | `5000` (default) |
| `--allowed-hosts` | Host header validation | `"*"` (allow all) |

## Quick Start Template

```bash
#!/bin/bash
# Complete server startup script

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
