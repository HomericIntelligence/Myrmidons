#!/usr/bin/env bash
# tests/validate-fleet-refs.sh — CI: validate fleet ref referential integrity
#
# Checks that every `ref: <host>/<name>` entry in fleet YAML files resolves
# to an existing `agents/<host>/<name>.yaml` file.
#
# Also validates inline agent definitions (entries without a `ref:` field)
# for required fields: name, program, and workingDirectory.
#
# Fleet refs resolve by FILENAME STEM (lowercased spec.label), not by
# metadata.name. This script enforces that no fleet file references a
# non-existent agent.
#
# Usage:
#   ./tests/validate-fleet-refs.sh
#
# Exit codes:
#   0 = all refs resolve and all inline agents are valid
#   1 = one or more dangling refs or invalid inline agents found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ERRORS=0
CHECKED=0
INLINE_CHECKED=0

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq is required for fleet ref validation." >&2
    echo "  Install: curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq" >&2
    exit 1
fi

echo "Validating fleet ref referential integrity and inline agent definitions..."
echo ""

# Warn if fleets/ directory is missing (issue #656)
if [[ ! -d "${REPO_ROOT}/fleets" ]]; then
    echo "WARNING: ${REPO_ROOT}/fleets directory not found — ref validation skipped (check REPO_ROOT)" >&2
fi

# Iterate over all fleet YAML files
while IFS= read -r -d '' fleet_file; do
    kind="$(yq eval '.kind // ""' "$fleet_file")"
    [[ "$kind" != "Fleet" ]] && continue

    fleet_name="$(yq eval '.metadata.name // ""' "$fleet_file")"
    fleet_rel="${fleet_file#"${REPO_ROOT}/"}"

    # Count total agents in the fleet
    agent_count="$(yq eval '.spec.agents | length' "$fleet_file" 2>/dev/null || echo 0)"

    if [[ "$agent_count" -eq 0 ]]; then
        echo "  ${fleet_rel} (${fleet_name}): no agents — skipping"
        continue
    fi

    echo "  ${fleet_rel} (${fleet_name}):"

    # Process each agent entry by index
    for (( idx=0; idx<agent_count; idx++ )); do
        ref="$(yq eval ".spec.agents[${idx}].ref // \"\"" "$fleet_file" 2>/dev/null || true)"

        if [[ -n "$ref" ]]; then
            # --- ref entry: validate that the target file exists ---
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
        else
            # --- inline agent: validate required fields ---
            INLINE_CHECKED=$((INLINE_CHECKED + 1))
            inline_name="$(yq eval ".spec.agents[${idx}].name // \"\"" "$fleet_file" 2>/dev/null || true)"
            inline_program="$(yq eval ".spec.agents[${idx}].program // \"\"" "$fleet_file" 2>/dev/null || true)"
            inline_workdir="$(yq eval ".spec.agents[${idx}].workingDirectory // \"\"" "$fleet_file" 2>/dev/null || true)"

            display_name="${inline_name:-<unnamed>}"
            printf "    inline[%d] %-36s " "${idx}" "${display_name}:"

            inline_errors=()
            [[ -z "$inline_name" ]] && inline_errors+=("name is required")
            [[ -z "$inline_program" ]] && inline_errors+=("program is required")
            [[ -z "$inline_workdir" ]] && inline_errors+=("workingDirectory is required")

            if [[ ${#inline_errors[@]} -eq 0 ]]; then
                echo "ok"
            else
                echo "FAIL"
                for err in "${inline_errors[@]}"; do
                    echo "      - ${err}"
                done
                ERRORS=$((ERRORS + 1))
            fi
        fi
    done
    echo ""

done < <(find "${REPO_ROOT}/fleets" -name "*.yaml" -print0 2>/dev/null)

echo "Checked: ${CHECKED} refs, ${INLINE_CHECKED} inline agents, Errors: ${ERRORS}"

if [[ $ERRORS -gt 0 ]]; then
    exit 1
fi
exit 0
