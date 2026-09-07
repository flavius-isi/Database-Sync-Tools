#!/bin/bash
HOST_GROUP="misc62"
REMOTE_DB_NAME="slidev_salesforce"
LOCAL_DB_NAME="misc62_slidev_salesforce"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/export.sh"
