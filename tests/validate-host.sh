#!/usr/bin/env bash
# tests/validate-host.sh — Test host parameter validation
#
# Tests that validate_host() in reconcile.sh correctly accepts valid
# host names and rejects path traversal attempts.
#
# Usage:
#   ./tests/validate-host.sh
#
# Exit codes:
#   0 = all tests passed
#   1 = one or more tests failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load only the functions we need (without executing main)
# shellcheck source=scripts/lib/reconcile.sh
source "${REPO_ROOT}/scripts/lib/reconcile.sh"

PASS=0
FAIL=0

assert_valid() {
    local host="$1"
    if validate_host "$host" 2>/dev/null; then
        echo "PASS: validate_host('${host}') accepted"
        PASS=$((PASS + 1))
    else
        echo "FAIL: validate_host('${host}') should be valid but was rejected"
        FAIL=$((FAIL + 1))
    fi
}

assert_invalid() {
    local host="$1"
    if ! validate_host "$host" 2>/dev/null; then
        echo "PASS: validate_host('${host}') rejected"
        PASS=$((PASS + 1))
    else
        echo "FAIL: validate_host('${host}') should be rejected but was accepted"
        FAIL=$((FAIL + 1))
    fi
}

echo "Testing validate_host()..."
echo ""

# Valid host names
assert_valid ""
assert_valid "hermes"
assert_valid "hermes-1"
assert_valid "my_host"
assert_valid "MyHost"
assert_valid "host123"
assert_valid "a"

# Path traversal attempts
assert_invalid "../etc"
assert_invalid "../../etc/passwd"
assert_invalid "../"
assert_invalid ".."
assert_invalid "."
assert_invalid "host/subdir"
assert_invalid "/etc/passwd"
assert_invalid "host name"
assert_invalid "host;rm -rf"
assert_invalid 'host$(whoami)'
assert_invalid "host\$(id)"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
