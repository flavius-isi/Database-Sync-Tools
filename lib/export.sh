#!/bin/bash

# Determine directories
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$LIB_DIR/.." && pwd)"

# Load environment configuration from .env if present in project root
if [ -f "$ROOT_DIR/.env" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ROOT_DIR/.env"
    set +a
fi

# Resolve database parameters with fallbacks from .env
DB_HOST="${DB_HOST:-$REMOTE_DB_HOST}"
DB_PORT="${DB_PORT:-${REMOTE_DB_PORT:-3306}}"
DB_USER="${DB_USER:-$REMOTE_DB_USER}"
DB_PASS="${DB_PASS:-$REMOTE_DB_PASS}"
ROW_LIMIT="${ROW_LIMIT:-5000}"

# Validate required variables
if [ -z "$DB_NAME" ]; then
    echo "❌ Error: DB_NAME is not defined."
    exit 1
fi

if [ -z "$DB_HOST" ] || [ -z "$DB_USER" ]; then
    echo "❌ Error: Missing database connection configuration for '$DB_NAME'."
    echo "   Ensure REMOTE_DB_HOST, REMOTE_DB_USER, and REMOTE_DB_PASS are set in .env"
    echo "   Run: cp .env.example .env (and fill in your credentials)"
    exit 1
fi

# Ensure output directory exists in project root
OUTPUT_DIR="$ROOT_DIR/output"
mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/latest_${DB_NAME}_dump.sql"

# Securely set password scope
export MYSQL_PWD="$DB_PASS"

echo "----------------------------------------------------"
echo "🚀 Starting optimized extraction for: $DB_NAME"
echo "📡 Host: $DB_HOST:$DB_PORT (User: $DB_USER)"
echo "📊 Target row slice per table: $ROW_LIMIT"
echo "----------------------------------------------------"

HAD_ERROR=0

# Initialize pristine output files with fast-import constraints
echo "SET FOREIGN_KEY_CHECKS = 0;" > "$OUTPUT_FILE"
echo "SET UNIQUE_CHECKS = 0;" >> "$OUTPUT_FILE"

# Export global structure using modern zlib network compression
echo "📦 [Structure] Fetching schema constraints (zlib compression)..."
mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" --compression-algorithms=zlib --no-data --no-tablespaces --set-gtid-purged=OFF "$DB_NAME" >> "$OUTPUT_FILE"
if [ $? -ne 0 ]; then HAD_ERROR=1; fi

echo "📋 [Optimization] Consolidating table metadata map..."
META_QUERY="SELECT t.TABLE_NAME, IF(c.EXTRA LIKE '%auto_increment%', 'YES', 'NO') FROM information_schema.TABLES t LEFT JOIN information_schema.COLUMNS c ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME AND c.COLUMN_NAME = 'id' WHERE t.TABLE_SCHEMA = '$DB_NAME' AND t.TABLE_TYPE = 'BASE TABLE';"

TABLE_MAP=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" --compression-algorithms=zlib -B -N -e "$META_QUERY")

# Loop through the localized map memory using a here-string context
while read -r table is_auto_inc; do
    if [ -z "$table" ]; then continue; fi
    
    if [ "$is_auto_inc" = "YES" ]; then
        echo "   📥 [Data Stream] Slicing LATEST $ROW_LIMIT rows: $table"
        mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" --compression-algorithms=zlib --no-create-info --no-tablespaces --skip-triggers --set-gtid-purged=OFF --where="1=1 ORDER BY id DESC LIMIT $ROW_LIMIT" "$DB_NAME" "$table" >> "$OUTPUT_FILE"
    else
        echo "   📥 [Data Stream] Slicing ANY $ROW_LIMIT rows: $table (fallback)"
        mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" --compression-algorithms=zlib --no-create-info --no-tablespaces --skip-triggers --set-gtid-purged=OFF --where="1=1 LIMIT $ROW_LIMIT" "$DB_NAME" "$table" >> "$OUTPUT_FILE"
    fi
    
    if [ $? -ne 0 ]; then HAD_ERROR=1; fi
done <<< "$TABLE_MAP"

# Append structural keys back on termination
echo "SET FOREIGN_KEY_CHECKS = 1;" >> "$OUTPUT_FILE"
echo "SET UNIQUE_CHECKS = 1;" >> "$OUTPUT_FILE"

unset MYSQL_PWD

echo "----------------------------------------------------"
if [ $HAD_ERROR -eq 0 ]; then
    echo "🎉 Success! Sliced dump saved to: $OUTPUT_FILE"
    echo "----------------------------------------------------"
    exit 0
else
    echo "❌ Finished extraction with failures for: $DB_NAME"
    echo "----------------------------------------------------"
    exit 1
fi
