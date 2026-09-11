#!/usr/bin/env bash
# Compatibility entry point; fixtures and cases live in the canonical Bats suite.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bats "$SCRIPT_DIR/unit/test_validate.bats" "$@"
