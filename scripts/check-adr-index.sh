#!/usr/bin/env bash
# scripts/check-adr-index.sh — lint guard for ADR README index completeness
#
# Verifies that every *.md file in docs/adr/ (excluding README.md) appears
# as a link target in docs/adr/README.md.  Prevents index drift when a new
# ADR file is added without updating the table.
#
# Usage:
#   ./scripts/check-adr-index.sh          # scan all of docs/adr/
#   ./scripts/check-adr-index.sh file ...  # scan specific files (pre-commit mode)
#
# Exit codes:
#   0 = all ADR files are linked in README.md
#   1 = one or more ADR files are missing from README.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ADR_DIR="${REPO_ROOT}/docs/adr"
README="${ADR_DIR}/README.md"

MISSING=0

if [[ ! -f "$README" ]]; then
    echo "ERROR: ${README}: file not found — cannot check ADR index."
    exit 1
fi

# Collect ADR files to check: either from arguments or by scanning docs/adr/
if [[ $# -gt 0 ]]; then
    ADR_FILES=()
    for f in "$@"; do
        # Only include .md files inside docs/adr/ that are not the README itself
        [[ "$f" == *.md ]] || continue
        [[ "$(basename "$f")" == "README.md" ]] && continue
        [[ "$f" == *"/docs/adr/"* || "$(dirname "$(realpath "$f" 2>/dev/null || echo "$f")")" == "$ADR_DIR" ]] || continue
        ADR_FILES+=("$f")
    done
else
    mapfile -t ADR_FILES < <(find "$ADR_DIR" -maxdepth 1 -name "*.md" ! -name "README.md" | sort)
fi

for adr_file in "${ADR_FILES[@]}"; do
    [[ ! -f "$adr_file" ]] && continue
    filename="$(basename "$adr_file")"

    if ! grep -qF "$filename" "$README"; then
        echo "ERROR: ${README}: missing link for ${filename}"
        MISSING=$((MISSING + 1))
    fi
done

if [[ $MISSING -gt 0 ]]; then
    echo ""
    echo "check-adr-index: ${MISSING} ADR file(s) not linked in docs/adr/README.md."
    echo "Add a table entry for each missing ADR and re-run."
    exit 1
fi

exit 0
