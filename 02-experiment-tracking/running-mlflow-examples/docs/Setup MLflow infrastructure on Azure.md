Provision the minimum Azure infrastructure to run an **MLflow tracking server** for a team:

* **PostgreSQL** (backend store for experiment metadata & Model Registry)
* **Ubuntu VM** (to host the MLflow server/UI)
* **Networking** (open TCP 5000 for the UI/API)
* All grouped in one **Resource Group** for easy cleanup

| Element | Azure Resource Name | Function and Relationship |
| :---------------------- | :------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Resource Group** | `$RESOURCE_GROUP` (e.g., `rg-mlflow`) | **Container:** Acts as a logical container for all the resources related to this MLflow setup, ensuring they can be managed and deleted together. |
| **MLflow Server** | **Virtual Machine (VM)** (`$VM_NAME`) | **Compute:** This is where the **MLflow Tracking Server** software will be installed and run. It serves two main roles: <br> 1. It hosts the MLflow web UI (accessible via **Port 5000**). <br> 2. It connects to the PostgreSQL server to store run data. |
| **Backend Database** | **PostgreSQL Flexible Server** (`$POSTGRES_SERVER_NAME`) | **Storage:** This server hosts the **`mlflow` database**. It is the central, persistent repository for all MLflow **experiment metadata**, run parameters, metrics, and artifact locations. |
| **Database Connection** | PostgreSQL URI | **Link:** The VM connects to the PostgreSQL server using the provided **Database URI** (which contains the host, database name, user, and password) to read and write tracking data. |
| **Access Port** | NSG rule for **TCP 5000** with **priority 1010** | **Entry Point:** The VM's network security group is configured to allow inbound traffic on this port, enabling external users (like you or your teammates) to access the **MLflow UI** hosted on the VM. |

## Script Header & Safety

* `#!/bin/bash`
	- Tells the system to run the script with Bash.

* `set -e`
	- Exit immediately if any command fails. Prevents partial/half-configured resources.

* **Color output**: The script uses ANSI color codes (`GREEN`, `YELLOW`, `RED`) with `echo -e` to provide visual feedback during execution, making it easier to identify successes, warnings, and errors.

## Configuration Variables

* `RESOURCE_GROUP`, `LOCATION`
	- Where your resources live and how to find/delete them later. A single RG makes lifecycle management (and cost control) easy.
* `POSTGRES_SERVER_NAME`
	- Unique server name for Azure Database for PostgreSQL. Uses `$(date +%s | tail -c 5)` to append a 5-digit timestamp suffix, avoiding name collisions in Azure.
* `VM_NAME`, `POSTGRES_ADMIN_USER`, `VM_ADMIN_USER`
	- Human-readable names for the VM and default admin users. You'll need these for SSH and DB connections.

**Default Values:**
- `RESOURCE_GROUP="rg-mlflow"`
- `LOCATION="southeastasia"`
- `POSTGRES_ADMIN_USER="mlflow"`
- `VM_ADMIN_USER="azureuser"`
- `VM_NAME="vm-mlflow"`

## Resource Provider Validation

**Before creating resources, the script verifies required Azure resource providers are registered:**

```bash
az provider show --namespace Microsoft.DBforPostgreSQL --query "registrationState" -o tsv
az provider show --namespace Microsoft.Compute --query "registrationState" -o tsv
```

* **Why:** Azure requires resource providers to be registered before you can create resources of that type.
* **If not registered:** The script exits with clear instructions to run `az provider register --namespace <PROVIDER> --wait` for:
	- `Microsoft.DBforPostgreSQL`
	- `Microsoft.Compute`
	- `Microsoft.Network`
* **Output:** The script uses `-o tsv` (tab-separated values) to parse the registration state cleanly, with error handling (`|| echo "NotRegistered"`).

## Secure Password Input & Validation

* `read -sp ... POSTGRES_PASSWORD` and `read -sp ... POSTGRES_PASSWORD_CONFIRM`
	- Securely capture the DB admin password without echoing to the terminal (`-s` flag).
	- Prompts twice to confirm the password matches.

* **Validation checks:**
	1. **Match verification**: Compares both password inputs - exits if they don't match to prevent typos.
	2. **Minimum length**: Requires at least 8 characters (`${#POSTGRES_PASSWORD} -lt 8`) to meet Azure's PostgreSQL password requirements.

* **Error handling:** Both validation failures print a clear error message in red and exit immediately (`exit 1`).

**Why:**
- PostgreSQL needs a strong admin password;
- MLflow will connect with these credentials;
- Failing fast on invalid passwords avoids creating resources that would need to be torn down.

## Step 1 - Resource Group

```bash
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output json
```

* A **Resource Group** is the logical container for everything you create.
* **Output format**: Uses `--output json` instead of `--output table` to avoid "Table output unavailable" errors that can occur with some Azure CLI commands when the data structure doesn't match the default table format.
* **Why**: Makes cleanup one command (`az group delete ...`) and keeps billing/auditing tidy.

## Step 2 - PostgreSQL Flexible Server

```bash
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
```

* Creates a **managed Postgres** (Flexible Server) with a small, cost-friendly SKU.
* **Why Postgres?** MLflow's Model Registry and tracking metadata require a **database-backed backend store** for robust, concurrent access.
* **Burstable B1ms**: cheapest practical tier for students/small teams (~$15-20/month).
* **Storage**: 32 GB (sufficient for metadata and small to medium teams).
* **Public access all** (0.0.0.0-255.255.255.255): simplest connectivity for demos. In production, restrict to your VM's IP or VNet for security.
* **Version 14**: a stable Postgres version commonly supported by clients.
* **Output format**: Uses `--output json` for reliable output parsing and to avoid table format errors.

## Step 3 - Database Creation

```bash
az postgres flexible-server db create \
  --resource-group "$RESOURCE_GROUP" \
  --server-name "$POSTGRES_SERVER_NAME" \
  --database-name mlflow \
  --output json
```

* Creates the **database schema** (`mlflow`) inside the PostgreSQL server.
* **Why**: MLflow expects a concrete database (not just the server) to write its tracking tables. Without this step, the MLflow server setup would fail when trying to connect.
* **Database name**: Fixed as `mlflow` - this is what MLflow expects by default, though it can be configured differently.
* **Output format**: Uses `--output json` for consistency with other commands.

## Step 4 - Ubuntu VM

```bash
az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --image Ubuntu2204 \
  --size Standard_D2s_v3 \
  --admin-username "$VM_ADMIN_USER" \
  --generate-ssh-keys \
  --public-ip-sku Standard \
  --output json
```

* Provisions the **compute host** for the MLflow server/UI.
* **Ubuntu 22.04**: stable LTS, widely supported, with long-term security updates.
* **D2s_v3** size: General purpose VM with better performance (~$40-50/month when running).
	- 2 vCPU, 8 GB RAM - good performance for MLflow tracking server and concurrent requests
	- Standard performance tier with Premium SSD storage - consistent performance for production workloads
* **SSH keys**: `--generate-ssh-keys` creates SSH key pairs in `~/.ssh/` if they don't exist. **Note**: Keys generated here are stored in Azure, so you may need to add your local SSH key separately for access (see troubleshooting).
* **Public IP**: `--public-ip-sku Standard` provides a static public IP address that can be accessed from anywhere (important for team access).
* **Output format**: Uses `--output json` for reliable output parsing.

**Why a VM?** MLflow's open-source server is a simple Python web app; a small VM is enough and easy to manage without requiring container orchestration or serverless infrastructure.

## Step 5 - Open MLflow Port

```bash
az vm open-port \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --port 5000 \
  --priority 1010 \
  --output json
```

* Adds a Network Security Group (NSG) rule to allow inbound TCP traffic on port **5000**.
* **Priority 1010**: Deliberately set higher than the default SSH rule (priority 1000) to avoid conflicts. Azure NSG rules must have unique priorities within the same direction (inbound), and using 1000 would conflict with the auto-generated SSH rule, causing a "SecurityRuleConflict" error.
* **Why port 5000**: MLflow's default UI/API port is 5000; without this NSG rule, the web UI and API would be unreachable from the internet.
* **Output format**: Uses `--output json` for consistency.

**Production considerations:**
- Consider using a reverse proxy (nginx/Apache) with TLS on ports 80/443
- Restrict source IPs to your team's IP addresses instead of allowing all (0.0.0.0/0)
- Use Azure Application Gateway or Azure Front Door for additional security layers

```ad-note

### How Azure NSG priorities work

In Azure Network Security Groups:

* **Lower numbers = higher precedence.**
* **Priorities must be unique** within inbound or outbound rules.
* Each rule is processed **in ascending order of priority** — the **first match wins**.

So:

* A rule with **priority 100** is evaluated *before* a rule with **priority 200**.
* Azure reserves **100–4096** as the valid priority range.

### Why not set it *lower* than 1000?

The **default SSH rule** that allows port 22 uses **priority 1000** and is evaluated early to ensure you can connect to the VM.

If you added your MLflow port rule with a **lower priority** (e.g., 900):

* It would be evaluated **before** the SSH rule.
* It could **override** or **interfere** with SSH access depending on other rules (for example, a “deny all” rule placed afterward might block SSH inadvertently).
* It’s considered **bad practice** to insert custom rules *above* default system rules unless you intend to change security behavior.

### Why 1010 is safe and intentional

* **1010 > 1000**, so it comes *after* SSH in the rule evaluation order.
* It avoids **priority collisions** with the default SSH rule.
* It’s **close enough** to the default to stay logically grouped with similar inbound “allow” rules.
* Keeps the setup **clean and predictable** for troubleshooting and auditing.


✅ **In short:**

> Using **priority 1010** keeps your SSH rule untouched and ensures the new MLflow port rule coexists safely, avoiding both functional conflicts and Azure’s `SecurityRuleConflict` error.
```

## Summary & Outputs

The script retrieves and displays all critical connection information needed for the next steps:

### VM IP Address Retrieval

```bash
VM_IP=$(az vm show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --show-details \
  --query publicIps \
  --output tsv)
```

* Uses `--show-details` to ensure the public IP is included in the output.
* Extracts only the IP address using `--query publicIps -o tsv` (tab-separated value output for clean parsing).

### PostgreSQL Hostname Construction

```bash
POSTGRES_HOST="${POSTGRES_SERVER_NAME}.postgres.database.azure.com"
```

* Builds the fully qualified domain name (FQDN) required for PostgreSQL connections.
* Format: `<server-name>.postgres.database.azure.com`

### Displayed Information

The script outputs (in colored text for clarity):

1. **Resource Details:**
	- Resource Group name
	- PostgreSQL server FQDN
	- Database name (`mlflow`)
	- Database username (`mlflow`)
	- VM name
	- VM public IP address

2. **Next Steps Instructions:**
	- SSH command with the exact IP address
	- PostgreSQL connection URI (ready to use)

3. **PostgreSQL Connection String:**

	```bash
	postgresql+psycopg2://<USER>:<PASSWORD>@<HOST>:5432/mlflow
	```

	- Includes the `psycopg2` driver specification required by MLflow
	- Uses the exact credentials entered during script execution

4. **Cost Management Tips:**
	- Approximate monthly costs (~$20-25/month for both resources)
	- Commands to check Azure credits
	- Commands to stop/deallocate resources when not in use
	- Command to delete all resources for cleanup

**⚠️ Important:** The script explicitly reminds users to "Save these details securely" - these credentials are only shown once and are required for all subsequent steps.

**Next Steps**: Follow the guide to install and configure MLflow server on the Azure VM:
	* SSH into the VM using the displayed IP address.
	* Transfer and run the MLflow setup script on the VM.
	* Use the printed PostgreSQL connection string to configure MLflow's backend store.
	* Access the MLflow UI via the VM's public IP on port **5000**.
