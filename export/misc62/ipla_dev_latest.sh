#!/bin/bash
HOST_GROUP="misc62"
REMOTE_DB_NAME="ipla_dev_latest"
LOCAL_DB_NAME="misc62_ipla_dev_latest"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/export.sh"
