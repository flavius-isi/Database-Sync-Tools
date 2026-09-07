#!/bin/bash
HOST_GROUP="fpbx62"
REMOTE_DB_NAME="asteriskcdrdb"
LOCAL_DB_NAME="fpbx62_asteriskcdrdb"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/export.sh"
