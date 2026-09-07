#!/bin/bash
HOST_GROUP="misc61"
REMOTE_DB_NAME="slicrm_dev"
LOCAL_DB_NAME="misc61_slicrm_dev"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/export.sh"
