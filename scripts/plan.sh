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

# shellcheck source=scripts/lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"
# shellcheck source=scripts/lib/api.sh
source "${SCRIPT_DIR}/lib/api.sh"
# shellcheck source=scripts/lib/reconcile.sh
source "${SCRIPT_DIR}/lib/reconcile.sh"

HOST=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            --dry-run) shift ;;
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
    mapfile -t yaml_files < <(get_agent_files "$HOST")

    if [[ ${#yaml_files[@]} -eq 0 ]]; then
        log_info "No agent YAML files found."
        exit 0
    fi

    local has_changes=0
    local CREATE_COUNT=0
    local UPDATE_COUNT=0
    local WAKE_COUNT=0
    local HIBERNATE_COUNT=0

    log_info "Plan for ${AGAMEMNON_URL} (dry-run — no changes will be made)"
    log_info "================================================================"
    log_info ""

    for yaml_file in "${yaml_files[@]}"; do
        plan_agent "$yaml_file" "$agents_json" || has_changes=1
    done

    # Report unmanaged agents (in Agamemnon but not in YAML)
    log_info ""
    log_info "Checking for unmanaged agents..."
    report_unmanaged "$agents_json" "${yaml_files[@]}"

    log_info ""
    if [[ $has_changes -eq 0 ]]; then
        log_info "No changes needed. Desired state matches actual state."
        exit 0
    else
        log_warn "Summary: created=${CREATE_COUNT} updated=${UPDATE_COUNT} woken=${WAKE_COUNT} hibernated=${HIBERNATE_COUNT}"
        log_warn "Changes would be made. Run ./scripts/apply.sh to apply."
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
        log_info "[+] CREATE ${name} (program=${program}, deploy=${fields[deploymentType]:-local})"
        if [[ "$desired_state" == "active" ]]; then
            log_info "    └─ WAKE after create"
        fi
        ((CREATE_COUNT++))
        return 1
    fi

    local action
    action="$(compute_drift "$name" "$desired_state" "$actual_json" \
        "$label" "$program" "$workdir" "$args" "$desc")"

    case "$action" in
        UNCHANGED)
            log_info "[=] UNCHANGED ${name}"
            ;;
        WAKE)
            log_warn "[!] WAKE ${name} (desired=active, actual=$(echo "$actual_json" | jq -r '.status'))"
            ((WAKE_COUNT++))
            return 1
            ;;
        HIBERNATE)
            log_warn "[z] HIBERNATE ${name} (desired=hibernated, actual=$(echo "$actual_json" | jq -r '.status'))"
            ((HIBERNATE_COUNT++))
            return 1
            ;;
        UPDATE:*)
            local fields_changed="${action#UPDATE:}"
            log_warn "[~] UPDATE ${name}: ${fields_changed} differ"
            ((UPDATE_COUNT++))
            return 1
            ;;
    esac

    return 0
}

main "$@"
