# Azure Blob Storage Setup for MLflow

This guide explains how to set up MLflow with Azure Blob Storage for artifact storage.

## Quick Start

1. **Create your .env file:**
   ```bash
   cp env.template .env
   ```

2. **Edit `.env` with your actual values:**
   ```bash
   # Fill in these fields:
   MLFLOW_TRACKING_URI=http://YOUR_VM_IP:5000
   AZURE_STORAGE_ACCOUNT=your_storage_account_name
   AZURE_STORAGE_KEY=your_storage_account_key
   ```
   
   The connection string will be built automatically from the account name and key.

3. **Run the notebook cells** - they will automatically load from `.env`

## Files

- `env.template` - Template file with all required environment variables
- `.env` - Your actual configuration (create from template, **not committed to git**)
- `setup-azure-resources-blob.sh` - Creates Azure resources (Storage Account, PostgreSQL, VM)
- `setup-mlflow-server-blob.sh` - Sets up MLflow server on the VM with Blob Storage

## Required Environment Variables

### Essential (must be set):
- `MLFLOW_TRACKING_URI` - MLflow server URL (e.g., `http://your_vm_ip:5000`)
- `AZURE_STORAGE_ACCOUNT` - Azure Storage Account name
- `AZURE_STORAGE_KEY` - Azure Storage Account access key

### Optional:
- `POSTGRES_HOST` - PostgreSQL server hostname
- `POSTGRES_USER` - PostgreSQL username
- `POSTGRES_PASSWORD` - PostgreSQL password
- `POSTGRES_DB` - PostgreSQL database name

## Getting Your Connection String

After running `setup-azure-resources-blob.sh`, it will output your connection string. You can also get it:

1. **From Azure Portal:**
   - Go to Storage Account > Access keys
   - Copy the Connection string

2. **From Azure CLI:**
   ```bash
   az storage account show-connection-string \
     --resource-group rg-mlflow-blob \
     --name YOUR_STORAGE_ACCOUNT \
     --query connectionString -o tsv
   ```

## Security Notes

- **Never commit `.env` to git** - it contains sensitive credentials
- `.env` is already in `.gitignore`
- Use Azure Key Vault for production deployments
- Rotate storage account keys regularly

