
[[Setup MLflow infrastructure on Azure|docs/Setup MLflow infrastructure on Azure]]

## Script Header & Safety

* `#!/bin/bash` - Tells the system to run the script with Bash.
* `set -e` - Exit immediately if any command fails. Prevents partial/half-configured installations.
* **Color output**: The script uses ANSI color codes (`GREEN`, `YELLOW`, `RED`) with `echo -e` to provide visual feedback during execution, making it easier to identify successes, warnings, and errors.

## Interactive Configuration & Variables

```bash
read -p "PostgreSQL host (e.g., pg-mlflow-1234.postgres.database.azure.com): " POSTGRES_HOST
read -p "PostgreSQL user [mlflow]: " POSTGRES_USER
POSTGRES_USER=${POSTGRES_USER:-mlflow}
read -sp "PostgreSQL password: " POSTGRES_PASSWORD
echo ""
read -p "PostgreSQL database [mlflow]: " POSTGRES_DB
POSTGRES_DB=${POSTGRES_DB:-mlflow}
ARTIFACT_ROOT="/home/$(whoami)/mlruns-artifacts"
```

| Section              | Code Snippet                                                                  | Purpose & Impact                                                                                                                                                                                                                                                                                       |
| :------------------- | :---------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Database Details** | `read -p "PostgreSQL host ..."` `read -sp "PostgreSQL password:"`             | **Collects Connection Info:** Gathers the necessary credentials (Host, User, Password, DB Name) for the MLflow server to connect to the **PostgreSQL Flexible Server** provisioned previously. The host prompt includes an example format for clarity.                                                 |
| **Defaulting**       | `POSTGRES_USER=${POSTGRES_USER:-mlflow}` `POSTGRES_DB=${POSTGRES_DB:-mlflow}` | **Convenience:** Sets default values (`mlflow`) if the user presses Enter without typing an input. This uses bash parameter expansion: `${VAR:-default}` returns `default` if `VAR` is unset or empty.                                                                                                 |
| **Password Input**   | `read -sp "..." POSTGRES_PASSWORD` followed by `echo ""`                      | **Security:** The `-s` flag suppresses echo (password won't show on screen). The `echo ""` adds a blank line after password entry for better UX.                                                                                                                                                       |
| **Artifact Root**    | `ARTIFACT_ROOT="/home/$(whoami)/mlruns-artifacts"`                 | **Artifact Location:** Defines the directory on the **local VM disk** where the MLflow server will save artifact files (models, plots, data). This is used as the destination for artifacts when clients upload via HTTP. Uses `$(whoami)` to dynamically determine the current user's home directory. |

## System Preparation (Inside the VM)

### Step 1: System Update

```bash
sudo apt update && sudo apt upgrade -y
```

* Updates package lists and upgrades all installed packages to their latest versions.
* **Why:** Ensures the system has the latest security patches and package versions before installing new software.
* **Color feedback:** The script displays this step with a yellow warning color (`${YELLOW}...${NC}`) to indicate it's in progress.

### Step 2: Core Dependencies Installation

```bash
sudo apt install -y python3 python3-pip python3-venv postgresql-client
```

* Installs essential packages:
	* **Python 3** - The Python interpreter required to run MLflow. MLflow is a Python application.
	* **pip** (`python3-pip`) - Python's package installer, required to install MLflow and its dependencies.
	* **python3-venv** - Virtual environment support (installed for completeness, though this script uses `--user` installs).
	* **postgresql-client** - Provides the `psql` command-line tool. While not strictly needed for MLflow itself to run, it is **vital for the Sanity Check** step, allowing the script to test the database connection and firewall rules *before* attempting to start the MLflow server.
* The `-y` flag automatically answers "yes" to prompts, enabling non-interactive installation.
* **Color feedback:** Displayed with yellow to show progress.

### Step 3: Python Packages Installation

Once Python is available, the script installs the specific libraries MLflow requires:

```bash
pip3 install --user mlflow psycopg2-binary
```

* **mlflow** - The MLflow tracking server package, which includes the `mlflow server` command and all MLflow client libraries.
* **psycopg2-binary** - PostgreSQL database driver for Python. MLflow uses this to connect to the PostgreSQL backend store. The `-binary` version includes pre-compiled binaries, avoiding the need for PostgreSQL development libraries on the system.
* `--user` flag:
	* Avoids needing `sudo` (superuser/administrator privileges).
	* Installs packages into `~/.local/lib/python3.x/site-packages/` and executables into `~/.local/bin/`.
	* Treats the MLflow server installation as a user-level application rather than a critical system component.
	* **Note:** This requires adding `~/.local/bin` to the PATH (handled in the next step).
* **Color feedback:** Displayed with yellow to show installation progress.

### Ensure MLflow is on PATH

```bash
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/.local/bin:$PATH"
fi
```

The use of the `--user` flag necessitates a PATH adjustment:

* **Conditional check:** Uses `grep -q` to silently check if `$HOME/.local/bin` is already in the `$PATH` environment variable. The `-q` flag makes grep quiet (no output), and the `!` negates the condition.
* **Persistence:** If missing, the script adds `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc` to make the change permanent for future shell sessions.
* **Immediate effect:** The `export PATH="$HOME/.local/bin:$PATH"` command applies the change to the current shell session immediately, so the script can use `mlflow` commands in subsequent steps.
* **Why:** This ensures that the user can run the `mlflow` command directly from any directory without specifying the full path (`~/.local/bin/mlflow`).

### Step 4: Prepare Artifacts Folder

```bash
mkdir -p "$ARTIFACT_ROOT"
```

* **Purpose:** Creates the local artifact directory MLflow will write to (if it doesn't exist).
* **Flag explanation:** The `-p` flag means:
	* Create parent directories as needed
	* Do not error if the directory already exists
* **Location:** Uses the `ARTIFACT_ROOT` variable defined earlier, which defaults to `/home/<username>/mlruns-artifacts`.
* **Color feedback:** This step is shown with yellow text to indicate setup progress.

## Sanity Check: DB Connectivity

```bash
export PGPASSWORD="$POSTGRES_PASSWORD"
if psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT version();" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Database connection successful!${NC}"
else
    echo -e "${RED}✗ Database connection failed. Check credentials or firewall rules.${NC}"
    exit 1
fi
unset PGPASSWORD
```

* **Purpose:** Validates that the VM can **reach and authenticate** to PostgreSQL **before** attempting to start MLflow. This is a critical pre-flight check.
* **Connection method:** Uses `PGPASSWORD` environment variable to provide the password non-interactively, avoiding prompts.
* **Output suppression:** The `> /dev/null 2>&1` redirects both stdout and stderr to `/dev/null`, silencing the actual query output. Only the success/failure status matters here.
* **Conditional logic:**
	* **Success case:** Prints a green checkmark message (`✓ Database connection successful!`) if the connection succeeds.
	* **Failure case:** Prints a red error message (`✗ Database connection failed...`) and exits with code 1, preventing the script from continuing with a broken configuration.
* **Cleanup:** `unset PGPASSWORD` removes the password from the environment for security after the test.
* **Error handling:** Because the script uses `set -e`, the `exit 1` on failure ensures the script stops immediately, preventing partial setup.
* **Why it matters:** If this fails, you know immediately to check:
	* Database credentials (username, password, hostname)
	* PostgreSQL firewall rules (must allow VM's IP)
	* Network connectivity between VM and PostgreSQL server

## MLflow Server Startup Script Generation

```bash
cat > ~/start-mlflow-server.sh << EOF
#!/bin/bash
# Start MLflow server

export BACKEND_URI="postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:5432/${POSTGRES_DB}?sslmode=require"
export PATH="USDHOME/.local/bin:USDPATH"
# Disable host header validation for public IP access
export MLFLOW_ALLOWED_HOSTS="*"
export ALLOWED_HOSTS="*"

echo "Starting MLflow server..."
echo "Backend URI: postgresql+psycopg2://${POSTGRES_USER}:***@${POSTGRES_HOST}:5432/${POSTGRES_DB}"
echo "Artifacts directory: $ARTIFACT_ROOT"
echo "Access UI at: http://USD(curl -s ifconfig.me):5000"
echo ""

mlflow server \
  --backend-store-uri "USDBACKEND_URI" \
  --default-artifact-root mlflow-artifacts:/ \
  --artifacts-destination "$ARTIFACT_ROOT" \
  --host 0.0.0.0 \
  --port 5000 \
  --allowed-hosts "*"
EOF
chmod +x ~/start-mlflow-server.sh
```

### Creating the Launch Script

* **Heredoc usage:** Uses `<< EOF` (not `<< 'EOF'`) to allow variable expansion. The variables `${POSTGRES_USER}`, `${POSTGRES_PASSWORD}`, etc. are substituted with their actual values at script creation time.
* **Purpose:** Writes a **reusable launcher** so you don't need to retype the long MLflow server command every time.
* **Executable permission:** After the file is written, `chmod +x ~/start-mlflow-server.sh` makes the file **executable**, allowing you to run the server simply by typing `~/start-mlflow-server.sh` instead of having to copy and paste the long command every time.
* **Escape sequences:** Uses `USD` for variables that should **not** be expanded during script generation (like `USDHOME`, `USDBACKEND_URI`) - these will be evaluated when the startup script runs, not when it's created.

### Environment Variables in the Startup Script

The generated script sets several environment variables before starting MLflow:

* **`BACKEND_URI`**: Contains the complete PostgreSQL connection string with embedded credentials. This is built using the values collected during interactive prompts.
* **`PATH`**: Ensures `~/.local/bin` is in the PATH so the `mlflow` command can be found.
* **`MLFLOW_ALLOWED_HOSTS="*"`** and **`ALLOWED_HOSTS="*"`**: These environment variables disable host header validation, which is crucial for accessing the MLflow UI via the VM's public IP address. Without these, you may encounter "Invalid Host header" errors when accessing the UI from a browser.

### The MLflow Launch Command

The core of the generated script is the `mlflow server` command, which binds the three primary components of your setup:

* **`mlflow server`**: The command that initiates the MLflow Tracking Server process.
* **`--backend-store-uri "$BACKEND_URI"`**: This is the crucial link to the metadata store. It uses the connection string you built from your inputs (host, user, password, database) to tell MLflow where to store and retrieve all experiment metadata, run parameters, metrics, tags, and the Model Registry data.
* **`--default-artifact-root mlflow-artifacts:/`**: This tells MLflow to use the HTTP proxy for artifact storage. The `mlflow-artifacts:/` URI scheme causes the client to send artifact uploads/downloads via HTTP to the server, instead of trying to write to local file paths. This is **critical** for remote deployments to prevent permission errors.
* **`--artifacts-destination "$ARTIFACT_ROOT"`**: This specifies where the server actually stores artifact files on disk. Combined with `--default-artifact-root mlflow-artifacts:/`, this enables HTTP proxying: clients send artifacts via HTTP, and the server stores them in the specified directory (`~/mlruns-artifacts`).
* **`--host 0.0.0.0`**: This instructs the server to **bind to all network interfaces** on the VM, making it accessible from both localhost and external IP addresses.
* **`--port 5000`**: Uses MLflow's default port. Make sure this port is open in your Azure Network Security Group (NSG).
* **`--allowed-hosts "*"`**: This parameter explicitly allows connections from any host header. Combined with the environment variables above, this prevents the "Invalid Host header - possible DNS rebinding attack detected" error that occurs when accessing the UI via the VM's public IP address instead of localhost.

```ad-note
An **Azure Network Security Group (NSG)** acts as a **virtual firewall** for your Azure resources. It contains a list of **security rules** that allow or deny inbound (ingress) or outbound (egress) network traffic to and from resources connected to Azure Virtual Networks (VNet).
```

```ad-important
**Critical Configuration:** The combination of `--default-artifact-root mlflow-artifacts:/` and `--artifacts-destination` is **essential** for remote deployments. Without `mlflow-artifacts:/`, the server returns local file paths like `/home/azureuser/mlruns-artifacts/...`, causing clients to attempt local file operations and resulting in permission errors. The `mlflow-artifacts:/` URI scheme enables HTTP proxying, ensuring clients send artifacts via HTTP to the server instead of trying to write locally.
```

### Defining the Backend URI

The script constructs the `BACKEND_URI` using your interactive inputs:

```
postgresql+psycopg2://USER:PASSWORD@HOST:5432/DB?sslmode=require
```

**Components:**
* **`postgresql+psycopg2://`** - The SQLAlchemy connection scheme. `postgresql` is the dialect, `psycopg2` is the driver that MLflow's SQLAlchemy layer uses to communicate with PostgreSQL.
* **`USER:PASSWORD@`** - The PostgreSQL credentials collected during interactive prompts. The password is embedded directly in the URI (this is standard for connection strings, though less secure than using separate credentials).
* **`HOST:5432`** - The PostgreSQL server hostname (FQDN) and default PostgreSQL port.
* **`/DB`** - The database name (typically `mlflow`).
* **`?sslmode=require`** - **Critical for Azure:** Azure PostgreSQL Flexible Server requires SSL/TLS encryption for all connections. This parameter ensures the connection uses SSL, avoiding TLS-related connection failures. Without it, connections will be rejected.

**Security Note:** The connection string includes the password in plain text. The script stores this in a file readable only by the user (`~/start-mlflow-server.sh` with standard permissions), but be aware of this for production deployments.

## Final Guidance & Completion

```bash
echo -e "\n${GREEN}=== MLflow setup complete! ===${NC}\n"
echo "To start MLflow: ~/start-mlflow-server.sh"
echo "Run in background: nohup ~/start-mlflow-server.sh > mlflow-server.log 2>&1 &"
echo "Check health: curl http://localhost:5000/health"
echo "UI: http://<VM_PUBLIC_IP>:5000"
echo -e "${YELLOW}Ensure port 5000 is open in the VM's network security group.${NC}"
```

The script concludes with colored output providing clear next steps:

* **Completion message:** Green success message (` === MLflow setup complete! ===`) confirms successful installation.
* **Start command:** `~/start-mlflow-server.sh` - Runs the server with your configuration in the foreground (you'll see logs in real-time). Press `Ctrl+C` to stop.
* **Background run:** `nohup ~/start-mlflow-server.sh > mlflow-server.log 2>&1 &` -
	* `nohup` ensures the process continues running after you log out of SSH.
	* `> mlflow-server.log` redirects stdout to a log file.
	* `2>&1` redirects stderr to stdout (so errors also go to the log file).
	* `&` runs the command in the background.
* **Health check:** `curl http://localhost:5000/health` - Quick probe to verify the server is running. Expected response: `{"status":"ok"}` or `OK`.
* **UI URL:** `http://<VM_PUBLIC_IP>:5000` - Where teammates can access the MLflow dashboard from their browsers. Replace `<VM_PUBLIC_IP>` with your actual VM's public IP address.
* **Reminder:** Yellow warning text reminds you to ensure port 5000 is open in the VM's Network Security Group (this should have been done in the infrastructure setup script).

### How pieces map to MLflow’s architecture

* **Postgres (BACKEND_URI)** - MLflow **backend store** for runs, params, metrics, tags, and **Model Registry**.
* **`--default-artifact-root mlflow-artifacts:/`** - Configures the tracking server to use HTTP proxy for artifact operations, preventing permission errors in remote deployments.
* **`--artifacts-destination ARTIFACT_ROOT`** - Specifies where the server stores artifact files on disk (local directory in this setup; can be switched to Azure Blob via a `wasbs://...` URI).
* **`mlflow server`** on the VM - the **tracking server** + UI that clients point to using `mlflow.set_tracking_uri("http://<VM_IP>:5000")`.

> Want to use Azure Blob instead of local disk for artifacts? Keep `--default-artifact-root mlflow-artifacts:/` and change `--artifacts-destination` to a `wasbs://container@account.blob.core.windows.net/prefix` URI, then export `AZURE_STORAGE_ACCOUNT_NAME` + `AZURE_STORAGE_ACCOUNT_KEY` (or a connection string) before starting the server.
