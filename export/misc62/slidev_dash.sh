#!/bin/bash
HOST_GROUP="misc62"
REMOTE_DB_NAME="slidev_dash"
LOCAL_DB_NAME="misc62_slidev_dash"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/export.sh"
