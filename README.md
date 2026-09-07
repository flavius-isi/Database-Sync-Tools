# Database Sync Tools

A fast, parallel toolkit for slicing and exporting MySQL databases from development environments and importing them cleanly into a local MySQL instance for local development.

The toolkit is organized by **remote MySQL hosts** (`misc61`, `misc62`, `misc63`, `misc64`, `fpbx62`). When restored locally, databases are automatically prefixed with their host name (e.g. `misc62_slidev_dash`, `misc64_dash`, `fpbx62_asteriskcdrdb`) to guarantee zero name collisions and allow multiple local applications to share common data sources.

---

## Features

- **🌐 Host-Centric Architecture**: Databases are grouped by their origin server (`misc61`, `misc62`, `misc63`, `misc64`, `fpbx62`).
- **⚡ Concurrent Exports**: Export all databases on any host concurrently in parallel background threads via `export.sh`.
- **📊 Row Slicing**: Slices recent data per table (default: latest 5,000 rows by descending ID) for fast downloads and manageable local disk sizes.
- **🛡️ Clean Definer Filtering**: Automatically strips remote `DEFINER` attributes during import so triggers, procedures, and views bind directly to your local MySQL session without permission errors.
- **🔄 Cross-Schema View Rewriting**: Automatically rewrites cross-database view dependencies (e.g., `dash.` and `salesforce.` joins) during import to match local prefixed schemas.
- **🔒 Security First**: Credentials are fully decoupled via `.env` and kept strictly out of version control.

---

## Remote Host & Database Directory

| Host Target | Databases | Local MySQL Database Name |
| :--- | :--- | :--- |
| **`misc61`** | `slicrm_dev` | `misc61_slicrm_dev` |
| **`misc62`** | `slidev_dash`<br>`slidev_clients`<br>`ipla_dev_latest`<br>`slidev_salesforce`<br>`iapi61` | `misc62_slidev_dash`<br>`misc62_slidev_clients`<br>`misc62_ipla_dev_latest`<br>`misc62_slidev_salesforce`<br>`misc62_iapi61` |
| **`misc63`** | `convoso_dev` | `misc63_convoso_dev` |
| **`misc64`** | `dash`<br>`clients`<br>`salesforce`<br>`api`<br>`dialer`<br>`iapp2_dev_applications`<br>`client_data_imports`<br>`zz-payment-service`<br>`facebook` | `misc64_dash`<br>`misc64_clients`<br>`misc64_salesforce`<br>`misc64_api`<br>`misc64_dialer`<br>`misc64_iapp2_dev_applications`<br>`misc64_client_data_imports`<br>`misc64_zz_payment_service`<br>`misc64_facebook` |
| **`fpbx62`** | `asteriskcdrdb` | `fpbx62_asteriskcdrdb` |

---


## Prerequisites

Ensure you have standard MySQL client utilities installed on your system:

- **MySQL Client Tools**: `mysql` and `mysqldump`
  - On macOS (via Homebrew):
    ```bash
    brew install mysql-client
    # Add to PATH if needed:
    echo 'export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"' >> ~/.zshrc
    ```
- **Bash & Sed**: Standard on macOS and Linux.

---

## Quick Start

### 1. Configure Environment

Copy the example configuration file:

```bash
cp .env.example .env
```

Open `.env` and configure your row limit per table, local MySQL settings, and remote host credentials.

> **Security Note**: `.env` and all SQL dumps under `output/` are automatically ignored by Git. Never commit credentials to version control.

---

### 2. Export Databases

#### Export by Remote Host (Parallel)
Run the orchestrator script with the target host name to export all databases on that host concurrently:

```bash
./export.sh misc62     # Export all Canada stack databases
./export.sh misc64     # Export all US stack databases
./export.sh misc61     # Export SLI CRM
./export.sh misc63     # Export Convoso
./export.sh fpbx62     # Export Asterisk PBX CDR
```

#### Export All Hosts
To export every database across all hosts in parallel:

```bash
./export.sh all
```

#### Export a Single Database
You can also run any specific export script directly:

```bash
./export/misc62/slidev_dash.sh
./export/misc64/clients.sh
```

Dumps are saved cleanly to `output/<host_group>/<database_name>.sql` (e.g. `output/misc61/slicrm_dev.sql`).
When restored into your local MySQL server, they are automatically namespaced as `<host_group>_<database_name>` (e.g. `misc61_slicrm_dev`).

---

### 3. Import to Local MySQL

Make sure your local MySQL server is running, then execute:

#### Import by Host
```bash
./import.sh misc62     # Restore all misc62 databases into local MySQL
./import.sh misc64     # Restore all misc64 databases into local MySQL
```

#### Import All Available Dumps
```bash
./import.sh all
```

This script will:
1. Locate all `.sql` dump files under `output/<target>/`.
2. Automatically prioritize prerequisite databases (`misc64_dash`, `misc64_salesforce`, `misc62_slidev_dash`, etc.) before dependent databases.
3. Drop and recreate each target database with `utf8mb4_unicode_ci` collation.
4. Strip remote `DEFINER` directives on-the-fly.
5. Rewrite cross-database view schemas (e.g. `dash.` to `misc64_dash.`) so views bind cleanly.
6. Restore tables, views, and data.

---

## Adding a New Database Target

To add a new database under an existing or new host:

1. Create a new file inside `export/<host_group>/<db_name>.sh` (e.g., `export/misc62/billing.sh`).
2. Add the following boilerplate:
   ```bash
   #!/bin/bash
   HOST_GROUP="misc62"
   REMOTE_DB_NAME="billing"

   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   source "$SCRIPT_DIR/../../lib/export.sh"
   ```
3. Make it executable:
   ```bash
   chmod +x export/misc62/billing.sh
   ```


`./export.sh misc62` will automatically discover and run it alongside all other targets.
