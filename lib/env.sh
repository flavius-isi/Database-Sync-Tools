#!/bin/bash

# Determine project root from lib directory location
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$LIB_DIR/.." && pwd)"

# Load environment configuration (.env)
# Usage: load_env [require_env=false]
load_env() {
    local require_env="${1:-false}"
    local env_file="$PROJECT_ROOT/.env"

    if [ -f "$env_file" ]; then
        set -a
        # shellcheck disable=SC1090
        source "$env_file"
        set +a
    elif [ "$require_env" = "true" ]; then
        echo "⚠️  Configuration error: .env file not found at $env_file"
        echo "👉 Please copy .env.example to .env and configure your database credentials:"
        echo "   cp .env.example .env"
        exit 1
    fi
}

# Resolve remote database credentials based on host group
# Usage: get_remote_credentials <host_group>
get_remote_credentials() {
    local host_grp="$1"

    case "$host_grp" in
        misc61)
            REMOTE_HOST="$MISC61_HOST"
            REMOTE_PORT="${MISC61_PORT:-3306}"
            REMOTE_USER="$MISC61_USER"
            REMOTE_PASS="$MISC61_PASS"
            ;;
        misc62)
            REMOTE_HOST="$MISC62_HOST"
            REMOTE_PORT="${MISC62_PORT:-3306}"
            REMOTE_USER="$MISC62_USER"
            REMOTE_PASS="$MISC62_PASS"
            ;;
        misc63)
            REMOTE_HOST="$MISC63_HOST"
            REMOTE_PORT="${MISC63_PORT:-3306}"
            REMOTE_USER="$MISC63_USER"
            REMOTE_PASS="$MISC63_PASS"
            ;;
        misc64)
            REMOTE_HOST="$MISC64_HOST"
            REMOTE_PORT="${MISC64_PORT:-3306}"
            REMOTE_USER="$MISC64_USER"
            REMOTE_PASS="$MISC64_PASS"
            ;;
        fpbx62)
            REMOTE_HOST="$FPBX62_HOST"
            REMOTE_PORT="${FPBX62_PORT:-3306}"
            REMOTE_USER="$FPBX62_USER"
            REMOTE_PASS="$FPBX62_PASS"
            ;;
        *)
            REMOTE_HOST="${REMOTE_DB_HOST:-}"
            REMOTE_PORT="${REMOTE_DB_PORT:-3306}"
            REMOTE_USER="${REMOTE_DB_USER:-}"
            REMOTE_PASS="${REMOTE_DB_PASS:-}"
            ;;
    esac
}
