#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "===================================================="
echo "🌍 Starting Master Parallel Database Orchestrator"
echo "===================================================="

# Pre-flight check: verify .env exists before launching concurrent workers
ENV_FILE="$SCRIPT_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "⚠️  Configuration error: .env file not found at $ENV_FILE"
    echo "👉 Please copy .env.example to .env and configure your database credentials:"
    echo "   cp .env.example .env"
    exit 1
fi

shopt -s nullglob
EXPORT_SCRIPTS=("$SCRIPT_DIR/export"/*.sh)

if [ ${#EXPORT_SCRIPTS[@]} -eq 0 ]; then
    echo "❌ No export targets found inside '$SCRIPT_DIR/export/'."
    exit 1
fi

# Use standard indexed arrays for universal macOS Bash 3.2 compatibility
PIDS=()
SCRIPT_NAMES=()

echo "⚡ Launching ${#EXPORT_SCRIPTS[@]} extractions concurrently..."

# Fire off each script into the background simultaneously
for script in "${EXPORT_SCRIPTS[@]}"; do
    script_name=$(basename "$script")
    
    (cd "$SCRIPT_DIR/export" && bash "./$script_name") &
    PIDS+=($!)
    SCRIPT_NAMES+=("$script_name")
done

echo "⏳ All threads deployed. Streaming and compressing outputs..."
echo "===================================================="

SUCCESS_COUNT=0
FAILED_COUNT=0
FAILED_LIST=()

# Monitor and wait for the background jobs using sequential tracking indexes
for i in "${!PIDS[@]}"; do
    pid=${PIDS[$i]}
    script_name=${SCRIPT_NAMES[$i]}
    
    wait "$pid"
    
    if [ $? -eq 0 ]; then
        ((SUCCESS_COUNT++))
        echo "   ✅ [Thread Complete] $script_name finished successfully."
    else
        ((FAILED_COUNT++))
        FAILED_LIST+=("$script_name")
        echo "   ❌ [Thread Failed] $script_name encountered errors."
    fi
done

echo ""
echo "===================================================="
echo "📊 Master Performance Summary"
echo "===================================================="
echo "  Total Stack Databases Processed: ${#EXPORT_SCRIPTS[@]}"
echo "  Successfully Parallel Slices:     $SUCCESS_COUNT"
echo "  Failed Operations:               $FAILED_COUNT"

if [ $FAILED_COUNT -gt 0 ]; then
    echo ""
    echo "🚨 The following background processes threw errors:"
    for failed in "${FAILED_LIST[@]}"; do
        echo "    - $failed"
    done
    echo "===================================================="
    exit 1
else
    echo ""
    echo "🎉 Global compressed backup arrays generated in record time!"
    echo "===================================================="
    exit 0
fi
