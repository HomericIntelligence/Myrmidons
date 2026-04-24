#!/usr/bin/env bash
# scripts/apply.sh — Reconcile desired state → actual via Agamemnon API
#
# The core GitOps reconciliation loop. Reads agent YAML files and ensures
# Agamemnon matches the desired state. All changes go through the REST API.
#
# Usage:
#   ./scripts/apply.sh                         # Apply all agents on all hosts
#   ./scripts/apply.sh hermes                  # Apply agents for a specific host
#   ./scripts/apply.sh --fleet dev-mesh
#   ./scripts/apply.sh --prune                 # Also hibernate+delete unmanaged agents
#   ./scripts/apply.sh --dry-run               # Same as plan.sh
#   ./scripts/apply.sh --output json           # Emit JSON reconciliation report to stdout
#   ./scripts/apply.sh --webhook <url>         # POST report to webhook URL after apply
#
# Safety:
#   - Never auto-deletes agents without --prune flag
#   - Always hibernates before deleting
#   - Prints a summary of what was done

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/config.sh
source "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=scripts/lib/api.sh
source "${SCRIPT_DIR}/lib/api.sh"
# shellcheck source=scripts/lib/reconcile.sh
source "${SCRIPT_DIR}/lib/reconcile.sh"
# shellcheck source=scripts/lib/report.sh
source "${SCRIPT_DIR}/lib/report.sh"

load_config

HOST=""
FLEET_NAME=""
PRUNE=0
DRY_RUN=0
OUTPUT_FORMAT="text"   # "text" | "json"
WEBHOOK_URL=""
AIM_LOCK_TIMEOUT="${AIM_LOCK_TIMEOUT:-60}"
SNAPSHOT_DIR=""
SNAPSHOT_KEEP="${SNAPSHOT_KEEP:-10}"

CREATED=0
UPDATED=0
WOKEN=0
HIBERNATED=0
UNCHANGED=0
PRUNED=0
ERRORS=0

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prune)            PRUNE=1; shift ;;
            --dry-run)          DRY_RUN=1; shift ;;
            --fleet)            FLEET_NAME="$2"; shift 2 ;;
            --lock-timeout)     AIM_LOCK_TIMEOUT="$2"; shift 2 ;;
            --output)           OUTPUT_FORMAT="$2"; shift 2 ;;
            --webhook)          WEBHOOK_URL="$2"; shift 2 ;;
            --snapshot-dir)     SNAPSHOT_DIR="$2"; shift 2 ;;
            --force)            shift ;;  # Consume --force (applies during actual apply, not dry-run)
            -h|--help)          usage; exit 0 ;;
            *) HOST="$1"; shift ;;
        esac
    done
}

usage() {
    cat <<EOF
Usage: $0 [host] [--fleet <name>] [--prune] [--dry-run] [--force] [--lock-timeout SECONDS] [--output json] [--webhook <url>]

Reconciles agent YAML definitions against Agamemnon's actual state.

Options:
  host                 Only apply agents for this host (default: all)
  --fleet NAME         Only apply agents belonging to the named fleet
  --prune              Hibernate and delete unmanaged agents (agents in Agamemnon
                       but not in YAML). DEFAULT: warn only.
  --dry-run            Show what would happen, make no changes (same as plan.sh)
  --force              Force apply even if lock acquisition times out.
  --lock-timeout SECS  Set lock acquisition timeout in seconds (default: 60).
                       Also configurable via AIM_LOCK_TIMEOUT env var.
  --output json        Emit a JSON reconciliation report to stdout instead of
                       human-readable text. Also saves to reports/last-reconciliation.json.
  --webhook URL        POST the JSON report to URL after reconciliation completes.
  --snapshot-dir DIR   Directory for pre-apply snapshots (default: .myrmidons/snapshots).
                       Also configurable via SNAPSHOT_DIR env var.
  -h, --help           Show this help

Examples:
  $0                              # Reconcile everything
  $0 hermes                       # Reconcile hermes only
  $0 --fleet dev-mesh             # Reconcile agents in the dev-mesh fleet
  $0 --prune                      # Reconcile + remove unmanaged agents
  $0 --dry-run --force            # Dry-run (force is handled correctly)
  $0 --lock-timeout 120           # Reconcile with 120s lock timeout
  $0 --output json | jq .         # Machine-readable report
  $0 --webhook http://host/hook   # Post report to webhook
EOF
}

main() {
    # Save original args before parse_args consumes them for dry-run filtering
    local -a orig_args=("$@")

    parse_args "$@"

    # Validate AGAMEMNON_URL format early (#118)
    validate_agamemnon_url

    # Validate HOST argument against known agents/ subdirectories (#149)
    if [[ -n "$HOST" && ! -d "${REPO_ROOT}/agents/${HOST}" ]]; then
        echo "ERROR: Host '${HOST}' not found — no agents/${HOST}/ directory exists." >&2
        echo "  Known hosts: $(find "${REPO_ROOT}/agents" -mindepth 1 -maxdepth 1 -type d \
            ! -name '_templates' -printf '%f ' 2>/dev/null || echo '(none)')" >&2
        exit 1
    fi

    # Export AIM_LOCK_TIMEOUT for use by child processes (e.g. api.sh)
    export AIM_LOCK_TIMEOUT

    if [[ $DRY_RUN -eq 1 ]]; then
        # Strip --force, --dry-run, and --lock-timeout before forwarding to plan.sh
        # plan.sh doesn't understand these flags
        local -a clean_args=()
        local skip_next=0
        for arg in "${orig_args[@]}"; do
            if [[ $skip_next -eq 1 ]]; then
                skip_next=0
                continue
            fi
            case "$arg" in
                --force | --dry-run)
                    continue
                    ;;
                --lock-timeout | --snapshot-dir)
                    skip_next=1
                    continue
                    ;;
                *)
                    clean_args+=("$arg")
                    ;;
            esac
        done

        exec "${SCRIPT_DIR}/plan.sh" "${clean_args[@]}"
    fi

    check_deps
    agamemnon_check_connection

    # Check for agents/ and fleets/ directories
    local has_agents=false
    local has_fleets=false
    [[ -d "${REPO_ROOT}/agents/" ]] && has_agents=true
    [[ -d "${REPO_ROOT}/fleets/" ]] && has_fleets=true

    if [[ "$has_agents" == "false" && "$has_fleets" == "false" ]]; then
        log_error "Neither agents/ nor fleets/ directory found — nothing to reconcile"
        exit 1
    elif [[ "$has_agents" == "false" ]]; then
        log_warn "agents/ directory not found — reconciling fleets only"
    elif [[ "$has_fleets" == "false" ]]; then
        log_warn "fleets/ directory not found — reconciling agents only"
    fi

    # Initialise report accumulator
    report_init "${HOST:-all}"
    trap 'report_cleanup; cleanup_fleet_tmpdir' EXIT

    local agents_json
    agents_json="$(agamemnon_list_agents)"

    # Capture pre-apply snapshot (#228: includes context fields user/branch/host/timestamp)
    local effective_snapshot_dir="${SNAPSHOT_DIR:-${repo_root}/.myrmidons/snapshots}"
    local snap_file
    snap_file="$(snapshot_write "$agents_json" "$effective_snapshot_dir" "${HOST:-all}")"
    snapshot_prune "$effective_snapshot_dir" "$SNAPSHOT_KEEP"
    if [[ "$OUTPUT_FORMAT" != "json" ]]; then
        echo "Snapshot saved: ${snap_file}"
    fi

    local yaml_files
    mapfile -t yaml_files < <(get_agent_files "$HOST" "$FLEET_NAME")

    if [[ ${#yaml_files[@]} -eq 0 ]]; then
        if [[ "$OUTPUT_FORMAT" == "json" ]]; then
            report_emit 0 0 0 0 0 0 0
        else
            echo "No agent YAML files found."
        fi
        exit 0
    fi

    if [[ "$OUTPUT_FORMAT" != "json" ]]; then
        echo "Applying desired state to ${AGAMEMNON_URL}"
        echo "================================================"
        echo ""
    fi

    for yaml_file in "${yaml_files[@]}"; do
        if ! apply_agent "$yaml_file" "$agents_json"; then
            echo "ERROR: apply_agent failed for ${yaml_file}" >&2
            ERRORS=$((ERRORS + 1))
        fi
        # Refresh actual state after each change
        agents_json="$(agamemnon_list_agents)"
    done

    # Handle unmanaged agents.
    # When --fleet is active, scope the check to only agents that belong to the
    # fleet (i.e. agents whose names are in yaml_files), so agents managed by
    # other fleets or outside this fleet are not flagged as unmanaged.
    local scoped_agents_json
    if [[ -n "$FLEET_NAME" ]]; then
        local fleet_names_json
        fleet_names_json="$(for f in "${yaml_files[@]}"; do yq eval '.metadata.name' "$f"; done | jq -Rsc 'split("\n") | map(select(length > 0))')"
        scoped_agents_json="$(echo "$agents_json" | jq --argjson names "$fleet_names_json" '[.[] | select(.name as $n | $names | index($n) != null)]')"
    else
        scoped_agents_json="$agents_json"
    fi
    handle_unmanaged "$scoped_agents_json" "${yaml_files[@]}"

    # Emit output
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        local report_json
        report_json="$(report_emit "$CREATED" "$UPDATED" "$WOKEN" "$HIBERNATED" \
                                   "$UNCHANGED" "$PRUNED" "$ERRORS")"
        if [[ -n "$WEBHOOK_URL" ]]; then
            local delivery_json
            delivery_json="$(report_webhook "$report_json" "$WEBHOOK_URL")"
            report_json="$(echo "$report_json" | jq --argjson d "$delivery_json" \
                '. + {webhook_delivery: $d}')"
        fi
        report_save "$report_json"
        echo "$report_json"
    else
        echo ""
        echo "================================================"
        echo "Summary: created=${CREATED} updated=${UPDATED} woken=${WOKEN} hibernated=${HIBERNATED} unchanged=${UNCHANGED} errors=${ERRORS}"

        # Always save a report file (silently) so report_save is useful even in text mode
        local report_json
        report_json="$(report_emit "$CREATED" "$UPDATED" "$WOKEN" "$HIBERNATED" \
                                   "$UNCHANGED" "$PRUNED" "$ERRORS")"
        if [[ -n "$WEBHOOK_URL" ]]; then
            local delivery_json
            delivery_json="$(report_webhook "$report_json" "$WEBHOOK_URL")"
            report_json="$(echo "$report_json" | jq --argjson d "$delivery_json" \
                '. + {webhook_delivery: $d}')"
        fi
        report_save "$report_json"
    fi

    if [[ $ERRORS -gt 0 ]]; then
        exit 1
    fi
}

apply_agent() {
    local yaml_file="$1"
    local agents_json="$2"

    # Parse YAML fields into local variables
    local name label program workdir args desc tags owner role desired_state
    name="$(yq eval '.metadata.name' "$yaml_file")"
    local agent_host
    agent_host="$(yq eval '.metadata.host // "hermes"' "$yaml_file")"
    label="$(yq eval '.spec.label // ""' "$yaml_file")"
    program="$(yq eval '.spec.program // "claude-code"' "$yaml_file")"
    workdir="$(yq eval '.spec.workingDirectory // ""' "$yaml_file")"
    args="$(yq eval '.spec.programArgs // ""' "$yaml_file")"
    desc="$(yq eval '.spec.taskDescription // ""' "$yaml_file")"
    tags="$(yq eval '.spec.tags // [] | join(",")' "$yaml_file")"
    owner="$(yq eval '.spec.owner // ""' "$yaml_file")"
    role="$(yq eval '.spec.role // "member"' "$yaml_file")"
    desired_state="$(yq eval '.spec.desiredState // "active"' "$yaml_file")"

    # Look up actual agent
    local actual_json
    actual_json="$(echo "$agents_json" | jq -r --arg n "$name" '.[] | select(.name == $n)')"

    if [[ -z "$actual_json" ]]; then
        # CREATE
        if [[ "$OUTPUT_FORMAT" != "json" ]]; then
            echo "[+] Creating ${name}..."
        fi
        local create_body
        create_body="$(build_create_json "$name" "$label" "$program" "$workdir" "$args" "$desc" "$tags" "$owner" "$role")"

        local result
        if result="$(agamemnon_create_agent "$create_body" 2>&1)"; then
            local new_id
            new_id="$(echo "$result" | jq -r '.id // empty')"
            if [[ "$OUTPUT_FORMAT" != "json" ]]; then
                echo "    Created: id=${new_id}"
            fi
            CREATED=$((CREATED + 1))

            local woke_status="created"
            # Wake if desired
            if [[ "$desired_state" == "active" && -n "$new_id" ]]; then
                if [[ "$OUTPUT_FORMAT" != "json" ]]; then
                    echo "    Starting ${name}..."
                fi
                agamemnon_wake_agent "$new_id" > /dev/null
                if [[ "$OUTPUT_FORMAT" != "json" ]]; then
                    echo "    Started."
                fi
                WOKEN=$((WOKEN + 1))
                woke_status="active"
            fi

            report_add_agent "$name" "$agent_host" "CREATE" "$desired_state" "$woke_status" "[]" ""
        else
            if [[ "$OUTPUT_FORMAT" != "json" ]]; then
                echo "    ERROR creating ${name}: ${result}" >&2
            fi
            ERRORS=$((ERRORS + 1))
            report_add_agent "$name" "$agent_host" "ERROR" "$desired_state" "unknown" "[]" "create failed: ${result}"
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
            if [[ "$OUTPUT_FORMAT" != "json" ]]; then
                echo "[=] Unchanged: ${name}"
            fi
            UNCHANGED=$((UNCHANGED + 1))
            report_add_agent "$name" "$agent_host" "UNCHANGED" "$desired_state" "$actual_status" "[]" ""
            ;;
        WAKE)
            if [[ "$OUTPUT_FORMAT" != "json" ]]; then
                echo "[!] Starting ${name} (status=${actual_status}, desired=active)..."
            fi
            agamemnon_wake_agent "$actual_id" > /dev/null
            if [[ "$OUTPUT_FORMAT" != "json" ]]; then
                echo "    Started."
            fi
            WOKEN=$((WOKEN + 1))
            report_add_agent "$name" "$agent_host" "WAKE" "$desired_state" "$actual_status" "[]" ""
            ;;
        HIBERNATE)
            if [[ "$OUTPUT_FORMAT" != "json" ]]; then
                echo "[z] Stopping ${name} (status=${actual_status}, desired=hibernated)..."
            fi
            agamemnon_hibernate_agent "$actual_id" > /dev/null
            if [[ "$OUTPUT_FORMAT" != "json" ]]; then
                echo "    Hibernated."
            fi
            HIBERNATED=$((HIBERNATED + 1))
            report_add_agent "$name" "$agent_host" "HIBERNATE" "$desired_state" "$actual_status" "[]" ""
            ;;
        UPDATE:*)
            local changed_fields="${action#UPDATE:}"
            if [[ "$OUTPUT_FORMAT" != "json" ]]; then
                echo "[~] Updating ${name} (fields: ${changed_fields})..."
            fi

            local drift_json
            drift_json="$(build_drift_json "$action" "$actual_json" \
                "$label" "$program" "$workdir" "$args" "$desc" "$tags")"

            local tags_json
            if [[ -z "$tags" ]]; then
                tags_json="[]"
            else
                tags_json="$(echo "$tags" | jq -Rc 'split(",")')"
            fi

            local patch_body
            patch_body="$(jq -n \
                --arg label "$label" \
                --arg program "$program" \
                --arg workingDirectory "$workdir" \
                --arg programArgs "$args" \
                --arg taskDescription "$desc" \
                --argjson tags "$tags_json" \
                --arg owner "$owner" \
                --arg role "$role" \
                '{label: $label, program: $program, workingDirectory: $workingDirectory,
                  programArgs: $programArgs, taskDescription: $taskDescription,
                  tags: $tags, owner: $owner, role: $role}')"

            if agamemnon_update_agent "$actual_id" "$patch_body" > /dev/null 2>&1; then
                if [[ "$OUTPUT_FORMAT" != "json" ]]; then
                    echo "    Updated."
                fi
                UPDATED=$((UPDATED + 1))
                report_add_agent "$name" "$agent_host" "UPDATE" "$desired_state" "$actual_status" "$drift_json" ""
            else
                if [[ "$OUTPUT_FORMAT" != "json" ]]; then
                    echo "    ERROR updating ${name}" >&2
                fi
                ERRORS=$((ERRORS + 1))
                report_add_agent "$name" "$agent_host" "ERROR" "$desired_state" "$actual_status" "$drift_json" "update failed"
            fi

            # Also start/stop if state needs to change
            if [[ "$desired_state" == "active" && "$actual_status" == "offline" ]]; then
                agamemnon_wake_agent "$actual_id" > /dev/null
                WOKEN=$((WOKEN + 1))
            elif [[ "$desired_state" == "hibernated" && \
                    ("$actual_status" == "active" || "$actual_status" == "online") ]]; then
                agamemnon_hibernate_agent "$actual_id" > /dev/null
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
                if [[ "$OUTPUT_FORMAT" != "json" ]]; then
                    echo "[-] Pruning unmanaged: ${actual_name}"
                    echo "    Hibernating first..."
                fi
                agamemnon_hibernate_agent "$agent_id" > /dev/null || true
                sleep 2
                if [[ "$OUTPUT_FORMAT" != "json" ]]; then
                    echo "    Deleting..."
                fi
                agamemnon_delete_agent "$agent_id" > /dev/null
                if [[ "$OUTPUT_FORMAT" != "json" ]]; then
                    echo "    Deleted (backup created)."
                fi
                PRUNED=$((PRUNED + 1))
                report_add_agent "$actual_name" "-" "PRUNE" "-" "pruned" "[]" ""
            else
                if [[ "$OUTPUT_FORMAT" != "json" ]]; then
                    echo "[-] UNMANAGED: ${actual_name} (in Agamemnon but not in YAML — use --prune to remove)"
                fi
                report_add_unmanaged "$actual_name"
            fi
        fi
    done < <(echo "$agents_json" | jq -r '.[].name')
}

main "$@"
