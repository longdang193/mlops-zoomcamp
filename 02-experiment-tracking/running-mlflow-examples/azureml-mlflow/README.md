# MLflow with Azure Machine Learning

This folder contains a simplified setup for using MLflow with Azure Machine Learning (Azure ML), which is much easier than the VM-based approach.

## Why Azure ML?

✅ **No infrastructure management** - Fully managed service  
✅ **Automatic MLflow integration** - Built-in tracking  
✅ **Simple authentication** - Uses Azure credentials  
✅ **Enterprise features** - Model registry, deployments, RBAC  
✅ **Cost-effective** - Pay only for compute, not infrastructure  

## Quick Start

### 1. Create Azure ML Workspace

```bash
./setup-azureml-workspace.sh
```

This creates:
- Resource Group: `rg-azureml-mlflow`
- Azure ML Workspace: `aml-mlflow-XXXXX`
- Automatic storage and MLflow tracking endpoint

### 2. Authenticate

```bash
az login
```

### 3. Get Workspace Details

```bash
# Get subscription ID
az account show --query id -o tsv

# List workspaces
az ml workspace list -g rg-azureml-mlflow --query "[].name" -o table
```

### 4. Configure Environment

```bash
cp env.template .env
# Edit .env with your subscription ID and workspace name
```

### 5. Install Packages

```bash
pip install azure-ai-ml azure-identity azureml-mlflow
```

### 6. Run Notebook

Open `scenario-azureml.ipynb` and run the cells in order.

## Comparison with VM Setup

| Feature | VM Setup | Azure ML |
|---------|----------|----------|
| **Setup Time** | 30-60 min | 5-10 min |
| **Infrastructure** | Manual | Managed |
| **MLflow Server** | Manual install | Built-in |
| **Authentication** | Storage keys | Azure credentials |
| **Cost** | ~$20-65/month | ~$0-15/month |
| **Maintenance** | Manual | Zero |

## Architecture

```
┌─────────────────────────────────────┐
│   Your Local Machine / Notebook     │
│   ┌───────────────────────────────┐ │
│   │  MLflow Client                │ │
│   │  └─► azureml-mlflow           │ │
│   └───────────────────────────────┘ │
└──────────────┬──────────────────────┘
               │ Azure ML API
               │ (automatic auth)
               ▼
┌─────────────────────────────────────┐
│   Azure Machine Learning Workspace  │
│   ├─► MLflow Tracking (built-in)   │
│   ├─► Artifact Storage             │
│   ├─► Model Registry               │
│   └─► Experiment Management        │
└─────────────────────────────────────┘
```

## Cost

- **Workspace**: Free (no cost for the workspace itself)
- **Storage**: ~$0.018/GB/month (for artifacts)
- **Compute**: Only pay when running training jobs (not for tracking)

## Cleanup

```bash
# Delete workspace and resources
az group delete -n rg-azureml-mlflow --yes --no-wait
```

## Next Steps

- View experiments in Azure ML Studio UI
- Deploy models using Azure ML endpoints
- Set up CI/CD pipelines with Azure ML
- Use Azure ML compute for training jobs

