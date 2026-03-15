#!/usr/bin/env bash
# scripts/apply.sh — Reconcile desired state → actual via ai-maestro API
#
# The core GitOps reconciliation loop. Reads agent YAML files and ensures
# ai-maestro matches the desired state. NEVER modifies registry.json directly —
# all changes go through the REST API.
#
# Usage:
#   ./scripts/apply.sh                 # Apply all agents on all hosts
#   ./scripts/apply.sh hermes          # Apply agents for a specific host
#   ./scripts/apply.sh --fleet dev-mesh
#   ./scripts/apply.sh --prune         # Also hibernate+delete unmanaged agents
#   ./scripts/apply.sh --dry-run       # Same as plan.sh
#
# Safety:
#   - Never auto-deletes agents without --prune flag
#   - Always hibernates before deleting
#   - Prints a summary of what was done

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/api.sh
source "${SCRIPT_DIR}/lib/api.sh"
# shellcheck source=scripts/lib/reconcile.sh
source "${SCRIPT_DIR}/lib/reconcile.sh"

HOST=""
FLEET=""
PRUNE=0
DRY_RUN=0

CREATED=0
UPDATED=0
WOKEN=0
HIBERNATED=0
UNCHANGED=0
ERRORS=0

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prune)   PRUNE=1; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            --fleet)   FLEET="$2"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) HOST="$1"; shift ;;
        esac
    done
}

usage() {
    cat <<EOF
Usage: $0 [host] [--fleet <name>] [--prune] [--dry-run]

Reconciles agent YAML definitions against ai-maestro's actual state.

Options:
  host           Only apply agents for this host (default: all)
  --fleet NAME   Only apply agents in this fleet
  --prune        Hibernate and delete unmanaged agents (agents in ai-maestro
                 but not in YAML). DEFAULT: warn only.
  --dry-run      Show what would happen, make no changes (same as plan.sh)
  -h, --help     Show this help

Examples:
  $0                         # Reconcile everything
  $0 hermes                  # Reconcile hermes only
  $0 --fleet dev-mesh        # Reconcile dev-mesh fleet
  $0 --prune                 # Reconcile + remove unmanaged agents
EOF
}

main() {
    parse_args "$@"

    if [[ $DRY_RUN -eq 1 ]]; then
        exec "${SCRIPT_DIR}/plan.sh" "$@"
    fi

    check_deps
    aim_check_connection

    local agents_json
    agents_json="$(aim_list_agents)"

    local yaml_files
    mapfile -t yaml_files < <(get_agent_files "$HOST")

    if [[ ${#yaml_files[@]} -eq 0 ]]; then
        echo "No agent YAML files found."
        exit 0
    fi

    echo "Applying desired state to ${AIM_HOST}"
    echo "================================================"
    echo ""

    for yaml_file in "${yaml_files[@]}"; do
        apply_agent "$yaml_file" "$agents_json" || true
        # Refresh actual state after each change
        agents_json="$(aim_list_agents)"
    done

    # Handle unmanaged agents
    handle_unmanaged "$agents_json" "${yaml_files[@]}"

    echo ""
    echo "================================================"
    echo "Summary: created=${CREATED} updated=${UPDATED} woken=${WOKEN} hibernated=${HIBERNATED} unchanged=${UNCHANGED} errors=${ERRORS}"

    if [[ $ERRORS -gt 0 ]]; then
        exit 1
    fi
}

apply_agent() {
    local yaml_file="$1"
    local agents_json="$2"

    # Parse YAML fields into local variables
    local name label program model workdir args desc tags owner role deploy_type desired_state
    name="$(yq eval '.metadata.name' "$yaml_file")"
    label="$(yq eval '.spec.label // ""' "$yaml_file")"
    program="$(yq eval '.spec.program // "claude-code"' "$yaml_file")"
    model="$(yq eval '.spec.model // ""' "$yaml_file")"
    workdir="$(yq eval '.spec.workingDirectory // ""' "$yaml_file")"
    args="$(yq eval '.spec.programArgs // ""' "$yaml_file")"
    desc="$(yq eval '.spec.taskDescription // ""' "$yaml_file")"
    tags="$(yq eval '.spec.tags // [] | join(",")' "$yaml_file")"
    owner="$(yq eval '.spec.owner // ""' "$yaml_file")"
    role="$(yq eval '.spec.role // "member"' "$yaml_file")"
    deploy_type="$(yq eval '.spec.deployment.type // "local"' "$yaml_file")"
    desired_state="$(yq eval '.spec.desiredState // "active"' "$yaml_file")"

    # Look up actual agent
    local actual_json
    actual_json="$(echo "$agents_json" | jq -r --arg n "$name" '.[] | select(.name == $n)')"

    if [[ -z "$actual_json" ]]; then
        # CREATE
        echo "[+] Creating ${name}..."
        local create_body
        create_body="$(build_create_json "$name" "$label" "$program" "$workdir" "$args" "$desc" "$tags" "$owner" "$role")"

        local result
        if result="$(aim_create_agent "$create_body" 2>&1)"; then
            local new_id
            new_id="$(echo "$result" | jq -r '.id // empty')"
            echo "    Created: id=${new_id}"
            CREATED=$((CREATED + 1))

            # Wake if desired
            if [[ "$desired_state" == "active" && -n "$new_id" ]]; then
                echo "    Waking ${name}..."
                aim_wake_agent "$new_id" > /dev/null
                echo "    Woken."
                WOKEN=$((WOKEN + 1))
            fi
        else
            echo "    ERROR creating ${name}: ${result}" >&2
            ERRORS=$((ERRORS + 1))
        fi
        return
    fi

    # Agent exists — check what needs to change
    local actual_id actual_status
    actual_id="$(echo "$actual_json" | jq -r '.id')"
    actual_status="$(echo "$actual_json" | jq -r '.status // "unknown"')"

    local action
    action="$(compute_drift "$name" "$desired_state" "$actual_json" \
        "$label" "$program" "$workdir" "$args" "$desc")"

    case "$action" in
        UNCHANGED)
            echo "[=] Unchanged: ${name}"
            UNCHANGED=$((UNCHANGED + 1))
            ;;
        WAKE)
            echo "[!] Waking ${name} (status=${actual_status}, desired=active)..."
            aim_wake_agent "$actual_id" > /dev/null
            echo "    Woken."
            WOKEN=$((WOKEN + 1))
            ;;
        HIBERNATE)
            echo "[z] Hibernating ${name} (status=${actual_status}, desired=hibernated)..."
            aim_hibernate_agent "$actual_id" > /dev/null
            echo "    Hibernated."
            HIBERNATED=$((HIBERNATED + 1))
            ;;
        UPDATE:*)
            local changed_fields="${action#UPDATE:}"
            echo "[~] Updating ${name} (fields: ${changed_fields})..."

            local patch_body
            patch_body="$(jq -n \
                --arg label "$label" \
                --arg program "$program" \
                --arg workingDirectory "$workdir" \
                --arg programArgs "$args" \
                --arg taskDescription "$desc" \
                '{label: $label, program: $program, workingDirectory: $workingDirectory,
                  programArgs: $programArgs, taskDescription: $taskDescription}')"

            if aim_update_agent "$actual_id" "$patch_body" > /dev/null 2>&1; then
                echo "    Updated."
                UPDATED=$((UPDATED + 1))
            else
                echo "    ERROR updating ${name}" >&2
                ERRORS=$((ERRORS + 1))
            fi

            # Also wake/hibernate if state needs to change
            if [[ "$desired_state" == "active" && "$actual_status" == "offline" ]]; then
                aim_wake_agent "$actual_id" > /dev/null
                WOKEN=$((WOKEN + 1))
            elif [[ "$desired_state" == "hibernated" && \
                    ("$actual_status" == "active" || "$actual_status" == "online") ]]; then
                aim_hibernate_agent "$actual_id" > /dev/null
                HIBERNATED=$((HIBERNATED + 1))
            fi
            ;;
    esac
}

handle_unmanaged() {
    local agents_json="$1"
    shift
    local yaml_files=("$@")

    # Collect managed names
    local managed_names=()
    for yaml_file in "${yaml_files[@]}"; do
        local n
        n="$(yq eval '.metadata.name' "$yaml_file")"
        managed_names+=("$n")
    done

    # Find unmanaged
    while IFS= read -r actual_name; do
        local is_managed=0
        for mn in "${managed_names[@]}"; do
            [[ "$mn" == "$actual_name" ]] && is_managed=1 && break
        done

        if [[ $is_managed -eq 0 ]]; then
            if [[ $PRUNE -eq 1 ]]; then
                local agent_id
                agent_id="$(echo "$agents_json" | jq -r --arg n "$actual_name" \
                    '.[] | select(.name == $n) | .id')"
                echo "[-] Pruning unmanaged: ${actual_name}"
                echo "    Hibernating first..."
                aim_hibernate_agent "$agent_id" > /dev/null || true
                sleep 2
                echo "    Deleting..."
                aim_delete_agent "$agent_id" > /dev/null
                echo "    Deleted (backup created)."
            else
                echo "[-] UNMANAGED: ${actual_name} (in ai-maestro but not in YAML — use --prune to remove)"
            fi
        fi
    done < <(echo "$agents_json" | jq -r '.[].name')
}

main "$@"
