# Database Sync Tools

A fast, parallel toolkit for slicing and exporting MySQL databases from development environments and importing them cleanly into a local MySQL instance for local development.

---

## Features

- **⚡ Concurrent Exports**: Export all databases in parallel background threads via `export_us.sh`.
- **📊 Row Slicing**: Slices recent data per table (default: latest 5,000 rows by descending ID) for fast downloads and manageable local disk sizes.
- **🛡️ Clean Definer Filtering**: Automatically strips remote `DEFINER` attributes during import so triggers, procedures, and views bind directly to your local MySQL session without permission errors.
- **🔒 Security First**: Credentials are fully decoupled via `.env` and kept out of version control.

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

Open `.env` and configure your credentials and export settings.

> **Note**: `.env` and SQL dumps inside `output/` are automatically ignored by Git. Never commit credentials to version control.

---

### 2. Export Databases

#### Export All Databases (Parallel)
Run the orchestrator script to export all stack databases concurrently:

```bash
./export_us.sh
```

#### Export a Single Database
To export just one database, run its specific script inside `export/`:

```bash
./export/us_api.sh
./export/us_clients.sh
./export/us_dash.sh
./export/us_dialer.sh
./export/us_facebook.sh
./export/us_iapp2_dev_applications.sh
./export/us_client_data_imports.sh
./export/us_zz-payment-service.sh
```

Dumps will be saved to the `output/` directory as `latest_<db_name>_dump.sql`.

---

### 3. Import to Local MySQL

Make sure your local MySQL server is running, then execute:

```bash
./import_us.sh
```

This script will:
1. Locate all `latest_*_dump.sql` files in `output/`.
2. Drop and recreate each target database with `utf8mb4_unicode_ci` collation for a clean slate.
3. Strip remote `DEFINER` directives on-the-fly.
4. Restore tables, views, and data.

---

## Adding a New Database Target

To add a new database to the export stack:

1. Create a new file inside `export/` named `us_<database_name>.sh` (e.g., `export/us_billing.sh`).
2. Add the following boilerplate:
   ```bash
   #!/bin/bash

   # Target database name
   DB_NAME="billing"

   # Dynamically locate directory path and source shared core engine
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   source "$SCRIPT_DIR/core.sh"
   ```
3. Make it executable:
   ```bash
   chmod +x export/us_billing.sh
   ```

`export_us.sh` will automatically discover and run it alongside all other targets.
