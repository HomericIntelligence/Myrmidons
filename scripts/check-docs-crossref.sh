#!/usr/bin/env bash
# scripts/check-docs-crossref.sh — lint guard for AGENTS.md cross-reference in CLAUDE.md
#
# Asserts:
#   1. AGENTS.md exists at the repo root.
#   2. CLAUDE.md exists at the repo root.
#   3. CLAUDE.md contains a reference to AGENTS.md.
#
# Usage:
#   ./scripts/check-docs-crossref.sh
#
# Exit codes:
#   0 = all checks pass
#   1 = one or more violations found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VIOLATIONS=0

# Check 1: AGENTS.md must exist at repo root
if [[ ! -f "${REPO_ROOT}/AGENTS.md" ]]; then
    echo "::error::AGENTS.md not found at repo root."
    VIOLATIONS=$((VIOLATIONS + 1))
fi

# Check 2: CLAUDE.md must exist at repo root
if [[ ! -f "${REPO_ROOT}/CLAUDE.md" ]]; then
    echo "::error::CLAUDE.md not found at repo root."
    VIOLATIONS=$((VIOLATIONS + 1))
elif ! grep -q 'AGENTS\.md' "${REPO_ROOT}/CLAUDE.md"; then
    echo "::error::CLAUDE.md: no reference to AGENTS.md found."
    echo "  Add a cross-reference line, e.g.:"
    echo "  > For agent safety boundaries and permitted tool use, see [AGENTS.md](AGENTS.md)."
    VIOLATIONS=$((VIOLATIONS + 1))
fi

if [[ $VIOLATIONS -gt 0 ]]; then
    echo ""
    echo "check-docs-crossref: FAILED: ${VIOLATIONS} violation(s)."
    exit 1
fi

echo "check-docs-crossref: PASSED."
exit 0
