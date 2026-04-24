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
AGAMEMNON_API_KEY="${AGAMEMNON_API_KEY:-}"

# Build auth headers array for curl. Populates _AUTH_HEADERS global array.
# Prefers Authorization: Bearer when AGAMEMNON_API_KEY is set.
# Falls back to no auth (backward compatible).
_agamemnon_auth_headers() {
    _AUTH_HEADERS=()
    if [[ -n "${AGAMEMNON_API_KEY}" ]]; then
        _AUTH_HEADERS+=(-H "Authorization: Bearer ${AGAMEMNON_API_KEY}")
        _AUTH_HEADERS+=(-H "X-API-Key: ${AGAMEMNON_API_KEY}")
    fi
}

# Check that Agamemnon is reachable before making calls.
agamemnon_check_connection() {
    _agamemnon_auth_headers
    if ! curl -sf --max-time 5 "${_AUTH_HEADERS[@]+"${_AUTH_HEADERS[@]}"}" "${AGAMEMNON_URL}/v1/health" > /dev/null 2>&1; then
        echo "ERROR: Cannot reach Agamemnon at ${AGAMEMNON_URL}" >&2
        echo "  Is Agamemnon running? Check your ProjectAgamemnon deployment." >&2
        return 1
    fi
}

# Internal helper: curl with retry on transient errors (connection refused, timeout, 5xx).
# Injects auth headers automatically when AGAMEMNON_API_KEY is set.
# Usage: _agamemnon_curl_retry [-X METHOD] URL [-H header] [-d body]
_agamemnon_curl_retry() {
    local max_attempts=3
    local delay=1
    local attempt=1
    local http_code response tmpfile curl_exit

    _agamemnon_auth_headers

    while [[ $attempt -le $max_attempts ]]; do
        tmpfile="$(mktemp)"
        http_code="$(curl -s --max-time "${AGAMEMNON_TIMEOUT:-10}" -w "%{http_code}" -o "$tmpfile" \
            "${_AUTH_HEADERS[@]+"${_AUTH_HEADERS[@]}"}" "$@" 2>/dev/null)"
        curl_exit=$?
        response="$(cat "$tmpfile")"
        rm -f "$tmpfile"

        # Success
        if [[ $curl_exit -eq 0 && "${http_code:0:1}" == "2" ]]; then
            echo "$response"
            return 0
        fi

        # Classify failure: transient = retry; permanent = fail immediately
        local is_transient=0
        if [[ $curl_exit -eq 7 || $curl_exit -eq 28 ]]; then
            is_transient=1
        elif [[ $curl_exit -ne 0 ]]; then
            is_transient=0
        elif [[ "${http_code:0:1}" == "5" ]]; then
            is_transient=1
        fi

        if [[ $is_transient -eq 0 ]]; then
            if [[ $curl_exit -ne 0 ]]; then
                echo "ERROR: curl failed (exit ${curl_exit}) for: $*" >&2
            else
                echo "ERROR: HTTP ${http_code} from Agamemnon" >&2
                echo "  URL: $*" >&2
                if [[ -n "$response" ]]; then
                    echo "  Body: ${response}" >&2
                fi
            fi
            return 1
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            echo "WARN: Retry ${attempt}/${max_attempts} in ${delay}s (curl_exit=${curl_exit} http=${http_code}): $*" >&2
            sleep "$delay"
            delay=$((delay * 2))
        fi

        attempt=$((attempt + 1))
    done

    if [[ $curl_exit -ne 0 ]]; then
        echo "ERROR: curl failed after ${max_attempts} attempts (exit ${curl_exit}) for: $*" >&2
    else
        echo "ERROR: HTTP ${http_code} from Agamemnon after ${max_attempts} attempts" >&2
        echo "  URL: $*" >&2
        if [[ -n "$response" ]]; then
            echo "  Body: ${response}" >&2
        fi
    fi
    return 1
}

# Internal helper: single curl call with auth headers.
# All API functions delegate here. Uses retry logic from _agamemnon_curl_retry.
# Usage: _agamemnon_curl [-X METHOD] URL [-H header] [-d body]
_agamemnon_curl() {
    _agamemnon_curl_retry "$@"
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
    local status
    status="$(agamemnon_list_agents | jq -r --arg name "$name" \
        'first(.[] | select(.name == $name) | .status) // "unknown"')"
    echo "${status:-unknown}"
}

