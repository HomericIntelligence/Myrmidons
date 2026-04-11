#!/usr/bin/env bash
# scripts/plan.sh — Dry-run: show what apply.sh would do
#
# Compares desired state (YAML files) against actual state (Agamemnon API)
# and prints what changes would be made. Makes NO changes.
#
# Usage:
#   ./scripts/plan.sh                  # Plan all agents on all hosts
#   ./scripts/plan.sh hermes           # Plan agents for a specific host
#
# Exit codes:
#   0 = no changes needed
#   1 = changes would be made (or error)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/api.sh
source "${SCRIPT_DIR}/lib/api.sh"
# shellcheck source=scripts/lib/reconcile.sh
source "${SCRIPT_DIR}/lib/reconcile.sh"

HOST=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            *) HOST="$1"; shift ;;
        esac
    done
}

usage() {
    echo "Usage: $0 [host]"
    echo ""
    echo "Shows what apply.sh would do without making any changes."
    echo ""
    echo "Examples:"
    echo "  $0                    # Plan all agents"
    echo "  $0 hermes             # Plan agents on hermes"
}

main() {
    parse_args "$@"
    check_deps
    agamemnon_check_connection

    local agents_json
    agents_json="$(agamemnon_list_agents)"

    local yaml_files
    if [[ -n "$FLEET" ]]; then
        local fleet_file
        fleet_file="$(find_fleet_file "$FLEET")" || exit 1
        mapfile -t yaml_files < <(resolve_fleet_files "$fleet_file")
    else
        mapfile -t yaml_files < <(get_agent_files "$HOST")
    fi

    if [[ ${#yaml_files[@]} -eq 0 ]]; then
        echo "No agent YAML files found."
        exit 0
    fi

    local has_changes=0

    echo "Plan for ${AGAMEMNON_URL} (dry-run — no changes will be made)"
    echo "================================================================"
    echo ""

    for yaml_file in "${yaml_files[@]}"; do
        plan_agent "$yaml_file" "$agents_json" || has_changes=1
    done

    # Report unmanaged agents (in Agamemnon but not in YAML)
    echo ""
    echo "Checking for unmanaged agents..."
    while IFS= read -r actual_name; do
        echo "[-] UNMANAGED ${actual_name} (in Agamemnon but not in desired state — use --prune to remove)"
    done < <(get_unmanaged_names "$agents_json" "${yaml_files[@]}")

    cleanup_fleet_tmpdir

    echo ""
    if [[ $has_changes -eq 0 ]]; then
        echo "No changes needed. Desired state matches actual state."
        exit 0
    else
        echo "Changes would be made. Run ./scripts/apply.sh to apply."
        exit 1
    fi
}

plan_agent() {
    local yaml_file="$1"
    local agents_json="$2"

    # Parse YAML fields
    local fields
    declare -A fields
    while IFS='=' read -r key value; do
        fields["$key"]="${value}"
    done < <(parse_agent_yaml "$yaml_file")

    local name="${fields[name]}"
    local desired_state="${fields[desiredState]:-active}"
    local label="${fields[label]:-}"
    local program="${fields[program]:-}"
    local workdir="${fields[workingDirectory]:-}"
    local args="${fields[programArgs]:-}"
    local desc="${fields[taskDescription]:-}"
    local model="${fields[model]:-}"
    local owner="${fields[owner]:-}"
    local role="${fields[role]:-member}"
    local deploy_type="${fields[deploymentType]:-local}"

    # Look up in actual state
    local actual_json
    actual_json="$(echo "$agents_json" | jq -r --arg name "$name" \
        '.[] | select(.name == $name)')"

    if [[ -z "$actual_json" ]]; then
        echo "[+] CREATE ${name} (program=${program}, deploy=${fields[deploymentType]:-local})"
        if [[ "$desired_state" == "active" ]]; then
            echo "    └─ WAKE after create"
        fi
        return 1
    fi

    local action
    action="$(compute_drift "$name" "$desired_state" "$actual_json" \
        "$label" "$program" "$workdir" "$args" "$desc" "${fields[tags]:-}" \
        "$model" "$owner" "$role" "$deploy_type")"

    case "$action" in
        UNCHANGED)
            echo "[=] UNCHANGED ${name}"
            ;;
        WAKE)
            echo "[!] WAKE ${name} (desired=active, actual=$(echo "$actual_json" | jq -r '.status'))"
            return 1
            ;;
        HIBERNATE)
            echo "[z] HIBERNATE ${name} (desired=hibernated, actual=$(echo "$actual_json" | jq -r '.status'))"
            return 1
            ;;
        UPDATE:*)
            local fields_changed="${action#UPDATE:}"
            echo "[~] UPDATE ${name}: ${fields_changed} differ"
            return 1
            ;;
    esac

    return 0
}

main "$@"
