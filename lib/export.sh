#!/bin/bash

# Determine directory and load core library
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/core.sh
source "$LIB_DIR/core.sh"

# Load environment configuration
load_env

# Resolve remote connection credentials
get_remote_credentials "${HOST_GROUP:-}"
DB_HOST="${DB_HOST:-$REMOTE_HOST}"
DB_PORT="${DB_PORT:-$REMOTE_PORT}"
DB_USER="${DB_USER:-$REMOTE_USER}"
DB_PASS="${DB_PASS:-$REMOTE_PASS}"
ROW_LIMIT="${ROW_LIMIT:-5000}"

# Resolve remote and local database names
REMOTE_DB_NAME="${REMOTE_DB_NAME:-${DB_NAME:-}}"
if [ -z "$REMOTE_DB_NAME" ]; then
    echo "❌ Error: REMOTE_DB_NAME (or DB_NAME) is not defined."
    exit 1
fi

LOCAL_DB_NAME="${LOCAL_DB_NAME:-$(resolve_local_db_name "$REMOTE_DB_NAME" "${HOST_GROUP:-}")}"

if [ -n "$HOST_GROUP" ]; then
    OUTPUT_DIR="$PROJECT_ROOT/output/$HOST_GROUP"
else
    OUTPUT_DIR="$PROJECT_ROOT/output"
fi

# Validate required connection parameters
if [ -z "$DB_HOST" ] || [ -z "$DB_USER" ]; then
    echo "❌ Error: Missing database connection configuration for '$REMOTE_DB_NAME' (Host group: ${HOST_GROUP:-custom})."
    echo "   Ensure host variables are configured in your .env file."
    exit 1
fi

# Resolve database engine, binaries, and extraction flags
HOST_ENGINE=$(get_engine_for_host "${HOST_GROUP:-}")
DUMP_BIN=$(get_dump_binary "$HOST_ENGINE")
CLIENT_BIN=$(get_client_binary "$HOST_ENGINE")
get_export_flags "$HOST_ENGINE"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/${REMOTE_DB_NAME}.sql"

# Securely set password scope
export MYSQL_PWD="$DB_PASS"

echo "----------------------------------------------------"
echo "🚀 Starting optimized extraction: $REMOTE_DB_NAME (Local DB: $LOCAL_DB_NAME)"
echo "📡 Host: $DB_HOST:$DB_PORT (User: $DB_USER | Group: ${HOST_GROUP:-default} | Engine: $HOST_ENGINE)"
echo "🔧 Tools: $DUMP_BIN / $CLIENT_BIN"
echo "📊 Target row slice per table: $ROW_LIMIT"
echo "----------------------------------------------------"

HAD_ERROR=0

# Initialize output file with performance and dependency bypass constraints
echo "SET FOREIGN_KEY_CHECKS = 0;" > "$OUTPUT_FILE"
echo "SET UNIQUE_CHECKS = 0;" >> "$OUTPUT_FILE"

# Export schema structure
echo "📦 [Structure] Fetching schema constraints for '$REMOTE_DB_NAME' ($HOST_ENGINE)..."
ERR_TMP=$(mktemp)
"$DUMP_BIN" -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "${DUMP_STRUCT_FLAGS[@]}" "$REMOTE_DB_NAME" >> "$OUTPUT_FILE" 2>"$ERR_TMP"
DUMP_STATUS=$?
if [ $DUMP_STATUS -ne 0 ] || grep -E '^ERROR [0-9]+' "$ERR_TMP" &>/dev/null; then
    echo "⚠️ Warning: $DUMP_BIN schema export encountered issues for $REMOTE_DB_NAME:"
    cat "$ERR_TMP"
    HAD_ERROR=1
fi
rm -f "$ERR_TMP"

echo "📋 [Optimization] Consolidating table metadata map..."
META_QUERY="SELECT t.TABLE_NAME, IF(c.EXTRA LIKE '%auto_increment%', 'YES', 'NO') FROM information_schema.TABLES t LEFT JOIN information_schema.COLUMNS c ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME AND c.COLUMN_NAME = 'id' WHERE t.TABLE_SCHEMA = '$REMOTE_DB_NAME' AND t.TABLE_TYPE = 'BASE TABLE';"

ERR_TMP=$(mktemp)
TABLE_MAP=$("$CLIENT_BIN" -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "${CLIENT_QUERY_FLAGS[@]}" -B -N -e "$META_QUERY" 2>"$ERR_TMP")
CLIENT_STATUS=$?
if [ $CLIENT_STATUS -ne 0 ] || grep -E '^ERROR [0-9]+' "$ERR_TMP" &>/dev/null; then
    echo "⚠️ Warning: Error querying table map for $REMOTE_DB_NAME:"
    cat "$ERR_TMP"
    HAD_ERROR=1
fi
rm -f "$ERR_TMP"

if [ -z "$TABLE_MAP" ]; then
    echo "   ℹ️ No base tables found in '$REMOTE_DB_NAME' (empty database or views only)."
else
    # Loop through the table map
    while read -r table is_auto_inc; do
        if [ -z "$table" ]; then continue; fi

        ERR_TMP=$(mktemp)
        if [ "$is_auto_inc" = "YES" ]; then
            echo "   📥 [Data Stream] Slicing LATEST $ROW_LIMIT rows: $table"
            "$DUMP_BIN" -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "${DUMP_DATA_FLAGS[@]}" --where="1=1 ORDER BY id DESC LIMIT $ROW_LIMIT" "$REMOTE_DB_NAME" "$table" >> "$OUTPUT_FILE" 2>"$ERR_TMP"
        else
            echo "   📥 [Data Stream] Slicing ANY $ROW_LIMIT rows: $table (fallback)"
            "$DUMP_BIN" -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "${DUMP_DATA_FLAGS[@]}" --where="1=1 LIMIT $ROW_LIMIT" "$REMOTE_DB_NAME" "$table" >> "$OUTPUT_FILE" 2>"$ERR_TMP"
        fi
        TABLE_STATUS=$?
        if [ $TABLE_STATUS -ne 0 ] || grep -E '^ERROR [0-9]+' "$ERR_TMP" &>/dev/null; then
            echo "   ⚠️ Error slicing table $table:"
            cat "$ERR_TMP"
            HAD_ERROR=1
        fi
        rm -f "$ERR_TMP"
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
