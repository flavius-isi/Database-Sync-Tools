#!/bin/bash
HOST_GROUP="misc64"
REMOTE_DB_NAME="dash_staging_dev_copy"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/export.sh"
