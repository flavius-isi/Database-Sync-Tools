#!/bin/bash

# Standard host directory across the project
KNOWN_HOSTS=(misc61 misc62 misc63 misc64 fpbx62)

# Prerequisite priority ordering to satisfy cross-database view dependencies
PRIORITY_DBS=(
    "misc64_dash"
    "misc64_salesforce"
    "misc62_slidev_dash"
    "misc62_slidev_salesforce"
)

# Resolve database engine for a host group (e.g. misc61 -> mariadb, misc64 -> mysql)
# Usage: get_engine_for_host <host_group>
get_engine_for_host() {
    local host_grp="$1"
    local upper_grp
    upper_grp=$(echo "$host_grp" | tr '[:lower:]' '[:upper:]')
    local engine_var="${upper_grp}_ENGINE"
    local engine="${!engine_var:-}"

    if [ -z "$engine" ]; then
        case "$host_grp" in
            misc61|misc62) engine="mariadb" ;;
            misc63|misc64|fpbx62) engine="mysql" ;;
            *)
                echo "❌ Error: Missing configuration for host '$host_grp'." >&2
                echo "   Please define ${engine_var}=<mysql|mariadb> in your .env file." >&2
                exit 1
                ;;
        esac
    fi
    echo "$engine"
}

# Resolve client binary with fallback support
# Usage: get_client_binary <engine>
get_client_binary() {
    local engine="$1"
    if [ "$engine" = "mariadb" ]; then
        if command -v mariadb &>/dev/null; then
            echo "mariadb"
        else
            echo "mysql"
        fi
    else
        echo "mysql"
    fi
}

# Resolve dump binary with fallback support
# Usage: get_dump_binary <engine>
get_dump_binary() {
    local engine="$1"
    if [ "$engine" = "mariadb" ]; then
        if command -v mariadb-dump &>/dev/null; then
            echo "mariadb-dump"
        else
            echo "mysqldump"
        fi
    else
        echo "mysqldump"
    fi
}

# Configure local target connection parameters based on database engine
# Usage: get_local_connection <engine>
# Sets: LOCAL_TARGET_HOST, LOCAL_TARGET_PORT, LOCAL_TARGET_USER, LOCAL_TARGET_PASS, LOCAL_CLIENT_BIN, LOCAL_CLIENT_ARGS
get_local_connection() {
    local engine="$1"

    if [ "$engine" = "mariadb" ]; then
        LOCAL_TARGET_HOST="${LOCAL_MARIADB_HOST:-127.0.0.1}"
        LOCAL_TARGET_PORT="${LOCAL_MARIADB_PORT:-3307}"
        LOCAL_TARGET_USER="${LOCAL_MARIADB_USER:-root}"
        LOCAL_TARGET_PASS="${LOCAL_MARIADB_PASS:-}"
        LOCAL_CLIENT_BIN=$(get_client_binary "mariadb")
        LOCAL_CLIENT_ARGS=(-u "$LOCAL_TARGET_USER" -h "$LOCAL_TARGET_HOST" -P "$LOCAL_TARGET_PORT" --skip-ssl)
    else
        LOCAL_TARGET_HOST="${LOCAL_MYSQL_HOST:-127.0.0.1}"
        LOCAL_TARGET_PORT="${LOCAL_MYSQL_PORT:-3306}"
        LOCAL_TARGET_USER="${LOCAL_MYSQL_USER:-root}"
        LOCAL_TARGET_PASS="${LOCAL_MYSQL_PASS:-}"
        LOCAL_CLIENT_BIN=$(get_client_binary "mysql")
        LOCAL_CLIENT_ARGS=(-u "$LOCAL_TARGET_USER" -h "$LOCAL_TARGET_HOST" -P "$LOCAL_TARGET_PORT")
    fi
}

# Configure extraction flags for export
# Usage: get_export_flags <engine>
# Sets: DUMP_STRUCT_FLAGS, DUMP_DATA_FLAGS, CLIENT_QUERY_FLAGS
get_export_flags() {
    local engine="$1"

    if [ "$engine" = "mariadb" ]; then
        DUMP_STRUCT_FLAGS=(--compress --single-transaction --skip-lock-tables --no-data)
        DUMP_DATA_FLAGS=(--compress --single-transaction --skip-lock-tables --no-create-info --skip-triggers)
        CLIENT_QUERY_FLAGS=(-C --skip-ssl)
    else
        DUMP_STRUCT_FLAGS=(--compression-algorithms=zlib --single-transaction --skip-lock-tables --no-data --no-tablespaces --set-gtid-purged=OFF)
        DUMP_DATA_FLAGS=(--compression-algorithms=zlib --single-transaction --skip-lock-tables --no-create-info --no-tablespaces --skip-triggers --set-gtid-purged=OFF)
        CLIENT_QUERY_FLAGS=(--compression-algorithms=zlib)
    fi
}

# Standardize local database names from file path or remote name
# Usage: resolve_local_db_name <file_or_name> [host_group]
resolve_local_db_name() {
    local target="$1"
    local host_grp="${2:-}"

    if [ -z "$host_grp" ]; then
        host_grp=$(basename "$(dirname "$target")")
    fi

    local raw_base
    raw_base=$(basename "$target" | sed -E 's/^latest_//' | sed -E 's/(_dump)?\.sql$//')

    if [ -n "$host_grp" ] && [[ "$raw_base" == "${host_grp}_"* ]]; then
        echo "$raw_base"
    elif [ "$host_grp" = "output" ] || [ -z "$host_grp" ]; then
        echo "$raw_base"
    else
        echo "${host_grp}_${raw_base}"
    fi
}
