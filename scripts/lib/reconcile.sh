#!/usr/bin/env bash
# scripts/lib/reconcile.sh — diff and reconciliation logic
#
# Provides functions used by apply.sh and plan.sh.
# Parses YAML agent definitions, compares with actual Agamemnon state,
# and produces a list of actions to take.
#
# Requires: yq (YAML parser), jq, source of api.sh

set -euo pipefail

# Check required tools
check_deps() {
    local missing=()
    for cmd in yq jq curl; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required tools: ${missing[*]}" >&2
        echo "  Install yq: https://github.com/mikefarah/yq" >&2
        echo "  Install jq: apt install jq / brew install jq" >&2
        return 1
    fi
}

# Parse a single agent YAML file. Outputs key=value lines for each field.
# Usage: parse_agent_yaml /path/to/agent.yaml
parse_agent_yaml() {
    local file="$1"

    yq eval '{
        "name": .metadata.name,
        "host": .metadata.host,
        "label": .spec.label,
        "program": .spec.program,
        "model": (.spec.model // ""),
        "workingDirectory": .spec.workingDirectory,
        "programArgs": (.spec.programArgs // ""),
        "taskDescription": (.spec.taskDescription // ""),
        "tags": (.spec.tags // [] | join(",")),
        "owner": (.spec.owner // ""),
        "role": (.spec.role // "member"),
        "deploymentType": (.spec.deployment.type // "local"),
        "dockerImage": (.spec.deployment.docker.image // ""),
        "dockerCpus": (.spec.deployment.docker.cpus // ""),
        "dockerMemory": (.spec.deployment.docker.memory // ""),
        "desiredState": (.spec.desiredState // "active")
    } | to_entries[] | .key + "=" + (.value | tostring)' "$file"
}

# Get all agent YAML files for a given host (or all hosts).
# Usage: get_agent_files [host]
get_agent_files() {
    local host="${1:-}"
    local repo_root
    repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

    if [[ -n "$host" ]]; then
        find "${repo_root}/agents/${host}" -name "*.yaml" \
            ! -path "*/\_templates/*" 2>/dev/null || true
    else
        find "${repo_root}/agents" -name "*.yaml" \
            ! -path "*/\_templates/*" 2>/dev/null || true
    fi
}

# Build a JSON create body from parsed YAML fields.
# Usage: build_create_json name label program workingDirectory programArgs taskDescription tags owner role
build_create_json() {
    local name="$1" label="$2" program="$3" workdir="$4"
    local args="$5" desc="$6" tags_csv="$7" owner="$8" role="$9"

    # Convert comma-separated tags to JSON array
    local tags_json
    if [[ -z "$tags_csv" ]]; then
        tags_json="[]"
    else
        tags_json="$(echo "$tags_csv" | jq -Rc 'split(",")')"
    fi

    jq -n \
        --arg name "$name" \
        --arg label "$label" \
        --arg program "$program" \
        --arg workingDirectory "$workdir" \
        --arg programArgs "$args" \
        --arg taskDescription "$desc" \
        --argjson tags "$tags_json" \
        --arg owner "$owner" \
        --arg role "$role" \
        '{
            name: $name,
            label: $label,
            program: $program,
            workingDirectory: $workingDirectory,
            programArgs: $programArgs,
            taskDescription: $taskDescription,
            tags: $tags,
            owner: $owner,
            role: $role
        }'
}

# Compare desired agent state (YAML fields) with actual state (JSON from API).
# Outputs: "UNCHANGED", "CREATE", "UPDATE:<field1>,<field2>...", "WAKE", "HIBERNATE"
# Usage: compute_action <yaml_fields_assoc_array_name> <actual_json>
compute_drift() {
    local name="$1"
    local desired_state="$2"    # "active" | "hibernated"
    local actual_json="$3"      # Full agent JSON from API

    local actual_status
    actual_status="$(echo "$actual_json" | jq -r '.status // "unknown"')"

    # Check if wake/hibernate action is needed
    if [[ "$desired_state" == "active" && "$actual_status" == "offline" ]]; then
        echo "WAKE"
        return
    fi
    if [[ "$desired_state" == "hibernated" ]] && \
       [[ "$actual_status" == "active" || "$actual_status" == "online" ]]; then
        echo "HIBERNATE"
        return
    fi

    # Check field-level drift (simplified: check key fields)
    local drifted_fields=()

    local actual_label actual_program actual_workdir actual_args actual_desc actual_tags_sorted
    actual_label="$(echo "$actual_json" | jq -r '.label // ""')"
    actual_program="$(echo "$actual_json" | jq -r '.program // ""')"
    actual_workdir="$(echo "$actual_json" | jq -r '.workingDirectory // ""')"
    actual_args="$(echo "$actual_json" | jq -r '.programArgs // ""')"
    actual_desc="$(echo "$actual_json" | jq -r '.taskDescription // ""')"
    # Tags: sorted comma-joined for stable comparison
    actual_tags_sorted="$(echo "$actual_json" | jq -r '.tags // [] | sort | join(",")')"

    # These are passed as positional args from the caller
    local desired_label="$4"
    local desired_program="$5"
    local desired_workdir="$6"
    local desired_args="$7"
    local desired_desc="$8"
    local desired_tags_csv="${9:-}"

    # Normalize tilde paths before comparison
    actual_workdir="$(normalize_path "$actual_workdir")"
    desired_workdir="$(normalize_path "$desired_workdir")"

    # Sort desired tags for stable comparison
    local desired_tags_sorted=""
    if [[ -n "$desired_tags_csv" ]]; then
        desired_tags_sorted="$(echo "$desired_tags_csv" | tr ',' '\n' | sort | tr '\n' ',' | sed 's/,$//')"
    fi

    [[ "$actual_label" != "$desired_label" ]] && drifted_fields+=("label")
    [[ "$actual_program" != "$desired_program" ]] && drifted_fields+=("program")
    [[ "$actual_workdir" != "$desired_workdir" ]] && drifted_fields+=("workingDirectory")
    [[ "$actual_args" != "$desired_args" ]] && drifted_fields+=("programArgs")
    [[ "$actual_desc" != "$desired_desc" ]] && drifted_fields+=("taskDescription")
    [[ "$actual_tags_sorted" != "$desired_tags_sorted" ]] && drifted_fields+=("tags")

    if [[ ${#drifted_fields[@]} -gt 0 ]]; then
        local joined
        joined="$(IFS=','; echo "${drifted_fields[*]}")"
        echo "UPDATE:${joined}"
    else
        echo "UNCHANGED"
    fi
}

# Expand ~ to $HOME so path comparisons are stable regardless of how the
# path was entered (e.g. "~/foo" vs "/home/mvillmow/foo").
normalize_path() {
    local p="$1"
    echo "${p/#\~/$HOME}"
}
