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

# Resolve defaults based on HOST_GROUP if defined
DEFAULT_HOST=""
DEFAULT_PORT="3306"
DEFAULT_USER=""
DEFAULT_PASS=""

case "$HOST_GROUP" in
    misc61)
        DEFAULT_HOST="$MISC61_HOST"
        DEFAULT_PORT="${MISC61_PORT:-3306}"
        DEFAULT_USER="$MISC61_USER"
        DEFAULT_PASS="$MISC61_PASS"
        ;;
    misc62)
        DEFAULT_HOST="$MISC62_HOST"
        DEFAULT_PORT="${MISC62_PORT:-3306}"
        DEFAULT_USER="$MISC62_USER"
        DEFAULT_PASS="$MISC62_PASS"
        ;;
    misc63)
        DEFAULT_HOST="$MISC63_HOST"
        DEFAULT_PORT="${MISC63_PORT:-3306}"
        DEFAULT_USER="$MISC63_USER"
        DEFAULT_PASS="$MISC63_PASS"
        ;;
    misc64)
        DEFAULT_HOST="$MISC64_HOST"
        DEFAULT_PORT="${MISC64_PORT:-3306}"
        DEFAULT_USER="$MISC64_USER"
        DEFAULT_PASS="$MISC64_PASS"
        ;;
    fpbx62)
        DEFAULT_HOST="$FPBX62_HOST"
        DEFAULT_PORT="${FPBX62_PORT:-3306}"
        DEFAULT_USER="$FPBX62_USER"
        DEFAULT_PASS="$FPBX62_PASS"
        ;;
    *)
        DEFAULT_HOST="${REMOTE_DB_HOST:-}"
        DEFAULT_PORT="${REMOTE_DB_PORT:-3306}"
        DEFAULT_USER="${REMOTE_DB_USER:-}"
        DEFAULT_PASS="${REMOTE_DB_PASS:-}"
        ;;
esac

# Resolve database parameters
DB_HOST="${DB_HOST:-$DEFAULT_HOST}"
DB_PORT="${DB_PORT:-$DEFAULT_PORT}"
DB_USER="${DB_USER:-$DEFAULT_USER}"
DB_PASS="${DB_PASS:-$DEFAULT_PASS}"
ROW_LIMIT="${ROW_LIMIT:-5000}"

# Resolve remote and local database names
REMOTE_DB_NAME="${REMOTE_DB_NAME:-${DB_NAME:-}}"
if [ -z "$REMOTE_DB_NAME" ]; then
    echo "❌ Error: REMOTE_DB_NAME (or DB_NAME) is not defined."
    exit 1
fi

if [ -n "$HOST_GROUP" ]; then
    LOCAL_DB_NAME="${LOCAL_DB_NAME:-${HOST_GROUP}_${REMOTE_DB_NAME}}"
    OUTPUT_DIR="$ROOT_DIR/output/$HOST_GROUP"
else
    LOCAL_DB_NAME="${LOCAL_DB_NAME:-$REMOTE_DB_NAME}"
    OUTPUT_DIR="$ROOT_DIR/output"
fi

# Validate required connection parameters
if [ -z "$DB_HOST" ] || [ -z "$DB_USER" ]; then
    echo "❌ Error: Missing database connection configuration for '$REMOTE_DB_NAME' (Host group: ${HOST_GROUP:-custom})."
    echo "   Ensure host variables are configured in your .env file."
    exit 1
fi

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/${REMOTE_DB_NAME}.sql"

# Securely set password scope
export MYSQL_PWD="$DB_PASS"

echo "----------------------------------------------------"
echo "🚀 Starting optimized extraction: $REMOTE_DB_NAME (Local DB: $LOCAL_DB_NAME)"
echo "📡 Host: $DB_HOST:$DB_PORT (User: $DB_USER | Group: ${HOST_GROUP:-default})"
echo "📊 Target row slice per table: $ROW_LIMIT"
echo "----------------------------------------------------"

HAD_ERROR=0

# Initialize output file with performance and dependency bypass constraints
echo "SET FOREIGN_KEY_CHECKS = 0;" > "$OUTPUT_FILE"
echo "SET UNIQUE_CHECKS = 0;" >> "$OUTPUT_FILE"

# Export schema structure using zlib network compression
echo "📦 [Structure] Fetching schema constraints for '$REMOTE_DB_NAME'..."
mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" --compression-algorithms=zlib --single-transaction --skip-lock-tables --no-data --no-tablespaces --set-gtid-purged=OFF "$REMOTE_DB_NAME" >> "$OUTPUT_FILE" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "⚠️ Warning: mysqldump schema export returned non-zero for $REMOTE_DB_NAME"
    HAD_ERROR=1
fi

echo "📋 [Optimization] Consolidating table metadata map..."
META_QUERY="SELECT t.TABLE_NAME, IF(c.EXTRA LIKE '%auto_increment%', 'YES', 'NO') FROM information_schema.TABLES t LEFT JOIN information_schema.COLUMNS c ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME AND c.COLUMN_NAME = 'id' WHERE t.TABLE_SCHEMA = '$REMOTE_DB_NAME' AND t.TABLE_TYPE = 'BASE TABLE';"

TABLE_MAP=$(mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" --compression-algorithms=zlib -B -N -e "$META_QUERY" 2>/dev/null)

if [ -z "$TABLE_MAP" ]; then
    echo "   ℹ️ No base tables found in '$REMOTE_DB_NAME' (empty database or views only)."
else
    # Loop through the table map
    while read -r table is_auto_inc; do
        if [ -z "$table" ]; then continue; fi
        
        if [ "$is_auto_inc" = "YES" ]; then
            echo "   📥 [Data Stream] Slicing LATEST $ROW_LIMIT rows: $table"
            mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" --compression-algorithms=zlib --single-transaction --skip-lock-tables --no-create-info --no-tablespaces --skip-triggers --set-gtid-purged=OFF --where="1=1 ORDER BY id DESC LIMIT $ROW_LIMIT" "$REMOTE_DB_NAME" "$table" >> "$OUTPUT_FILE" 2>/dev/null
        else
            echo "   📥 [Data Stream] Slicing ANY $ROW_LIMIT rows: $table (fallback)"
            mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" --compression-algorithms=zlib --single-transaction --skip-lock-tables --no-create-info --no-tablespaces --skip-triggers --set-gtid-purged=OFF --where="1=1 LIMIT $ROW_LIMIT" "$REMOTE_DB_NAME" "$table" >> "$OUTPUT_FILE" 2>/dev/null
        fi
        
        if [ $? -ne 0 ]; then HAD_ERROR=1; fi
    done <<< "$TABLE_MAP"
fi

# Append structural keys back on termination
echo "SET FOREIGN_KEY_CHECKS = 1;" >> "$OUTPUT_FILE"
echo "SET UNIQUE_CHECKS = 1;" >> "$OUTPUT_FILE"

unset MYSQL_PWD

echo "----------------------------------------------------"
if [ $HAD_ERROR -eq 0 ]; then
    echo "🎉 Success! Dump saved to: $OUTPUT_FILE"
    echo "----------------------------------------------------"
    exit 0
else
    echo "❌ Extraction completed with issues for: $REMOTE_DB_NAME"
    echo "----------------------------------------------------"
    exit 1
fi
