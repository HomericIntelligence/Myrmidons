#!/usr/bin/env bash
# tests/detect-doc-drift.sh — CI: detect documentation overclaims
#
# Scans documentation files for phrases that imply an active Nomad integration
# when none exists. Fails if any forbidden pattern is found.
#
# Used by .github/workflows/validate.yml on every PR.
# Also runnable locally via: just test-drift
#
# Exit codes:
#   0 = no drift detected
#   1 = overclaiming documentation found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ERRORS=0
CHECKED=0

# Forbidden phrases: patterns that imply Nomad is currently integrated.
# Extend this list as new overclaims are identified.
#
# Format: "PATTERN|Human-readable description of what this catches"
FORBIDDEN_PHRASES=(
    "Myrmidons.*Nomad.*cluster|implies Myrmidons actively drives a Nomad cluster"
    "apply\.sh.*Nomad|implies apply.sh submits Nomad jobs"
    "Nomad integration.*implemented|implies Nomad integration is complete"
    "Nomad.*currently supported|implies Nomad is currently supported"
    "spec\.model.*reconcil|implies spec.model changes are reconciled by apply.sh"
    "spec\.deployment\.type.*reconcil|implies spec.deployment.type changes are reconciled"
    "spec\.model.*✓|implies spec.model is tracked for drift (table row with checkmark)"
    "spec\.deployment\.type.*✓|implies spec.deployment.type is tracked for drift (table row with checkmark)"
    "spec\.model (is |are )?tracked|implies spec.model is tracked for drift"
    "spec\.deployment\.type (is |are )?tracked|implies spec.deployment.type is tracked for drift (it is not)"
)

# Files and directories to scan (relative to repo root).
# ADR files (docs/adr/) are excluded: they document architecture decisions and
# intentionally discuss unimplemented features in context.
DOC_FILES=()
while IFS= read -r -d '' f; do
    DOC_FILES+=("$f")
done < <(find "${REPO_ROOT}" \
    -not -path "${REPO_ROOT}/.worktrees/*" \
    \( -name "Architecture.md" -o -name "README.md" -o -name "CLAUDE.md" \
       -o -name "CONTRIBUTING.md" \) \
    -print0 2>/dev/null)

while IFS= read -r -d '' f; do
    DOC_FILES+=("$f")
done < <(find "${REPO_ROOT}/docs" -name "*.md" \
    -not -path "*/adr/*" \
    -print0 2>/dev/null)

if [[ ${#DOC_FILES[@]} -eq 0 ]]; then
    echo "No documentation files found to check."
    exit 0
fi

echo "Checking documentation for overclaims..."
echo ""

for file in "${DOC_FILES[@]}"; do
    rel="${file#"${REPO_ROOT}/"}"
    file_errors=0

    for entry in "${FORBIDDEN_PHRASES[@]}"; do
        pattern="${entry%%|*}"
        description="${entry#*|}"

        if grep -Eiq "${pattern}" "${file}" 2>/dev/null; then
            if [[ $file_errors -eq 0 ]]; then
                echo "  FAIL: ${rel}"
            fi
            echo "        - Pattern '${pattern}' matched: ${description}"
            file_errors=$((file_errors + 1))
            ERRORS=$((ERRORS + 1))
        fi
    done

    if [[ $file_errors -eq 0 ]]; then
        echo "  ok:   ${rel}"
    fi

    CHECKED=$((CHECKED + 1))
done

echo ""
echo "Checked: ${CHECKED} files, Errors: ${ERRORS}"

if [[ $ERRORS -gt 0 ]]; then
    echo "" >&2
    echo "Documentation drift detected. Review the patterns that matched above:" >&2
    echo "  - If an implementation has been completed, update this test to reflect the new reality." >&2
    echo "  - If no implementation exists, remove the overclaiming language from the docs." >&2
    echo "See docs/adr/ADR-007-nomad-integration-strategy.md for context." >&2
    exit 1
fi

exit 0
