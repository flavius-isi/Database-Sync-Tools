#!/bin/bash

# Target database name
DB_NAME="iapp2_dev_applications"

# Dynamically locate directory path and source shared core engine
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/export.sh"
