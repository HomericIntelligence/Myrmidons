#!/usr/bin/env bash
# tests/validate-schemas.sh — CI: validate all agent and fleet YAML files
#
# Uses check-jsonschema (schemas/agent-v1.schema.json and fleet-v1.schema.json)
# as the single source of truth for field definitions, types, and enum values.
#
# Used by .github/workflows/validate.yml on every PR.
#
# Usage:
#   ./tests/validate-schemas.sh
#
# Exit codes:
#   0 = all valid
#   1 = validation errors found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

AGENT_SCHEMA="${REPO_ROOT}/schemas/agent-v1.schema.json"
FLEET_SCHEMA="${REPO_ROOT}/schemas/fleet-v1.schema.json"

ERRORS=0
CHECKED=0

if ! command -v check-jsonschema &>/dev/null; then
    echo "ERROR: check-jsonschema is required for schema validation." >&2
    echo "  Install via pixi: pixi install" >&2
    echo "  Or via pip: pip install check-jsonschema" >&2
    exit 1
fi

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq is required for YAML parsing." >&2
    exit 1
fi

echo "Validating all agent and fleet YAML files..."
echo ""

# Find all YAML files (excluding templates)
while IFS= read -r -d '' file; do
    [[ "$file" == *"/_templates/"* ]] && continue

    CHECKED=$((CHECKED + 1))
    rel="${file#"${REPO_ROOT}/"}"
    echo -n "  ${rel}: "

    # YAML syntax check
    if ! yq eval '.' "$file" > /dev/null 2>&1; then
        echo "FAIL (invalid YAML syntax)"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    kind="$(yq eval '.kind // ""' "$file")"

    case "$kind" in
        Agent)
            schema="$AGENT_SCHEMA"
            ;;
        Fleet)
            schema="$FLEET_SCHEMA"
            ;;
        *)
            echo "FAIL (unknown kind '${kind}'; expected 'Agent' or 'Fleet')"
            ERRORS=$((ERRORS + 1))
            continue
            ;;
    esac

    # check-jsonschema requires JSON; convert YAML on the fly
    if error_output="$(yq eval -o=json '.' "$file" 2>&1 | \
            check-jsonschema --schemafile "$schema" /dev/stdin 2>&1)"; then
        name="$(yq eval '.metadata.name // ""' "$file")"
        echo "ok (${kind}: ${name})"
    else
        echo "FAIL"
        # Indent error output for readability
        while IFS= read -r line; do
            echo "      ${line}"
        done <<< "$error_output"
        ERRORS=$((ERRORS + 1))
    fi

done < <(find "${REPO_ROOT}/agents" "${REPO_ROOT}/fleets" \
    -name "*.yaml" -print0 2>/dev/null)

echo ""
echo "Checked: ${CHECKED} files, Errors: ${ERRORS}"

if [[ $ERRORS -gt 0 ]]; then
    exit 1
fi

# Also validate fleet ref referential integrity
echo ""
"${SCRIPT_DIR}/validate-fleet-refs.sh"
