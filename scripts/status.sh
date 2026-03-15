#!/usr/bin/env bash
# scripts/status.sh — Compare desired vs actual state
#
# Shows a formatted table of all managed agents with their desired state,
# actual state, and whether there's any drift.
#
# Usage:
#   ./scripts/status.sh                # Status of all agents
#   ./scripts/status.sh hermes         # Status of agents on a specific host

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/api.sh
source "${SCRIPT_DIR}/lib/api.sh"
# shellcheck source=scripts/lib/reconcile.sh
source "${SCRIPT_DIR}/lib/reconcile.sh"

HOST="${1:-}"

main() {
    check_deps
    aim_check_connection

    local agents_json
    agents_json="$(aim_list_agents)"

    local yaml_files
    mapfile -t yaml_files < <(get_agent_files "$HOST")

    # Header
    printf "%-22s %-10s %-12s %-12s %s\n" "AGENT" "HOST" "DESIRED" "ACTUAL" "DRIFT"
    printf "%-22s %-10s %-12s %-12s %s\n" "-----" "----" "-------" "------" "-----"

    for yaml_file in "${yaml_files[@]}"; do
        status_agent "$yaml_file" "$agents_json"
    done

    # Unmanaged agents
    report_unmanaged "$agents_json" "${yaml_files[@]}"
}

status_agent() {
    local yaml_file="$1"
    local agents_json="$2"

    local name host desired_state label program workdir args desc
    name="$(yq eval '.metadata.name' "$yaml_file")"
    host="$(yq eval '.metadata.host // "hermes"' "$yaml_file")"
    desired_state="$(yq eval '.spec.desiredState // "active"' "$yaml_file")"
    label="$(yq eval '.spec.label // ""' "$yaml_file")"
    program="$(yq eval '.spec.program // ""' "$yaml_file")"
    workdir="$(yq eval '.spec.workingDirectory // ""' "$yaml_file")"
    args="$(yq eval '.spec.programArgs // ""' "$yaml_file")"
    desc="$(yq eval '.spec.taskDescription // ""' "$yaml_file")"

    local actual_json
    actual_json="$(echo "$agents_json" | jq -r --arg n "$name" '.[] | select(.name == $n)')"

    if [[ -z "$actual_json" ]]; then
        printf "%-22s %-10s %-12s %-12s %s\n" \
            "${name:0:21}" "${host:0:9}" "$desired_state" "MISSING" "NEEDS CREATE"
        return
    fi

    local actual_status
    actual_status="$(echo "$actual_json" | jq -r '.status // "unknown"')"

    local drift
    drift="$(compute_drift "$name" "$desired_state" "$actual_json" \
        "$label" "$program" "$workdir" "$args" "$desc")"

    local drift_display
    case "$drift" in
        UNCHANGED)
            drift_display="ok"
            ;;
        WAKE)
            drift_display="NEEDS WAKE"
            ;;
        HIBERNATE)
            drift_display="NEEDS HIBERNATE"
            ;;
        UPDATE:*)
            drift_display="drifted: ${drift#UPDATE:}"
            ;;
        *)
            drift_display="$drift"
            ;;
    esac

    printf "%-22s %-10s %-12s %-12s %s\n" \
        "${name:0:21}" "${host:0:9}" "$desired_state" "$actual_status" "$drift_display"
}

report_unmanaged() {
    local agents_json="$1"
    shift
    local yaml_files=("$@")

    local managed_names=()
    for yaml_file in "${yaml_files[@]}"; do
        local n
        n="$(yq eval '.metadata.name' "$yaml_file")"
        managed_names+=("$n")
    done

    while IFS= read -r actual_name; do
        local is_managed=0
        for mn in "${managed_names[@]}"; do
            [[ "$mn" == "$actual_name" ]] && is_managed=1 && break
        done

        if [[ $is_managed -eq 0 ]]; then
            local actual_status
            actual_status="$(echo "$agents_json" | jq -r --arg n "$actual_name" \
                '.[] | select(.name == $n) | .status // "unknown"')"
            printf "%-22s %-10s %-12s %-12s %s\n" \
                "${actual_name:0:21}" "-" "-" "$actual_status" "UNMANAGED"
        fi
    done < <(echo "$agents_json" | jq -r '.[].name')
}

main "$@"
