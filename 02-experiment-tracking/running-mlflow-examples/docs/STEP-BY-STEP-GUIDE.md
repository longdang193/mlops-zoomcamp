```
[LOCAL] Preparation
       │
       ▼
[LOCAL] setup-azure-resources.sh  →  [Azure Cloud Resources Created]
       │
       ▼
[LOCAL] SSH  →  [VM]
       │
       ▼
[VM] setup-mlflow-server.sh  →  [MLflow Server Running]
       │
       ▼
[LOCAL / Notebook] Connect to MLflow via http://<VM_IP>:5000
```

## Pre-flight & Preparation Phase

This section ensures your local machine is ready to interact with Azure and the VM.

- For in-depth explanation of the infrastructure setup script, see: **[[Setup MLflow infrastructure on Azure|docs/Setup MLflow infrastructure on Azure]]**
- For detailed explanation of the MLflow server configuration script, see: **[[Install and configure MLflow server on Azure VM|docs/Install and configure MLflow server on Azure VM]]**

### Prerequisites

You need the following three tools:

* **Azure Account**: Provides the resources (VM, DB).
* **Azure CLI**: The command-line interface to create and manage Azure resources.
	* **Verification**: Run `az --version` to check.
	* **Authentication**: Use `az login` and confirm the correct subscription with `az account show`.
* **SSH Client & Key Pair**: Required to remotely access the Ubuntu VM.
	* **Key Check**: Ensure you have `~/.ssh/id_rsa` (private) and `~/.ssh/id_rsa.pub` (public). The Azure CLI handles key usage and generation for you.

### Key Context & Best Practices

| Context | Clarification | Action Context |
| :--- | :--- | :--- |
| **Command Context** | **Crucial:** Pay close attention to whether the command should be run on your **Local Machine (`[LOCAL]`)** to interact with Azure, or **Inside the VM (`[VM]`)** to configure the software. | `[LOCAL]` vs. `[VM]` tags are non-negotiable. |
| **Credentials** | **Save Immediately:** The PostgreSQL password, VM Public IP, and PostgreSQL Hostname are generated only once and are needed for steps 3, 5, and 7. | Treat these details as sensitive and critical. |
| **Port Priority** | Port **5000** for MLflow is opened with priority **1010**. This is a deliberate choice to ensure it doesn't conflict with or supersede standard ports like SSH (usually around 1000). | This ensures both remote management and MLflow access function correctly. |

## Step 1 - Verify Prerequisites

```
[LOCAL]
   │
   ├─► Run setup-azure-resources.sh
   │      • Creates Azure Resource Group
   │      • Creates PostgreSQL Flexible Server + DB
   │      • Creates Ubuntu VM
   │      • Opens Port 5000 (priority 1010)
   │
   ▼
Azure Cloud
   ├─► Resource Group: rg-mlflow
   ├─► PostgreSQL Server: pg-mlflow-XXXX.postgres.database.azure.com
   └─► VM: vm-mlflow (Ubuntu)
```

### Check Azure CLI Installation

```bash
az --version
```

If not installed:

* **Linux**: `curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash`
* **macOS**: `brew install azure-cli`
* **Windows**: Download from [https://aka.ms/installazurecliwindows](https://aka.ms/installazurecliwindows)

### Login and Verify Subscription

```bash
az login
az account show
```

If you have multiple subscriptions:

```bash
az account list --output json
az account set --subscription "Your Subscription Name"
```

> Use `--output json` to avoid “Table output unavailable” errors.

## Step 2 - Create Azure Resources

> See **[[Setup MLflow infrastructure on Azure|docs/Setup MLflow infrastructure on Azure]]** for a detailed breakdown of each command, why resources are created, and how they connect.

**`[LOCAL]`** Navigate to the project directory:

```bash
cd /workspaces/mlops-zoomcamp/02-experiment-tracking/running-mlflow-examples
```

**`[LOCAL]`** Run the setup script:

```bash
./setup-azure-resources.sh
```

### Script Actions

* Prompts for PostgreSQL password (min 8 characters)
* Creates:
	* Resource group: `rg-mlflow`
	* PostgreSQL Flexible Server (B1ms)
	* PostgreSQL database: `mlflow`
	* Ubuntu VM (D2s_v3)
	* Opens port 5000 (priority 1010)

### Save Output

You’ll need:

* VM public IP (e.g., `52.187.41.215`)
* PostgreSQL hostname (e.g., `pg-mlflow-1234.postgres.database.azure.com`)
* Username: `mlflow`
* Password: your chosen password
* Database: `mlflow`

**Expected time:** ~5-10 minutes

If the database isn’t created:

```bash
az postgres flexible-server db create --resource-group rg-mlflow --server-name <SERVER_NAME> --database-name mlflow
```

## Step 3 - Connect to the VM via SSH

```
┌──────────────────────────┐       SSH Connection       ┌────────────────────────────┐
│  Local Machine [LOCAL]   │  ───────────────────────►  │  Azure VM [VM] (Ubuntu)   │
│  ssh azureuser@<IP>      │                           │  azureuser@vm-mlflow:~$   │
└──────────────────────────┘                           └────────────────────────────┘
```

**Run on Local Machine (`[LOCAL]`) and Inside the VM (`[VM]`)**

```bash
ssh azureuser@<VM_PUBLIC_IP>
```

Example:

```bash
ssh azureuser@52.187.41.215
```

If you get `"Permission denied (publickey)"`, add your SSH key:

```bash
az vm user update --resource-group rg-mlflow --name vm-mlflow --username azureuser --ssh-key-value "$(cat ~/.ssh/id_rsa.pub)"
```

Wait 30-60 seconds, then try SSH again.

Once connected, your prompt should look like:

```
azureuser@vm-mlflow:~$
```

## Step 4 - Transfer MLflow Setup Script to VM

This step bridges the gap between the infrastructure creation (done by the first script on your local machine) and the software installation (done by the second script *inside* the VM). You need to move the file **`setup-mlflow-server.sh`** from your computer to the newly created Azure VM.

```
┌──────────────────────────────┐
│  Local Machine [LOCAL]       │
│  scp setup-mlflow-server.sh  │
└──────────────┬───────────────┘
               │ (File Transfer via SCP)
               ▼
┌──────────────────────────────┐
│  Azure VM [VM]               │
│  chmod +x setup-mlflow-server.sh │
│  ./setup-mlflow-server.sh         │
└──────────────────────────────┘
```

### Option A - File Transfer Method: SCP (Recommended)

- **SCP (Secure Copy Protocol)** is the standard, secure way to transfer files between two machines over an SSH connection.
- Keep your SSH session open. Open a new terminal window for file transfer.

| Command Context | Command | Purpose and Rationale |
| :-------------- | :------------------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`[LOCAL]`** | `scp setup-mlflow-server.sh azureuser@<VM_PUBLIC_IP>:~/` | **Transfer:** This command copies the local file (`setup-mlflow-server.sh`) to the remote VM. <br> - It uses your **SSH credentials** (key pair) for secure authentication. <br> - `azureuser` is the admin username on the VM. <br> - `~/` specifies the file should be placed in the home directory of `azureuser`. |
| **`[VM]`** | `ls -la setup-mlflow-server.sh` | **Verification:** After the transfer, you run this *inside the VM* to confirm the file has arrived and check its permissions (list details, including size and ownership). |
| **`[VM]`** | `chmod +x setup-mlflow-server.sh` | **Permission:** This is **critical**. It changes the file's mode to **make it executable**. Without the `+x` (execute) permission, the shell cannot run the script, and you would receive a "Permission denied" error when trying to run `./setup-mlflow-server.sh`. |

**`[LOCAL]`** In a NEW terminal window (keep SSH session open), transfer the script:

```bash
cd /workspaces/mlops-zoomcamp/02-experiment-tracking/running-mlflow-examples
scp setup-mlflow-server.sh azureuser@<VM_PUBLIC_IP>:~/
```

Example:

```bash
scp setup-mlflow-server.sh azureuser@52.187.41.215:~/`
```

**`[VM]`** Back in your SSH session, verify the script arrived:

```bash
ls -la setup-mlflow-server.sh
chmod +x setup-mlflow-server.sh
```

### Option B - Manual Copy

This option is used if `scp` is unavailable or if you prefer a simpler text transfer.

| Command Context | Command | Purpose and Rationale |
| :--- | :--- | :--- |
| **`[LOCAL]`** | `cat setup-mlflow-server.sh` | **Display:** This command prints the entire contents of the script file to your local terminal screen. |
| **`[VM]`** | `nano setup-mlflow-server.sh` | **Creation:** You open the `nano` text editor *inside the VM* to create a new file with the same name. You then manually **paste** the contents displayed by the `cat` command. |
| **`[VM]`** | `chmod +x setup-mlflow-server.sh` | **Permission:** Just as with SCP, this final step is necessary to enable the script to be run in **Step 5**. |

## Step 5 - Run MLflow Setup on the VM

> See **[[Install and configure MLflow server on Azure VM|docs/Install and configure MLflow server on Azure VM]]** for a comprehensive explanation of each step, including system preparation, package installation, database connectivity checks, and the MLflow server startup script generation.

This is the execution phase where you run the configuration script inside the Virtual Machine. This script uses the connection details you provide to configure and install the MLflow server software.

### Execution and Required Inputs

**Action:** Execute the script **inside the VM (`[VM]`)**:

```bash
./setup-mlflow-server.sh
```

The script will immediately pause and prompt you for the details needed to build the complete connection URI for the database:

| Input Field | Source of Value | Purpose |
| :--- | :--- | :--- |
| **PostgreSQL host** | Saved from **Step 2** output | The public address of the Azure Database. |
| **PostgreSQL user** | `mlflow` (Default) | The administrator username for the database. |
| **Password** | Saved from **Step 2** input | The password for the `mlflow` user (hidden for security). |
| **Database** | `mlflow` (Default) | The name of the specific database MLflow will use for metadata. |

### What the Script Performs

Once the inputs are gathered, the script executes the following essential tasks, ensuring the VM is ready to run the MLflow service:

* **System and Python Prep:** It first completes the system preparation, which involves:
	* Updating system packages.
	* Installing **Python 3**, **pip**, and the **PostgreSQL client (`psql`)**.
	* Installing the Python packages: **`mlflow`** (the server) and **`psycopg2-binary`** (the database driver).
* **Startup Script Creation:** It generates the executable file `~/start-mlflow-server.sh`. This script contains the permanent MLflow server command, using your provided inputs to construct the final, secure **Backend URI**.
	* It hardcodes crucial flags like `--allowed-hosts "*"` to prevent the common **"Invalid Host header"** error when accessing the UI via the VM's public IP.
	* It sets **`--default-artifact-root mlflow-artifacts:/`** to enable HTTP artifact proxying and prevent permission errors when logging artifacts.
	* It sets the access point to **Port 5000**.
* **Connection Sanity Check:** It performs a critical pre-flight test. It uses the installed **PostgreSQL client (`psql`)** and your credentials to attempt a simple query against the Azure database.

### Troubleshooting the Connection Failure

The final sanity check is the most likely point of failure. If the script reports that the database connection has failed, the issue is **external to the MLflow software**. You must verify the three following points:

1. **Database Existence:** Confirm the Azure database server and the **`mlflow` database** were created successfully in **Step 2**.
2. **Credentials:** Double-check that the **hostname**, **username**, and **password** you typed into the prompts are exactly correct.
3. **Firewall/Networking:** This is often the culprit. The connection failure indicates that the Azure network (either the **PostgreSQL server's firewall** or the **VM's NSG**) is blocking the traffic. The troubleshooting command to manually test this is:

	```bash
	psql -h <HOSTNAME> -U mlflow -d mlflow
	```

	- If this command fails, you need to go back and ensure the PostgreSQL server's firewall rules allow traffic from the VM's public IP address.

## Step 6 - Start MLflow Server

**Run Inside the VM (`[VM]`)**

* **Action**: Use `nohup ~/start-mlflow-server.sh > mlflow-server.log 2>&1 &` to run the server **in the background** and keep it running even after you disconnect your SSH session.
* **Verification**: Check the server status with `curl http://localhost:5000/health` (expected output: `{"status":"ok"}`).

## Step 7 & 8: Connect and Access

These steps confirm **external connectivity** from your local environment to the running MLflow service on the Azure VM.

### Step 7: Connect from a Data Science Notebook

This demonstrates how a **remote MLflow client** (like a Jupyter notebook on your local machine) connects to the Tracking Server.

* **Setup**: In your Python environment, you define the public address of the server.
* **Action**: `mlflow.set_tracking_uri(f"http://{TRACKING_SERVER_HOST}:5000")` sets the destination for all experiment logs.
* **Verification**: `mlflow.search_experiments()` attempts to query the list of experiments from the server, confirming that the client can communicate through your local network, the internet, and the Azure NSG firewall.

### Step 8: Access MLflow UI (Browser)

This provides the direct user interface access. This action is performed on your **Local Machine (`[LOCAL]`)**.

* **Access Point**: Open your web browser and navigate to the VM's Public IP address on Port 5000: `http://<VM_PUBLIC_IP>:5000`. This confirms the NSG rule for port 5000 is working.

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
| ------------------------------ | --------------------------------- | ---------------------------------------------- |
| **"Table output unavailable"** | Using `--output table` | Use `--output json` |
| **SSH denied** | Missing SSH key | Add with `az vm user update …` |
| **DB connection fails** | DB missing or wrong credentials | Create DB manually, verify password |
| **UI connection refused** | Server not running / port closed | Check with `ps aux` and Azure port 5000 |
| **Invalid Host header** | Missing host flag | Ensure `--allowed-hosts "*"` in startup script |
| **Setup script stops early** | Empty hostname or connection fail | Run with `bash -x ./setup-mlflow-server.sh` |
| **PermissionError: [Errno 13] Permission denied: '/home/azureuser'** | Incorrect MLflow server config | See "Artifact Upload Issues" section below ⚠️ |

### Artifact Upload Issues

**Symptom:** When trying to log artifacts or models, you get:

```
PermissionError: [Errno 13] Permission denied: '/home/azureuser'
```

**Root Cause:** The MLflow server is configured to return **local file paths** instead of HTTP proxy URIs, causing the client to attempt local file operations.

**The Fix:** The `setup-mlflow-server.sh` script now includes the correct configuration:

```bash
mlflow server \
  --default-artifact-root mlflow-artifacts:/ \  ← ⚠️ CRITICAL
  --artifacts-destination /home/azureuser/mlruns-artifacts \
  --backend-store-uri "$BACKEND_URI" \
  --host 0.0.0.0 \
  --port 5000 \
  --allowed-hosts "*"
```

**Key Points:**

1. **`--default-artifact-root mlflow-artifacts:/`** - This tells the server to return `mlflow-artifacts:/` URIs instead of local paths
	- Without this, server returns: `/home/azureuser/mlruns-artifacts/3/abc/artifacts`
	- With this, server returns: `mlflow-artifacts:/3/abc/artifacts`
	- The client then uses HTTP proxy instead of trying local file operations

2. **`--artifacts-destination /home/azureuser/mlruns-artifacts`** - This tells the server WHERE to store the actual files
	- Both flags are required for proper operation

```ad-note
You need **both** because:

* One tells **clients how to talk** to the server (`mlflow-artifacts:/` = “send via API”).
* The other tells **the server where to put** the received files (`/home/azureuser/mlruns-artifacts` = “store here”).

That combination fully decouples client and server filesystems — fixing the `/home/azureuser` `PermissionError`.
```

**If You Already Ran the Setup Script (Before the Fix):**

You need to update the server configuration:

**`[VM]`** SSH into your VM and run:

```bash
# Stop the current server
pkill -f "mlflow server"

# Read your backend URI (don't lose this!)
grep BACKEND_URI ~/start-mlflow-server.sh

# Update the startup script with correct config
cat > ~/start-mlflow-server.sh << 'EOF'
#!/bin/bash
export BACKEND_URI="postgresql+psycopg2://mlflow:YOUR_PASSWORD@YOUR_HOST:5432/mlflow?sslmode=require"
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

# Start the server
nohup ~/start-mlflow-server.sh > mlflow-server.log 2>&1 &

# Verify it's running
sleep 5
curl -s http://localhost:5000/health
```

**Verification:** Create a new experiment and test artifact upload. You should see artifact URIs like `mlflow-artifacts:/` instead of `/home/azureuser/`.

### PostgreSQL Access

Ensure firewall allows all IPs and credentials are correct.

### VM Errors

Check status in Azure Portal, verify credits, or restart:

```bash
az vm restart -g rg-mlflow -n vm-mlflow
```

## Manage Costs

Stop VM when not in use:

```bash
az vm deallocate -g rg-mlflow -n vm-mlflow
```

Restart later:

```bash
az vm start -g rg-mlflow -n vm-mlflow
```

Check new IP (it may change):

```bash
az vm show -g rg-mlflow -n vm-mlflow --show-details --query publicIps -o tsv
```

Delete resources when finished:

```bash
az group delete -n rg-mlflow --yes --no-wait
```

> The MLflow server won’t auto-start after VM restart. Run again:

```bash
nohup ~/start-mlflow-server.sh > mlflow-server.log 2>&1 &
```

## Next Steps

After successful setup:

1. Train and log models with MLflow
2. Register models in the Model Registry
3. Monitor experiments in the MLflow UI
4. Deallocate or delete the VM when idle to save costs
