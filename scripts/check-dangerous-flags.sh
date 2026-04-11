#!/usr/bin/env bash
# scripts/check-dangerous-flags.sh — lint guard for --dangerously-skip-permissions
#
# Scans agent and fleet YAML files for bare --dangerously-skip-permissions flags
# that are NOT accompanied by a suppression annotation on the same line.
#
# Suppression format (inline, same line as programArgs):
#   programArgs: "--dangerously-skip-permissions" # skip-permissions-lint: <justification>
#
# Usage:
#   ./scripts/check-dangerous-flags.sh                  # scan agents/ and fleets/
#   ./scripts/check-dangerous-flags.sh file1.yaml ...   # scan specific files
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
    # Skip template files (they may document the flag without using it)
    [[ "$file" == *"/_templates/"* ]] && continue

    FILES_CHECKED=$((FILES_CHECKED + 1))

    # Find lines containing --dangerously-skip-permissions
    # A line is a violation if it contains the flag but does NOT contain
    # the suppression annotation "# skip-permissions-lint:"
    while IFS= read -r line; do
        lineno="${line%%:*}"
        content="${line#*:}"

        if echo "$content" | grep -q -- '--dangerously-skip-permissions'; then
            if ! echo "$content" | grep -q '# skip-permissions-lint:'; then
                echo "ERROR: ${file}:${lineno}: --dangerously-skip-permissions used without suppression annotation."
                echo "       To suppress: append  # skip-permissions-lint: <justification>  on the same line."
                VIOLATIONS=$((VIOLATIONS + 1))
            fi
        fi
    done < <(grep -n -- '--dangerously-skip-permissions' "$file" 2>/dev/null || true)
done

if [[ $VIOLATIONS -gt 0 ]]; then
    echo ""
    echo "check-dangerous-flags: ${VIOLATIONS} violation(s) found in ${FILES_CHECKED} file(s)."
    echo "Remove --dangerously-skip-permissions or add a # skip-permissions-lint: <justification> annotation."
    exit 1
fi

exit 0
