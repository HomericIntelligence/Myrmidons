#!/usr/bin/env bash
# scripts/lint-shell.sh — Run shellcheck on all shell scripts
#
# This script runs shellcheck (with --severity=warning) on all shell scripts
# found in the scripts/, tools/, tests/, and hooks/ directories.
#
# Usage:
#   ./scripts/lint-shell.sh
#
# Exit codes:
#   0 = no shellcheck warnings or errors
#   1 = shellcheck warnings or errors found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Find shellcheck: try system first, then pixi lint environment
SHELLCHECK_CMD="shellcheck"
if ! command -v shellcheck &>/dev/null; then
    if [[ -f "${REPO_ROOT}/.pixi/envs/lint/bin/shellcheck" ]]; then
        SHELLCHECK_CMD="${REPO_ROOT}/.pixi/envs/lint/bin/shellcheck"
    else
        echo "ERROR: shellcheck is required for shell linting." >&2
        echo "  Install: https://www.shellcheck.net/wiki/Install" >&2
        echo "  Or run: pixi run lint-shell" >&2
        exit 1
    fi
fi

echo "Running shellcheck on all shell scripts..."
echo ""

# Find and check all shell scripts and bats test files
find "${REPO_ROOT}/scripts" "${REPO_ROOT}/tools" "${REPO_ROOT}/tests" \
    "${REPO_ROOT}/hooks" \
    \( -name '*.sh' -o -name '*.bats' -o -name 'pre-commit' \) \
    | sort \
    | xargs "$SHELLCHECK_CMD" --severity=warning --enable=SC2154

echo ""
echo "Shell script linting complete."
