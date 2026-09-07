#!/bin/bash
HOST_GROUP="misc64"
REMOTE_DB_NAME="dash"
LOCAL_DB_NAME="misc64_dash"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/export.sh"
