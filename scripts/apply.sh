#!/usr/bin/env bash
# scripts/apply.sh — Reconcile desired state → actual via Agamemnon API
#
# The core GitOps reconciliation loop. Reads agent YAML files and ensures
# Agamemnon matches the desired state. All changes go through the REST API.
#
# Usage:
#   ./scripts/apply.sh                 # Apply all agents on all hosts
#   ./scripts/apply.sh hermes          # Apply agents for a specific host
#   ./scripts/apply.sh --fleet dev-mesh
#   ./scripts/apply.sh --prune         # Also hibernate+delete unmanaged agents
#   ./scripts/apply.sh --dry-run       # Same as plan.sh
#   ./scripts/apply.sh --fail-fast     # Stop on first error
#
# Safety:
#   - Never auto-deletes agents without --prune flag
#   - Always hibernates before deleting
#   - Prints a summary of what was done
#
# Exit codes:
#   0 = all agents applied successfully
#   1 = partial failure (some agents failed)
#   2 = total failure (all processed agents failed)

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
FAIL_FAST=0
RETRY=0

CREATED=0
UPDATED=0
WOKEN=0
HIBERNATED=0
UNCHANGED=0
ERRORS=0

# Per-agent error tracking: parallel arrays of (agent_name, http_status, error_message)
FAILED_AGENT_NAMES=()
FAILED_AGENT_STATUSES=()
FAILED_AGENT_MESSAGES=()

# Directory for state files
MYRMIDONS_STATE_DIR="${REPO_ROOT}/.myrmidons"
FAILED_AGENTS_FILE="${MYRMIDONS_STATE_DIR}/failed-agents.txt"

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prune)     PRUNE=1; shift ;;
            --dry-run)   DRY_RUN=1; shift ;;
            --fail-fast) FAIL_FAST=1; shift ;;
            --retry)     RETRY=1; shift ;;
            --fleet)     FLEET="$2"; shift 2 ;;
            -h|--help)   usage; exit 0 ;;
            *) HOST="$1"; shift ;;
        esac
    done
}

usage() {
    cat <<EOF
Usage: $0 [host] [--fleet <name>] [--prune] [--dry-run] [--fail-fast] [--retry]

Reconciles agent YAML definitions against Agamemnon's actual state.

Options:
  host           Only apply agents for this host (default: all)
  --fleet NAME   Only apply agents in this fleet
  --prune        Hibernate and delete unmanaged agents (agents in Agamemnon
                 but not in YAML). DEFAULT: warn only.
  --dry-run      Show what would happen, make no changes (same as plan.sh)
  --fail-fast    Stop on first error (default: continue processing all agents)
  --retry        Re-apply only agents listed in .myrmidons/failed-agents.txt.
                 File is self-managing: updated on partial success, cleared on
                 full success. Operators need not manually manage this file.
  -h, --help     Show this help

Exit codes:
  0  All agents applied successfully
  1  Partial failure (some agents failed)
  2  Total failure (all processed agents failed)

Failed agents tracking (issue #269):
  .myrmidons/failed-agents.txt is automatically created on any failure and
  updated after each run to reflect only currently-failed agents. Use
  'just retry' to re-apply only previously failed agents.

  On successful --retry:       the file is cleared automatically (exit 0).
  On partial --retry success:  the file contains only agents still failing.
  On any failure without retry: the file contains all newly-failed agents.

Examples:
  $0                         # Reconcile everything
  $0 hermes                  # Reconcile hermes only
  $0 --fleet dev-mesh        # Reconcile dev-mesh fleet
  $0 --prune                 # Reconcile + remove unmanaged agents
  $0 --fail-fast             # Stop on first error
  $0 --retry                 # Re-attempt agents from last failure
EOF
}

# Record a per-agent failure and increment error counter.
# Usage: record_failure <agent_name> <http_status> <error_message>
record_failure() {
    local agent_name="$1"
    local http_status="$2"
    local error_message="$3"

    ERRORS=$((ERRORS + 1))
    FAILED_AGENT_NAMES+=("$agent_name")
    FAILED_AGENT_STATUSES+=("$http_status")
    FAILED_AGENT_MESSAGES+=("$error_message")
}

# Write failed agent names to .myrmidons/failed-agents.txt for use by 'just retry'.
# This file is self-managing (issue #269):
# - Truncated before writing (: > ...), so contains only agents that failed THIS run.
# - On partial retry success: updated with only agents still failing (previously-succeeded agents removed).
# - On full retry success: cleared by the explicit block at end of main().
# Operators do not need to manually delete or manage this file.
write_failed_agents_file() {
    mkdir -p "${MYRMIDONS_STATE_DIR}"
    : > "${FAILED_AGENTS_FILE}"
    for name in "${FAILED_AGENT_NAMES[@]}"; do
        echo "$name" >> "${FAILED_AGENTS_FILE}"
    done
}

# Print a detailed per-agent error summary.
print_error_summary() {
    echo ""
    echo "================================================"
    echo "FAILED AGENTS (${ERRORS}):"
    echo ""
    local i
    for i in "${!FAILED_AGENT_NAMES[@]}"; do
        local agent_name="${FAILED_AGENT_NAMES[$i]}"
        local http_status="${FAILED_AGENT_STATUSES[$i]}"
        local error_msg="${FAILED_AGENT_MESSAGES[$i]}"
        echo "  [FAIL] ${agent_name}"
        if [[ -n "$http_status" ]]; then
            echo "         HTTP status: ${http_status}"
        fi
        if [[ -n "$error_msg" ]]; then
            echo "         Error: ${error_msg}"
        fi
    done
    echo ""
    echo "Failed agents written to: ${FAILED_AGENTS_FILE}"
    echo "Run 'just retry' to re-apply only failed agents."
}

main() {
    parse_args "$@"

    if [[ $DRY_RUN -eq 1 ]]; then
        exec "${SCRIPT_DIR}/plan.sh" "$@"
    fi

    check_deps
    agamemnon_check_connection

    local agents_json
    agents_json="$(agamemnon_list_agents)"

    local yaml_files
    mapfile -t yaml_files < <(get_agent_files "$HOST")

    if [[ $RETRY -eq 1 ]]; then
        if [[ ! -f "${FAILED_AGENTS_FILE}" ]] || [[ ! -s "${FAILED_AGENTS_FILE}" ]]; then
            echo "No failed agents to retry (${FAILED_AGENTS_FILE} is empty or missing)."
            exit 0
        fi
        local failed_names=()
        mapfile -t failed_names < "${FAILED_AGENTS_FILE}"
        echo "Retrying ${#failed_names[@]} previously failed agent(s):"
        for fn in "${failed_names[@]}"; do echo "  - ${fn}"; done
        echo ""

        local filtered_files=()
        for yaml_file in "${yaml_files[@]}"; do
            local yname
            yname="$(yq eval '.metadata.name' "$yaml_file")"
            for fn in "${failed_names[@]}"; do
                if [[ "$yname" == "$fn" ]]; then
                    filtered_files+=("$yaml_file")
                    break
                fi
            done
        done
        yaml_files=("${filtered_files[@]}")

        if [[ ${#yaml_files[@]} -eq 0 ]]; then
            echo "WARNING: None of the failed agents were found in agents/. They may have been removed."
            exit 1
        fi
    fi

    if [[ ${#yaml_files[@]} -eq 0 ]]; then
        echo "No agent YAML files found."
        exit 0
    fi

    echo "Applying desired state to ${AGAMEMNON_URL}"
    echo "================================================"
    echo ""

    local processed=0
    for yaml_file in "${yaml_files[@]}"; do
        apply_agent "$yaml_file" "$agents_json"
        processed=$((processed + 1))

        if [[ $FAIL_FAST -eq 1 && $ERRORS -gt 0 ]]; then
            echo ""
            echo "ERROR: --fail-fast enabled, stopping after first failure." >&2
            break
        fi

        # Refresh actual state after each change
        agents_json="$(agamemnon_list_agents)"
    done

    # Handle unmanaged agents
    handle_unmanaged "$agents_json" "${yaml_files[@]}"

    echo ""
    echo "================================================"
    echo "Summary: created=${CREATED} updated=${UPDATED} woken=${WOKEN} hibernated=${HIBERNATED} unchanged=${UNCHANGED} errors=${ERRORS}"

    if [[ $ERRORS -gt 0 ]]; then
        print_error_summary
        write_failed_agents_file

        local total_processed=$(( CREATED + UPDATED + WOKEN + HIBERNATED + UNCHANGED + ERRORS ))
        # Total failure: every processed agent either failed or none succeeded
        if [[ $(( total_processed - ERRORS )) -eq 0 ]]; then
            exit 2
        fi
        exit 1
    fi

    # Clear failed-agents file on full success (issue #269).
    # This completes the self-managing lifecycle:
    # - Created on any failure via write_failed_agents_file() (called if $ERRORS > 0)
    # - Updated on partial retry success via write_failed_agents_file() (only failing agents written)
    # - Cleared here on full success (all agents passed in this run, $ERRORS == 0)
    # This ensures the file always contains only agents currently failing, with no manual management needed.
    if [[ -f "${FAILED_AGENTS_FILE}" ]]; then
        : > "${FAILED_AGENTS_FILE}"
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

        local result http_status
        http_status=""
        if result="$(agamemnon_create_agent "$create_body" 2>&1)"; then
            local new_id
            new_id="$(echo "$result" | jq -r '.id // empty')"
            echo "    Created: id=${new_id}"
            CREATED=$((CREATED + 1))

            # Wake if desired
            if [[ "$desired_state" == "active" && -n "$new_id" ]]; then
                echo "    Starting ${name}..."
                if ! agamemnon_wake_agent "$new_id" > /dev/null 2>&1; then
                    echo "    ERROR starting ${name} after create" >&2
                    record_failure "$name" "" "Failed to wake agent after creation (id=${new_id})"
                    return
                fi
                echo "    Started."
                WOKEN=$((WOKEN + 1))
            fi
        else
            # Try to extract HTTP status from error output
            http_status="$(echo "$result" | grep -oE 'HTTP [0-9]+' | grep -oE '[0-9]+' | head -1 || true)"
            local err_msg
            err_msg="$(echo "$result" | tail -1)"
            echo "    ERROR creating ${name}: ${err_msg}" >&2
            record_failure "$name" "$http_status" "$err_msg"
        fi
        return
    fi

    # Agent exists — check what needs to change
    local actual_id actual_status
    actual_id="$(echo "$actual_json" | jq -r '.id')"
    actual_status="$(echo "$actual_json" | jq -r '.status // "unknown"')"

    local action
    action="$(compute_drift "$name" "$desired_state" "$actual_json" \
        "$label" "$program" "$workdir" "$args" "$desc" "$tags")"

    case "$action" in
        UNCHANGED)
            echo "[=] Unchanged: ${name}"
            UNCHANGED=$((UNCHANGED + 1))
            ;;
        WAKE)
            echo "[!] Starting ${name} (status=${actual_status}, desired=active)..."
            local wake_out
            if wake_out="$(agamemnon_wake_agent "$actual_id" 2>&1)"; then
                echo "    Started."
                WOKEN=$((WOKEN + 1))
            else
                local http_status
                http_status="$(echo "$wake_out" | grep -oE 'HTTP [0-9]+' | grep -oE '[0-9]+' | head -1 || true)"
                local err_msg="$(echo "$wake_out" | tail -1)"
                echo "    ERROR starting ${name}: ${err_msg}" >&2
                record_failure "$name" "$http_status" "Failed to wake agent: ${err_msg}"
            fi
            ;;
        HIBERNATE)
            echo "[z] Stopping ${name} (status=${actual_status}, desired=hibernated)..."
            local hib_out
            if hib_out="$(agamemnon_hibernate_agent "$actual_id" 2>&1)"; then
                echo "    Hibernated."
                HIBERNATED=$((HIBERNATED + 1))
            else
                local http_status
                http_status="$(echo "$hib_out" | grep -oE 'HTTP [0-9]+' | grep -oE '[0-9]+' | head -1 || true)"
                local err_msg="$(echo "$hib_out" | tail -1)"
                echo "    ERROR stopping ${name}: ${err_msg}" >&2
                record_failure "$name" "$http_status" "Failed to hibernate agent: ${err_msg}"
            fi
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

            local update_out
            if update_out="$(agamemnon_update_agent "$actual_id" "$patch_body" 2>&1)"; then
                echo "    Updated."
                UPDATED=$((UPDATED + 1))

                # Also start/stop if state needs to change
                if [[ "$desired_state" == "active" && "$actual_status" == "offline" ]]; then
                    agamemnon_wake_agent "$actual_id" > /dev/null
                    WOKEN=$((WOKEN + 1))
                elif [[ "$desired_state" == "hibernated" && \
                        ("$actual_status" == "active" || "$actual_status" == "online") ]]; then
                    agamemnon_hibernate_agent "$actual_id" > /dev/null
                    HIBERNATED=$((HIBERNATED + 1))
                fi
            else
                local http_status
                http_status="$(echo "$update_out" | grep -oE 'HTTP [0-9]+' | grep -oE '[0-9]+' | head -1 || true)"
                local err_msg="$(echo "$update_out" | tail -1)"
                echo "    ERROR updating ${name}: ${err_msg}" >&2
                record_failure "$name" "$http_status" "Failed to update fields [${changed_fields}]: ${err_msg}"
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
                agamemnon_hibernate_agent "$agent_id" > /dev/null || true
                sleep 2
                echo "    Deleting..."
                agamemnon_delete_agent "$agent_id" > /dev/null
                echo "    Deleted (backup created)."
            else
                echo "[-] UNMANAGED: ${actual_name} (in Agamemnon but not in YAML — use --prune to remove)"
            fi
        fi
    done < <(echo "$agents_json" | jq -r '.[].name')
}

main "$@"
