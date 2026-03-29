#!/usr/bin/env bash
# scripts/lib/api.sh — ProjectAgamemnon API client
#
# Thin wrapper around curl calls to the ProjectAgamemnon REST API.
# All functions print raw JSON to stdout. Callers parse with jq.
#
# Usage:
#   source scripts/lib/api.sh
#   agamemnon_list_agents | jq '.[].name'

set -euo pipefail

AGAMEMNON_URL="${AGAMEMNON_URL:-http://localhost:8080}"

# Check that Agamemnon is reachable before making calls.
agamemnon_check_connection() {
    if ! curl -sf --max-time 5 "${AGAMEMNON_URL}/v1/health" > /dev/null 2>&1; then
        echo "ERROR: Cannot reach Agamemnon at ${AGAMEMNON_URL}" >&2
        echo "  Is Agamemnon running? Check your ProjectAgamemnon deployment." >&2
        return 1
    fi
}

# Internal helper: curl with standard flags (timeout, error output on failure).
# Usage: _agamemnon_curl [-X METHOD] URL [-H header] [-d body]
_agamemnon_curl() {
    local http_code
    local response
    local tmpfile
    tmpfile="$(mktemp)"

    # Write response body to tmpfile; capture HTTP status code separately.
    http_code="$(curl -s --max-time 10 -w "%{http_code}" -o "$tmpfile" "$@")"
    local curl_exit=$?

    response="$(cat "$tmpfile")"
    rm -f "$tmpfile"

    if [[ $curl_exit -ne 0 ]]; then
        echo "ERROR: curl failed (exit ${curl_exit}) for: $*" >&2
        return 1
    fi

    if [[ "${http_code:0:1}" != "2" ]]; then
        echo "ERROR: HTTP ${http_code} from Agamemnon" >&2
        echo "  URL: $*" >&2
        if [[ -n "$response" ]]; then
            echo "  Body: ${response}" >&2
        fi
        return 1
    fi

    echo "$response"
}

# List all agents registered on this host.
agamemnon_list_agents() {
    _agamemnon_curl "${AGAMEMNON_URL}/v1/agents"
}

# Get a single agent by ID.
agamemnon_get_agent() {
    local agent_id="$1"
    _agamemnon_curl "${AGAMEMNON_URL}/v1/agents/${agent_id}"
}

# Get a single agent by name (rich resolution).
agamemnon_by_name() {
    local name="$1"
    _agamemnon_curl "${AGAMEMNON_URL}/v1/agents/by-name/${name}"
}

# Create a new agent. $1 = JSON body.
# Required fields: name, program, workingDirectory
agamemnon_create_agent() {
    local body="$1"
    _agamemnon_curl -X POST \
        "${AGAMEMNON_URL}/v1/agents" \
        -H 'Content-Type: application/json' \
        -d "${body}"
}

# Partially update an agent. $1 = agent ID, $2 = JSON patch body.
agamemnon_update_agent() {
    local agent_id="$1"
    local body="$2"
    _agamemnon_curl -X PATCH \
        "${AGAMEMNON_URL}/v1/agents/${agent_id}" \
        -H 'Content-Type: application/json' \
        -d "${body}"
}

# Delete an agent (hard delete creates a backup).
# Always stop first for graceful shutdown.
agamemnon_delete_agent() {
    local agent_id="$1"
    _agamemnon_curl -X DELETE "${AGAMEMNON_URL}/v1/agents/${agent_id}?hard=true"
}

# Start an agent (starts tmux session + AI program).
agamemnon_wake_agent() {
    local agent_id="$1"
    _agamemnon_curl -X POST \
        "${AGAMEMNON_URL}/v1/agents/${agent_id}/start" \
        -H 'Content-Type: application/json' \
        -d '{}'
}

# Stop an agent (graceful stop: Ctrl-C, exit, kill tmux).
agamemnon_hibernate_agent() {
    local agent_id="$1"
    _agamemnon_curl -X POST \
        "${AGAMEMNON_URL}/v1/agents/${agent_id}/stop" \
        -H 'Content-Type: application/json' \
        -d '{}'
}

# Create a Docker-deployed agent.
agamemnon_docker_create() {
    local body="$1"
    _agamemnon_curl -X POST \
        "${AGAMEMNON_URL}/v1/agents/docker" \
        -H 'Content-Type: application/json' \
        -d "${body}"
}

# Helper: get agent ID by name. Returns empty string if not found.
agamemnon_id_by_name() {
    local name="$1"
    agamemnon_list_agents | jq -r --arg name "$name" \
        '.[] | select(.name == $name) | .id // empty'
}

# Helper: get agent status by name. Returns "unknown" if not found.
agamemnon_status_by_name() {
    local name="$1"
    agamemnon_list_agents | jq -r --arg name "$name" \
        '.[] | select(.name == $name) | .status // "unknown"'
}

