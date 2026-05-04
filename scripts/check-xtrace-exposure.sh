#!/usr/bin/env bash
# scripts/check-xtrace-exposure.sh — lint guard for unguarded auth expansions in curl calls
#
# Scans shell scripts for curl invocations that expand ${AGAMEMNON_API_KEY} or
# ${_AUTH_HEADERS...} inline without a preceding { set +x; } xtrace guard.
# Under bash -x such expansions print bearer tokens to the trace log.
#
# A violation is a line that:
#   - calls curl AND
#   - expands ${AGAMEMNON_API_KEY} or ${_AUTH_HEADERS on the same line AND
#   - is NOT already protected by a { set +x; } guard on the same line
#
# Usage:
#   ./scripts/check-xtrace-exposure.sh               # scan scripts/ and hooks/
#   ./scripts/check-xtrace-exposure.sh file1.sh ...  # scan specific files
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
    mapfile -t FILES < <(find "${REPO_ROOT}/scripts" "${REPO_ROOT}/hooks" \
        -name "*.sh" 2>/dev/null | sort)
fi

for file in "${FILES[@]}"; do
    [[ ! -f "$file" ]] && continue

    FILES_CHECKED=$((FILES_CHECKED + 1))

    # A violation: a line contains curl AND an auth variable expansion
    # but does NOT contain the xtrace guard on the same line.
    while IFS= read -r match; do
        lineno="${match%%:*}"
        content="${match#*:}"

        # Skip comment lines (leading whitespace + #)
        if echo "$content" | grep -qE '^\s*#'; then
            continue
        fi

        # Skip lines that already have the set +x guard on them
        if echo "$content" | grep -qF '{ set +x; }'; then
            continue
        fi

        echo "ERROR: ${file}:${lineno}: curl call expands auth variable without xtrace guard."
        echo "       Wrap with: { set +x; } 2>/dev/null  ...  if [[ \$_had_xtrace -eq 1 ]]; then set -x; fi"
        VIOLATIONS=$((VIOLATIONS + 1))
    done < <(grep -n 'curl' "$file" 2>/dev/null \
        | grep -E '\$\{AGAMEMNON_API_KEY[^}]*\}|\$\{_AUTH_HEADERS' \
        || true)
done

if [[ $VIOLATIONS -gt 0 ]]; then
    echo ""
    echo "check-xtrace-exposure: ${VIOLATIONS} violation(s) found in ${FILES_CHECKED} file(s)."
    echo "Auth header expansions in curl calls must be wrapped with the set +x xtrace guard."
    exit 1
fi

exit 0
