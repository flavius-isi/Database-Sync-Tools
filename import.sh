#!/bin/bash

# Determine directory paths and load core library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"
IMPORT_LOG_DIR="$SCRIPT_DIR/import"

# shellcheck source=lib/core.sh
source "$SCRIPT_DIR/lib/core.sh"

# Load environment configuration
load_env

# Inspect local targets for banner display
get_local_connection "mysql"
MYSQL_DISPLAY="$LOCAL_TARGET_HOST:$LOCAL_TARGET_PORT (User: $LOCAL_TARGET_USER)"

get_local_connection "mariadb"
MARIADB_DISPLAY="$LOCAL_TARGET_HOST:$LOCAL_TARGET_PORT (User: $LOCAL_TARGET_USER)"

echo "===================================================="
echo "📥 Master Host-Based Local Database Importer"
echo "📡 MySQL Target:   $MYSQL_DISPLAY"
echo "📡 MariaDB Target: $MARIADB_DISPLAY"
echo "===================================================="

if [ ! -d "$OUTPUT_DIR" ]; then
    echo "❌ Output data directory not found at $OUTPUT_DIR"
    exit 1
fi

TARGET="${1:-}"

if [ -z "$TARGET" ]; then
    echo "Usage: ./import.sh <host_group|all>"
    echo ""
    echo "Available host dump targets inside output/:"
    for h in "${KNOWN_HOSTS[@]}"; do
        if [ -d "$OUTPUT_DIR/$h" ]; then
            count=$(find "$OUTPUT_DIR/$h" -name "*.sql" 2>/dev/null | wc -l | tr -d ' ')
            echo "  - $h ($count dump files ready)"
        fi
    done
    echo "  - all    (Import all available dumps across all hosts)"
    echo ""
    echo "Example: ./import.sh misc62"
    exit 1
fi

shopt -s nullglob
RAW_DUMP_FILES=()

if [ "$TARGET" = "all" ]; then
    for h in "${KNOWN_HOSTS[@]}"; do
        if [ -d "$OUTPUT_DIR/$h" ]; then
            for f in "$OUTPUT_DIR/$h"/*.sql; do
                RAW_DUMP_FILES+=("$f")
            done
        fi
    done
else
    TARGET_DIR="$OUTPUT_DIR/$TARGET"
    if [ ! -d "$TARGET_DIR" ]; then
        echo "❌ Output directory not found for target '$TARGET': $TARGET_DIR"
        echo "   Run './export.sh $TARGET' first to generate dumps."
        exit 1
    fi
    for f in "$TARGET_DIR"/*.sql; do
        RAW_DUMP_FILES+=("$f")
    done
fi

if [ ${#RAW_DUMP_FILES[@]} -eq 0 ]; then
    echo "❌ No SQL dump files found for target '$TARGET'."
    echo "   Run './export.sh $TARGET' first."
    exit 1
fi

# Prerequisite priority ordering to satisfy cross-database view joins
PRIORITY_FILES=()
STANDARD_FILES=()

for f in "${RAW_DUMP_FILES[@]}"; do
    target_db=$(resolve_local_db_name "$f")
    is_p=0
    for pdb in "${PRIORITY_DBS[@]}"; do
        if [ "$target_db" = "$pdb" ]; then
            is_p=1
            break
        fi
    done

    if [ $is_p -eq 1 ]; then
        PRIORITY_FILES+=("$f")
    else
        STANDARD_FILES+=("$f")
    fi
done

DUMP_FILES=("${PRIORITY_FILES[@]}" "${STANDARD_FILES[@]}")

SUCCESS_COUNT=0
FAILED_COUNT=0
FAILED_LIST=()

echo "⚡ Beginning sequential restoration of ${#DUMP_FILES[@]} database dumps..."

for file in "${DUMP_FILES[@]}"; do
    filename=$(basename "$file")
    host_grp=$(basename "$(dirname "$file")")
    raw_base=$(basename "$file" | sed -E 's/^latest_//' | sed -E 's/(_dump)?\.sql$//')
    db_name=$(resolve_local_db_name "$file" "$host_grp")

    # Resolve database engine and local connection parameters
    DB_ENGINE=$(get_engine_for_host "$host_grp")
    get_local_connection "$DB_ENGINE"

    export MYSQL_PWD="$LOCAL_TARGET_PASS"

    # Setup log file: import/<host_group>/<db_name>.log
    HOST_LOG_DIR="$IMPORT_LOG_DIR/$host_grp"
    mkdir -p "$HOST_LOG_DIR"
    LOG_FILE="$HOST_LOG_DIR/${raw_base}.log"

    echo ""
    echo "📦 Restoring: $db_name (Engine: $DB_ENGINE | Target: $LOCAL_TARGET_HOST:$LOCAL_TARGET_PORT)"
    echo "   📄 Log: import/$host_grp/${raw_base}.log"
    echo "----------------------------------------------------"

    # Initialize log file
    {
        echo "===================================================="
        echo "📥 Database Import Log: $db_name"
        echo "Timestamp:    $(date)"
        echo "Source Dump:  $file"
        echo "Engine:       $DB_ENGINE"
        echo "Target:       $LOCAL_TARGET_HOST:$LOCAL_TARGET_PORT (User: $LOCAL_TARGET_USER)"
        echo "===================================================="
        echo ""
    } > "$LOG_FILE"

    # Reset schema for a clean slate
    echo "   🛠️  Creating fresh schema space..."
    SCHEMA_ERR=$(mktemp)
    "$LOCAL_CLIENT_BIN" "${LOCAL_CLIENT_ARGS[@]}" -e "DROP DATABASE IF EXISTS \`$db_name\`; CREATE DATABASE \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>"$SCHEMA_ERR"
    SCHEMA_EXIT=$?

    if [ $SCHEMA_EXIT -ne 0 ] || grep -E '^ERROR [0-9]+' "$SCHEMA_ERR" &>/dev/null; then
        echo -e "\033[0;31m   ❌ Failed to initialize database: $db_name\033[0m"
        cat "$SCHEMA_ERR" | while read -r line; do echo "      $line"; done
        cat "$SCHEMA_ERR" >> "$LOG_FILE"
        rm -f "$SCHEMA_ERR"
        ((FAILED_COUNT++))
        FAILED_LIST+=("$filename (Database creation failed)")
        continue
    fi
    rm -f "$SCHEMA_ERR"

    # Stream dump file through sed filters:
    # 1. Strip remote DEFINER clauses so views/triggers bind locally
    # 2. Rewrite cross-database view schemas (e.g. `dash`. -> `misc64_dash`.)
    echo "   🚚 Filtering definers and streaming data into local $DB_ENGINE..."
    ERR_FILE=$(mktemp)
    sed -E \
        -e 's/DEFINER=`[^`]+`@`[^`]+`//g' \
        -e 's/`dash`\./`misc64_dash`\./g' \
        -e 's/`salesforce`\./`misc64_salesforce`\./g' \
        "$file" | "$LOCAL_CLIENT_BIN" "${LOCAL_CLIENT_ARGS[@]}" --force "$db_name" 2>"$ERR_FILE" >> "$LOG_FILE"
    IMPORT_EXIT=$?

    if [ -s "$ERR_FILE" ]; then
        echo "" >> "$LOG_FILE"
        echo "=== Stderr / Execution Messages ===" >> "$LOG_FILE"
        cat "$ERR_FILE" >> "$LOG_FILE"
    fi

    ERR_LINES=$(grep -E '^ERROR [0-9]+' "$ERR_FILE" || true)

    # Verify table count
    TABLE_COUNT=$("$LOCAL_CLIENT_BIN" "${LOCAL_CLIENT_ARGS[@]}" -N -B -e "SELECT count(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$db_name';" 2>/dev/null)
    TABLE_COUNT="${TABLE_COUNT:-0}"

    EXPECTS_TABLES=0
    if grep -q -m 1 -i 'CREATE TABLE' "$file"; then
        EXPECTS_TABLES=1
    fi

    HAS_ERROR=0
    if [ $IMPORT_EXIT -ne 0 ] || [ -n "$ERR_LINES" ]; then
        HAS_ERROR=1
    elif [ "$TABLE_COUNT" -eq 0 ] && [ "$EXPECTS_TABLES" -eq 1 ]; then
        HAS_ERROR=1
    fi

    if [ $HAS_ERROR -eq 1 ]; then
        echo -e "\033[0;31m   ❌ Import encountered errors for: $db_name (Tables created: $TABLE_COUNT)\033[0m"
        if [ -n "$ERR_LINES" ]; then
            echo -e "\033[0;31m   Errors:\033[0m"
            echo "$ERR_LINES" | head -n 10 | sed 's/^/      /'
        fi
        echo "   📄 Full log saved to: import/$host_grp/${raw_base}.log"
        ((FAILED_COUNT++))
        FAILED_LIST+=("$filename ($db_name - errors encountered)")
    elif [ "$TABLE_COUNT" -eq 0 ]; then
        echo "   ℹ️ Sync complete: Local database '$db_name' is active (empty database, 0 tables)."
        ((SUCCESS_COUNT++))
    else
        echo "   ✅ Sync complete: Local database '$db_name' is active ($TABLE_COUNT tables)."
        ((SUCCESS_COUNT++))
    fi

    rm -f "$ERR_FILE"
done

unset MYSQL_PWD

echo ""
echo "===================================================="
echo "📊 Master Local Import Summary"
echo "===================================================="
echo "  Target Scope:       $TARGET"
echo "  Total Databases:    ${#DUMP_FILES[@]}"
echo "  Successful Imports: $SUCCESS_COUNT"
echo "  Failed Operations:  $FAILED_COUNT"

if [ $FAILED_COUNT -gt 0 ]; then
    echo ""
    echo "🚨 The following imports encountered errors:"
    for failed in "${FAILED_LIST[@]}"; do
        echo "    - $failed"
    done
    echo "===================================================="
    exit 1
else
    echo ""
    echo "🎉 All databases imported successfully!"
    echo "===================================================="
    exit 0
fi
