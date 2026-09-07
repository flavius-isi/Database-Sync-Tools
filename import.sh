#!/bin/bash

# Determine directory paths
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
echo "📥 Master Host-Based Local Database Importer"
echo "📡 Target: $LOCAL_DB_HOST:$LOCAL_DB_PORT (User: $LOCAL_DB_USER)"
echo "===================================================="

if [ ! -d "$OUTPUT_DIR" ]; then
    echo "❌ Output data directory not found at $OUTPUT_DIR"
    exit 1
fi

TARGET="${1:-}"
AVAILABLE_HOSTS=(misc61 misc62 misc63 misc64 fpbx62)

if [ -z "$TARGET" ]; then
    echo "Usage: ./import.sh <host_group|all>"
    echo ""
    echo "Available host dump targets inside output/:"
    for h in "${AVAILABLE_HOSTS[@]}"; do
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
    for h in "${AVAILABLE_HOSTS[@]}"; do
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
PRIORITY_DBS=(
    "misc64_dash"
    "misc64_salesforce"
    "misc62_slidev_dash"
    "misc62_slidev_salesforce"
)

# Helper function to compute local target database name from file path
resolve_db_name() {
    local f="$1"
    local host_grp
    host_grp=$(basename "$(dirname "$f")")
    local raw_base
    raw_base=$(basename "$f" | sed -E 's/^latest_//' | sed -E 's/(_dump)?\.sql$//')
    
    if [[ "$raw_base" == "${host_grp}_"* ]]; then
        echo "$raw_base"
    elif [ "$host_grp" = "output" ]; then
        echo "$raw_base"
    else
        echo "${host_grp}_${raw_base}"
    fi
}

PRIORITY_FILES=()
STANDARD_FILES=()

for f in "${RAW_DUMP_FILES[@]}"; do
    target_db=$(resolve_db_name "$f")
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
    db_name=$(resolve_db_name "$file")

    echo ""
    echo "📦 Restoring local database: $db_name (Source: $file)"
    echo "----------------------------------------------------"


    # Reset schema for a clean slate
    echo "   🛠️  Creating fresh schema space..."
    mysql -u "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -P "$LOCAL_DB_PORT" -e "DROP DATABASE IF EXISTS \`$db_name\`; CREATE DATABASE \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo "   ❌ Failed to initialize database: $db_name"
        ((FAILED_COUNT++))
        FAILED_LIST+=("$filename (Database creation failed)")
        continue
    fi

    # Stream dump file through sed filters:
    # 1. Strip remote DEFINER clauses so views/triggers bind locally
    # 2. Rewrite cross-database view schemas (e.g. `dash`. -> `misc64_dash`.)
    echo "   🚚 Filtering definers and streaming data into local MySQL..."
    sed -E \
        -e 's/DEFINER=`[^`]+`@`[^`]+`//g' \
        -e 's/`dash`\./`misc64_dash`\./g' \
        -e 's/`salesforce`\./`misc64_salesforce`\./g' \
        "$file" | mysql -u "$LOCAL_DB_USER" -h "$LOCAL_DB_HOST" -P "$LOCAL_DB_PORT" --force "$db_name" 2>/dev/null

    if [ $? -eq 0 ]; then
        echo "   ✅ Sync complete: Local database '$db_name' is active."
        ((SUCCESS_COUNT++))
    else
        echo "   ❌ Import finished with warnings/errors for: $db_name"
        ((FAILED_COUNT++))
        FAILED_LIST+=("$filename (SQL import errors)")
    fi
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
    echo "🎉 All databases imported successfully into local MySQL!"
    echo "===================================================="
    exit 0
fi
