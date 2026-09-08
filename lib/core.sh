#!/bin/bash

# ====================================================
# Core Module Entry Point
# ====================================================
# Sources environment management and database helper libraries

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/env.sh
source "$LIB_DIR/env.sh"

# shellcheck source=lib/db.sh
source "$LIB_DIR/db.sh"
