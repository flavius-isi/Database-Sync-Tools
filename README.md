# Database Sync Tools

A fast, parallel toolkit for slicing and exporting databases from development environments and importing them cleanly into local database instances for local development.

The toolkit is organized by **remote database hosts** (`misc61`, `misc62`, `misc63`, `misc64`, `fpbx62`). When restored locally, databases are automatically prefixed with their host name (e.g. `misc62_slidev_dash`, `misc64_dash`, `fpbx62_asteriskcdrdb`) to guarantee zero name collisions and allow multiple local applications to share common data sources.

---

## Dual-Engine Architecture (MySQL + MariaDB)

Our remote infrastructure uses different database engines across servers:
- **MariaDB 11.8+**: `misc61` and `misc62`
- **MySQL 8.0+**: `misc63`, `misc64`, and `fpbx62`

Because MariaDB uses unique syntax (such as inline JSON default expressions without MySQL 8 parenthesis wrapping: `languages longtext DEFAULT '["en"]' CHECK (json_valid(...))`), importing MariaDB schemas directly into MySQL 8 causes silent table creation failures.

To ensure **100% dev/prod parity**, the toolkit routes databases to engine-specific local services:
- **Local MySQL Server**: `127.0.0.1:3306` (Target for `misc63`, `misc64`, `fpbx62`)
- **Local MariaDB Server**: `127.0.0.1:3307` (Target for `misc61`, `misc62`)

---

## Features

- **🌐 Host-Centric Architecture**: Databases are grouped by their origin server (`misc61`, `misc62`, `misc63`, `misc64`, `fpbx62`).
- **🔀 Dual-Engine Routing**: Automatically routes exports and imports using the appropriate binary (`mysqldump` / `mariadb-dump`) and target port (3306 / 3307).
- **⚡ Concurrent Exports**: Export all databases on any host concurrently in parallel background threads via `export.sh`.
- **📊 Row Slicing**: Slices recent data per table (default: latest 5,000 rows by descending ID) for fast downloads and manageable local disk sizes.
- **🛡️ Clean Definer Filtering**: Automatically strips remote `DEFINER` attributes during import so triggers, procedures, and views bind directly to your local MySQL/MariaDB session without permission errors.
- **🔄 Cross-Schema View Rewriting**: Automatically rewrites cross-database view dependencies (e.g., `dash.` and `salesforce.` joins) during import to match local prefixed schemas.
- **📄 Transparent Execution Logs**: Import logs are stored at `import/<host_group>/<db_name>.log` mirroring `output/<host_group>/<db_name>.sql`. No silent errors are ever swallowed (`2>/dev/null` removed).
- **🔒 Security First**: Credentials are fully decoupled via `.env` and kept strictly out of version control.

---

## Remote Host & Database Directory

| Host Target | Engine | Local Target Port | Databases | Local Database Name |
| :--- | :--- | :--- | :--- | :--- |
| **`misc61`** | MariaDB | `3307` | `slicrm_dev` | `misc61_slicrm_dev` |
| **`misc62`** | MariaDB | `3307` | `slidev_dash`<br>`slidev_clients`<br>`ipla_dev_latest`<br>`slidev_salesforce`<br>`iapi61` | `misc62_slidev_dash`<br>`misc62_slidev_clients`<br>`misc62_ipla_dev_latest`<br>`misc62_slidev_salesforce`<br>`misc62_iapi61` |
| **`misc63`** | MySQL | `3306` | `convoso_dev` | `misc63_convoso_dev` |
| **`misc64`** | MySQL | `3306` | `dash`<br>`dash_staging_dev_copy`<br>`clients`<br>`clients_staging_dev_copy`<br>`salesforce`<br>`api`<br>`dialer`<br>`iapp2_dev_applications`<br>`client_data_imports`<br>`zz-payment-service`<br>`zz-payment-service-staging-dev-copy`<br>`facebook` | `misc64_dash`<br>`misc64_dash_staging_dev_copy`<br>`misc64_clients`<br>`misc64_clients_staging_dev_copy`<br>`misc64_salesforce`<br>`misc64_api`<br>`misc64_dialer`<br>`misc64_iapp2_dev_applications`<br>`misc64_client_data_imports`<br>`misc64_zz-payment-service`<br>`misc64_zz-payment-service-staging-dev-copy`<br>`misc64_facebook` |
| **`fpbx62`** | MySQL | `3306` | `asteriskcdrdb` | `fpbx62_asteriskcdrdb` |

---

## Prerequisites

Ensure you have both MySQL and MariaDB client utilities available:

1. **MySQL Client Tools**: `mysql` and `mysqldump`
   ```bash
   brew install mysql-client
   ```
2. **MariaDB Client Tools**: `mariadb` and `mariadb-dump`
   If you use DBngin, you can symlink the binaries into `/opt/homebrew/bin/`:
   ```bash
   ln -s /Users/Shared/DBngin/mariadb/12.3.2_arm/bin/mariadb /opt/homebrew/bin/mariadb
   ln -s /Users/Shared/DBngin/mariadb/12.3.2_arm/bin/mariadb-dump /opt/homebrew/bin/mariadb-dump
   ```
3. **Local Database Servers**:
   - MySQL running on `127.0.0.1:3306` (Homebrew / DBngin / Docker)
   - MariaDB running on `127.0.0.1:3307` (DBngin / Docker)

---

## Quick Start

### 1. Configure Environment

Copy the example configuration file:

```bash
cp .env.example .env
```

Open `.env` and configure your row limit per table, local server ports, and remote host credentials.

> **Security Note**: `.env`, all SQL dumps under `output/`, and all logs under `import/` are automatically ignored by Git. Never commit credentials to version control.

---

### 2. Export Databases

#### Export by Remote Host (Parallel)
Run the orchestrator script with the target host name to export all databases on that host concurrently:

```bash
./export.sh misc62     # Export all Canada stack databases (MariaDB)
./export.sh misc64     # Export all US stack databases (MySQL)
./export.sh misc61     # Export SLI CRM (MariaDB)
./export.sh misc63     # Export Convoso (MySQL)
./export.sh fpbx62     # Export Asterisk PBX CDR (MySQL)
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

---

### 3. Import to Local Environment

Make sure both your local MySQL (3306) and MariaDB (3307) servers are running, then execute:

#### Import by Host
```bash
./import.sh misc62     # Restores into MariaDB on 127.0.0.1:3307
./import.sh misc64     # Restores into MySQL on 127.0.0.1:3306
```

#### Import All Available Dumps
```bash
./import.sh all
```

This script will:
1. Locate all `.sql` dump files under `output/<target>/`.
2. Determine each target's engine from `.env` and route to either MySQL (`3306`) or MariaDB (`3307`).
3. Automatically prioritize prerequisite databases (`misc64_dash`, `misc64_salesforce`, `misc62_slidev_dash`, `misc62_slidev_salesforce`) before dependent databases.
4. Drop and recreate each target database with `utf8mb4_unicode_ci` collation.
5. Strip remote `DEFINER` directives on-the-fly.
6. Rewrite cross-database view schemas (e.g. `dash.` to `misc64_dash.`) so views bind cleanly.
7. Restore tables, views, and data.
8. Output detailed execution logs to `import/<host_group>/<database_name>.log`.
9. Surface any SQL errors in red to the terminal and verify table creation count.

---

## Architecture & Modular Structure

The codebase adheres to DRY principles with modular components under `lib/`:

```
Database/
├── lib/
│   ├── core.sh       # Unified entry point sourcing env.sh and db.sh
│   ├── env.sh        # .env discovery, environment loading, and remote credentials mapping
│   ├── db.sh         # Engine detection, binary tool resolution, local connection, naming
│   └── export.sh     # Streamlined single-database worker (sourced by export/*/*.sh)
├── export.sh         # Parallel multi-database export orchestrator
└── import.sh         # Dual-engine sequential import orchestrator
```

---

## Adding a New Database Target

### Under an Existing Host
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

### Under a New Host
When introducing a completely new host (e.g., `misc65`):
1. In `.env`, declare the engine and connection credentials:
   ```ini
   MISC65_ENGINE=mysql   # or mariadb
   MISC65_HOST=your_host
   MISC65_PORT=3306
   MISC65_USER=your_user
   MISC65_PASS="your_password"
   ```
2. Create your database export script inside `export/misc65/<db_name>.sh`.
3. Add the host name to `KNOWN_HOSTS` in `lib/db.sh`.

