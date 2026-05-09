#!/usr/bin/env bash
# scripts/lint-agents-md.sh — validate required sections in AGENTS.md
#
# Checks that all six required H2 sections are present in AGENTS.md.
# Prevents PRs from accidentally deleting or renaming a required section.
#
# Usage:
#   ./scripts/lint-agents-md.sh              # check AGENTS.md at repo root
#   ./scripts/lint-agents-md.sh path/to/AGENTS.md
#
# Exit codes:
#   0 = all required sections present
#   1 = one or more sections missing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET="${1:-${REPO_ROOT}/AGENTS.md}"

if [[ ! -f "$TARGET" ]]; then
    echo "ERROR: lint-agents-md: file not found: ${TARGET}"
    exit 1
fi

REQUIRED_SECTIONS=(
    "## Scope"
    "## Permitted Actions"
    "## Prohibited Actions"
    "## \`--dangerously-skip-permissions\` Policy"
    "## Fleet Coordination"
    "## Escalation — Human Review Required"
)

MISSING=0

for section in "${REQUIRED_SECTIONS[@]}"; do
    if ! grep -qF "$section" "$TARGET"; then
        echo "ERROR: lint-agents-md: required section missing from ${TARGET}: ${section}"
        MISSING=$((MISSING + 1))
    fi
done

if [[ $MISSING -gt 0 ]]; then
    echo ""
    echo "lint-agents-md: ${MISSING} required section(s) missing from AGENTS.md."
    echo "Restore the missing sections or update REQUIRED_SECTIONS in scripts/lint-agents-md.sh."
    exit 1
fi

exit 0
