#!/bin/bash

# Determine the directory where this script resides
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"

# Load environment configuration from .env if present
if [ -f "$SCRIPT_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$SCRIPT_DIR/.env"
    set +a
fi

# Local MySQL environment configurations
LOCAL_DB_HOST="${LOCAL_DB_HOST:-127.0.0.1}"
LOCAL_DB_PORT="${LOCAL_DB_PORT:-3306}"
LOCAL_DB_USER="${LOCAL_DB_USER:-root}"
LOCAL_DB_PASS="${LOCAL_DB_PASS:-}"
export MYSQL_PWD="$LOCAL_DB_PASS"

echo "===================================================="
echo "📥 Starting Master Local Database Importer"
echo "📡 Target: $LOCAL_DB_HOST:$LOCAL_DB_PORT (User: $LOCAL_DB_USER)"
echo "===================================================="

if [ ! -d "$OUTPUT_DIR" ]; then
    echo "❌ Output data directory not found at $OUTPUT_DIR"
    exit 1
fi

shopt -s nullglob
DUMP_FILES=("$OUTPUT_DIR"/latest_*_dump.sql)

if [ ${#DUMP_FILES[@]} -eq 0 ]; then
    echo "❌ No backup files found matching 'latest_*_dump.sql' inside $OUTPUT_DIR"
    echo "   Run './export_us.sh' (or a single export script) first to generate dumps."
    exit 1
fi

SUCCESS_COUNT=0
FAILED_COUNT=0
FAILED_LIST=()

for file in "${DUMP_FILES[@]}"; do
    filename=$(basename "$file")
    db_name=$(echo "$filename" | sed 's/^latest_//' | sed 's/_dump.sql$//')

    echo ""
    echo "📦 [Target Ecosystem] Restoring environment: $db_name"
    echo "----------------------------------------------------"

    # Drop the database first to ensure a clean slate and prevent trigger collision errors
    echo "   🛠️  Wiping and resetting empty target schema space..."
    mysql -u "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -P "$LOCAL_DB_PORT" -e "DROP DATABASE IF EXISTS \`$db_name\`; CREATE DATABASE \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    
    if [ $? -ne 0 ]; then
        echo "   ❌ Failed to initialize schema containment zone: $db_name"
        ((FAILED_COUNT++))
        FAILED_LIST+=("$filename (Database initialization rejected)")
        continue
    fi

    # Pipe the dump through sed to strip out remote DEFINER configurations on-the-fly.
    # This maps triggers/views to your local root session cleanly instead of crashing.
    echo "   🚚 Filtering definers and streaming data blocks..."
    sed -E 's/DEFINER=`[^`]+`@`[^`]+`//g' "$file" | mysql -u "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -P "$LOCAL_DB_PORT" --force "$db_name"

    if [ $? -eq 0 ]; then
        echo "   ✅ Sync complete: Local instance '$db_name' is active and healthy."
        ((SUCCESS_COUNT++))
    else
        echo "   ❌ Import execution broken for raw file records: $db_name"
        ((FAILED_COUNT++))
        FAILED_LIST+=("$filename (SQL processing exception)")
    fi
done

unset MYSQL_PWD

echo ""
echo "===================================================="
echo "📊 Master Local Sync Execution Summary"
echo "===================================================="
echo "  Total Datasets Mapped: ${#DUMP_FILES[@]}"
echo "  Successful Imports:    $SUCCESS_COUNT"
echo "  Failed Sync Blocks:    $FAILED_COUNT"

if [ $FAILED_COUNT -gt 0 ]; then
    echo ""
    echo "🚨 The following localized segments failed to map completely:"
    for failed in "${FAILED_LIST[@]}"; do
        echo "    - $failed"
    done
    echo "===================================================="
    exit 1
else
    echo ""
    echo "🎉 Local multi-tenant database environment fully synced and functional!"
    echo "===================================================="
    exit 0
fi
