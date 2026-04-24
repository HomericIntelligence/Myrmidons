#!/usr/bin/env bash
# scripts/lint-names.sh — Check for duplicate metadata.name across agents and fleets
#
# This script validates that all metadata.name values are unique across all agent
# and fleet YAML files in the agents/ and fleets/ directories.
#
# Usage:
#   ./scripts/lint-names.sh
#
# Exit codes:
#   0 = all names are unique
#   1 = duplicate names found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ERRORS=0

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq is required for name validation." >&2
    echo "  Install: https://github.com/mikefarah/yq" >&2
    exit 1
fi

echo "Checking metadata.name uniqueness across all agents and fleets..."

# Associative array to track names for uniqueness check
declare -A metadata_names

# Find all YAML files (excluding templates)
while IFS= read -r -d '' file; do
    [[ "$file" == *"/_templates/"* ]] && continue

    # Extract metadata.name
    name="$(yq eval '.metadata.name // ""' "$file" 2>/dev/null || true)"

    # Track names for uniqueness check (only non-empty names to avoid false positives)
    if [[ -n "$name" ]]; then
        metadata_names["$name"]+=" $file"
    fi

done < <(find "${REPO_ROOT}/agents" "${REPO_ROOT}/fleets" \
    -name "*.yaml" -print0 2>/dev/null)

# Cross-file name uniqueness check
for name in "${!metadata_names[@]}"; do
    files_with_name="${metadata_names[$name]}"
    # Count non-empty tokens (file paths are separated by spaces)
    count=0
    for f in $files_with_name; do
        [[ -n "$f" ]] && count=$((count + 1))
    done
    if [[ $count -gt 1 ]]; then
        echo "ERROR: duplicate metadata.name '${name}' found in:"
        for f in $files_with_name; do
            [[ -n "$f" ]] && echo "  - ${f#"${REPO_ROOT}/"}"
        done
        ERRORS=$((ERRORS + 1))
    fi
done

if [[ $ERRORS -gt 0 ]]; then
    echo ""
    echo "lint-names: ${ERRORS} duplicate name(s) found."
    exit 1
fi

echo "All metadata.name values are unique."
exit 0
