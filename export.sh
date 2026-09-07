#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "===================================================="
echo "🌍 Master Host-Based Database Export Orchestrator"
echo "===================================================="

# Pre-flight check: verify .env exists
ENV_FILE="$SCRIPT_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "⚠️  Configuration error: .env file not found at $ENV_FILE"
    echo "👉 Please copy .env.example to .env and configure your database credentials:"
    echo "   cp .env.example .env"
    exit 1
fi

TARGET="${1:-}"

shopt -s nullglob
AVAILABLE_HOSTS=(misc61 misc62 misc63 misc64 fpbx62)

if [ -z "$TARGET" ]; then
    echo "Usage: ./export.sh <host_group|all>"
    echo ""
    echo "Available host targets:"
    for h in "${AVAILABLE_HOSTS[@]}"; do
        count=$(find "$SCRIPT_DIR/export/$h" -name "*.sh" 2>/dev/null | wc -l | tr -d ' ')
        echo "  - $h ($count database targets)"
    done
    echo "  - all    (All hosts concurrently)"
    echo ""
    echo "Example: ./export.sh misc62"
    exit 1
fi

EXPORT_SCRIPTS=()

if [ "$TARGET" = "all" ]; then
    for h in "${AVAILABLE_HOSTS[@]}"; do
        for script in "$SCRIPT_DIR/export/$h"/*.sh; do
            EXPORT_SCRIPTS+=("$script")
        done
    done
else
    TARGET_DIR="$SCRIPT_DIR/export/$TARGET"
    if [ ! -d "$TARGET_DIR" ]; then
        echo "❌ Unknown host target: '$TARGET'"
        echo "   Available targets: ${AVAILABLE_HOSTS[*]} all"
        exit 1
    fi
    for script in "$TARGET_DIR"/*.sh; do
        EXPORT_SCRIPTS+=("$script")
    done
fi

if [ ${#EXPORT_SCRIPTS[@]} -eq 0 ]; then
    echo "❌ No export scripts found for target '$TARGET'."
    exit 1
fi

PIDS=()
SCRIPT_LABELS=()

echo "⚡ Launching ${#EXPORT_SCRIPTS[@]} extractions concurrently for target: [$TARGET]..."
echo "===================================================="

for script in "${EXPORT_SCRIPTS[@]}"; do
    script_dir=$(dirname "$script")
    host_group=$(basename "$script_dir")
    script_name=$(basename "$script")
    label="$host_group/$script_name"
    
    (cd "$script_dir" && bash "./$script_name") &
    PIDS+=($!)
    SCRIPT_LABELS+=("$label")
done

echo "⏳ All extraction workers deployed. Streaming outputs..."
echo "===================================================="

SUCCESS_COUNT=0
FAILED_COUNT=0
FAILED_LIST=()

for i in "${!PIDS[@]}"; do
    pid=${PIDS[$i]}
    label=${SCRIPT_LABELS[$i]}
    
    wait "$pid"
    
    if [ $? -eq 0 ]; then
        ((SUCCESS_COUNT++))
        echo "   ✅ [Thread Complete] $label finished successfully."
    else
        ((FAILED_COUNT++))
        FAILED_LIST+=("$label")
        echo "   ❌ [Thread Failed] $label encountered errors."
    fi
done

echo ""
echo "===================================================="
echo "📊 Master Export Performance Summary"
echo "===================================================="
echo "  Target Scope:               $TARGET"
echo "  Total Databases Processed:   ${#EXPORT_SCRIPTS[@]}"
echo "  Successful Parallel Slices: $SUCCESS_COUNT"
echo "  Failed Operations:          $FAILED_COUNT"

if [ $FAILED_COUNT -gt 0 ]; then
    echo ""
    echo "🚨 The following extractions encountered errors:"
    for failed in "${FAILED_LIST[@]}"; do
        echo "    - $failed"
    done
    echo "===================================================="
    exit 1
else
    echo ""
    echo "🎉 All requested databases sliced and exported successfully!"
    echo "===================================================="
    exit 0
fi
