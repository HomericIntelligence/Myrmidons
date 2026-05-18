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

# Idempotency sentinel (issue #657): if this script has already run inside
# the current pre-commit invocation (or any parent process tree that exported
# the marker), skip the re-run. The pre-commit hook config already sets
# `pass_filenames: false`, which should make pre-commit invoke the hook only
# once per run, but this guard is defensive against any future regression
# (duplicate hook id, wrapper that calls the script twice, etc.).
if [[ "${MYRMIDONS_FLEET_REFS_VALIDATED:-}" == "1" ]]; then
    echo "Fleet ref validation already ran in this pre-commit invocation — skipping."
    exit 0
fi
export MYRMIDONS_FLEET_REFS_VALIDATED=1

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

    # Track refs seen within THIS fleet so we can flag duplicates.
    # Bash 4+ associative array; key = ref string, value = first index seen.
    declare -A SEEN_REFS=()

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

            # Duplicate detection: a ref listed twice in the same fleet is an
            # authoring error — the consumer would reconcile the agent against
            # whichever entry it encountered last. Flag it loudly.
            if [[ -n "${SEEN_REFS[$ref]+x}" ]]; then
                echo "    FAIL (duplicate ref '${ref}' in ${fleet_rel}; first seen at index ${SEEN_REFS[$ref]}, repeated at index ${idx})"
                ERRORS=$((ERRORS + 1))
            else
                SEEN_REFS[$ref]="$idx"
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
    unset SEEN_REFS
    echo ""

done < <(find "${REPO_ROOT}/fleets" -name "*.yaml" -print0 2>/dev/null)

echo "Checked: ${CHECKED} refs, ${INLINE_CHECKED} inline agents, Errors: ${ERRORS}"

if [[ $ERRORS -gt 0 ]]; then
    exit 1
fi
exit 0
