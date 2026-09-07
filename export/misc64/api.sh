#!/bin/bash
HOST_GROUP="misc64"
REMOTE_DB_NAME="api"
LOCAL_DB_NAME="misc64_api"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/export.sh"
