#!/usr/bin/env bash
# scripts/check-schema-hints.sh — lint guard for yaml-language-server schema hints
#
# Validates that every agent and fleet YAML file begins with a correctly-formed
# yaml-language-server schema hint comment:
#
#   # yaml-language-server: $schema=<path-or-url>
#
# A missing or malformed hint (e.g. "# yaml-language-server: schema=..." without
# the "$") is a violation.  Files may suppress enforcement by placing a
# suppression annotation on line 1:
#
#   # schema-hint-skip: <justification>
#
# Usage:
#   ./scripts/check-schema-hints.sh                  # scan agents/ and fleets/
#   ./scripts/check-schema-hints.sh file1.yaml ...   # scan specific files
#
# Exit codes:
#   0 = no violations
#   1 = violations found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VIOLATIONS=0
FILES_CHECKED=0

# Collect files to scan
if [[ $# -gt 0 ]]; then
    FILES=("$@")
else
    # Default: scan all YAML files under agents/ and fleets/
    mapfile -t FILES < <(find "${REPO_ROOT}/agents" "${REPO_ROOT}/fleets" \
        -name "*.yaml" -o -name "*.yml" 2>/dev/null | sort)
fi

for file in "${FILES[@]}"; do
    [[ ! -f "$file" ]] && continue
    # Skip template files (they document the format, not enforce it)
    [[ "$file" == *"/_templates/"* ]] && continue

    FILES_CHECKED=$((FILES_CHECKED + 1))

    first_line="$(head -1 "$file")"

    # Pass: correct canonical hint
    if echo "$first_line" | grep -qE '^# yaml-language-server: \$schema=.+'; then
        continue
    fi

    # Pass: suppression annotation
    if echo "$first_line" | grep -qE '^# schema-hint-skip:'; then
        continue
    fi

    echo "ERROR: ${file}:1: missing or malformed yaml-language-server schema hint."
    echo "       Line 1 is: ${first_line}"
    echo "       Expected:  # yaml-language-server: \$schema=<path-or-url>"
    echo "       To suppress: replace line 1 with  # schema-hint-skip: <justification>"
    VIOLATIONS=$((VIOLATIONS + 1))
done

if [[ $VIOLATIONS -gt 0 ]]; then
    echo ""
    echo "check-schema-hints: ${VIOLATIONS} violation(s) found in ${FILES_CHECKED} file(s)."
    echo "Add '# yaml-language-server: \$schema=<path>' as line 1, or suppress with '# schema-hint-skip: <justification>'."
    exit 1
fi

exit 0
