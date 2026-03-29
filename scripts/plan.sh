#!/usr/bin/env bash
# scripts/plan.sh — Dry-run: show what apply.sh would do
#
# Compares desired state (YAML files) against actual state (Agamemnon API)
# and prints what changes would be made. Makes NO changes.
#
# Usage:
#   ./scripts/plan.sh                  # Plan all agents on all hosts
#   ./scripts/plan.sh hermes           # Plan agents for a specific host
#   ./scripts/plan.sh --fleet dev-mesh # Plan a specific fleet
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
FLEET=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --fleet) FLEET="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) HOST="$1"; shift ;;
        esac
    done
}

usage() {
    echo "Usage: $0 [host] [--fleet <fleet-name>]"
    echo ""
    echo "Shows what apply.sh would do without making any changes."
    echo ""
    echo "Examples:"
    echo "  $0                    # Plan all agents"
    echo "  $0 hermes             # Plan agents on hermes"
    echo "  $0 --fleet dev-mesh   # Plan dev-mesh fleet"
}

main() {
    parse_args "$@"
    check_deps
    agamemnon_check_connection

    local agents_json
    agents_json="$(agamemnon_list_agents)"

    local yaml_files
    mapfile -t yaml_files < <(get_agent_files "$HOST")

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
    report_unmanaged "$agents_json" "${yaml_files[@]}"

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
        "$label" "$program" "$workdir" "$args" "$desc")"

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

report_unmanaged() {
    local agents_json="$1"
    shift
    local yaml_files=("$@")

    # Collect all managed names
    local managed_names=()
    for yaml_file in "${yaml_files[@]}"; do
        local name
        name="$(yq eval '.metadata.name' "$yaml_file")"
        managed_names+=("$name")
    done

    # Find agents not in managed list
    echo "$agents_json" | jq -r '.[].name' | while IFS= read -r actual_name; do
        local is_managed=0
        for mn in "${managed_names[@]}"; do
            [[ "$mn" == "$actual_name" ]] && is_managed=1 && break
        done
        if [[ $is_managed -eq 0 ]]; then
            echo "[-] UNMANAGED ${actual_name} (in Agamemnon but not in desired state — use --prune to remove)"
        fi
    done
}

main "$@"
