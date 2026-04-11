#!/usr/bin/env bash
# tests/validate-fleet-refs.sh — CI: validate fleet ref referential integrity
#
# Checks that every `ref: <host>/<name>` entry in fleet YAML files resolves
# to an existing `agents/<host>/<name>.yaml` file.
#
# Fleet refs resolve by FILENAME STEM (lowercased spec.label), not by
# metadata.name. This script enforces that no fleet file references a
# non-existent agent.
#
# Usage:
#   ./tests/validate-fleet-refs.sh
#
# Exit codes:
#   0 = all refs resolve
#   1 = one or more dangling refs found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ERRORS=0
CHECKED=0

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq is required for fleet ref validation." >&2
    echo "  Install: curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq" >&2
    exit 1
fi

echo "Validating fleet ref referential integrity..."
echo ""

# Iterate over all fleet YAML files
while IFS= read -r -d '' fleet_file; do
    kind="$(yq eval '.kind // ""' "$fleet_file")"
    [[ "$kind" != "Fleet" ]] && continue

    fleet_name="$(yq eval '.metadata.name // ""' "$fleet_file")"
    fleet_rel="${fleet_file#"${REPO_ROOT}/"}"

    # Extract all ref values (pattern: <host>/<name>)
    mapfile -t refs < <(yq eval '.spec.agents[].ref // ""' "$fleet_file" 2>/dev/null | grep -v '^$' || true)

    if [[ ${#refs[@]} -eq 0 ]]; then
        echo "  ${fleet_rel} (${fleet_name}): no refs — skipping"
        continue
    fi

    echo "  ${fleet_rel} (${fleet_name}):"
    for ref in "${refs[@]}"; do
        CHECKED=$((CHECKED + 1))
        # ref format: <host>/<name>  →  agents/<host>/<name>.yaml
        agent_path="${REPO_ROOT}/agents/${ref}.yaml"
        printf "    ref: %-40s " "${ref}"
        if [[ -f "$agent_path" ]]; then
            echo "ok"
        else
            echo "FAIL (agents/${ref}.yaml not found)"
            ERRORS=$((ERRORS + 1))
        fi
    done
    echo ""

done < <(find "${REPO_ROOT}/fleets" -name "*.yaml" -print0 2>/dev/null)

echo "Checked: ${CHECKED} refs, Errors: ${ERRORS}"

if [[ $ERRORS -gt 0 ]]; then
    exit 1
fi
exit 0
