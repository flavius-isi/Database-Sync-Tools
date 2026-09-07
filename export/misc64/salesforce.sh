#!/bin/bash
HOST_GROUP="misc64"
REMOTE_DB_NAME="salesforce"
LOCAL_DB_NAME="misc64_salesforce"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/export.sh"
