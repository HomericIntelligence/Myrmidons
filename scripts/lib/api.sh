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

# Validate that an agent name contains only safe characters.
# Prevents path traversal / shell injection in URL construction.
_validate_agent_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "ERROR: Invalid agent name '${name}' — only [a-zA-Z0-9_-] allowed" >&2
        return 1
    fi
}

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
    chmod 600 "$tmpfile"
    trap 'rm -f "$tmpfile"' EXIT INT TERM

    # Write response body to tmpfile; capture HTTP status code separately.
    http_code="$(curl -s --max-time 10 -w "%{http_code}" -o "$tmpfile" "$@")"
    local curl_exit=$?

    response="$(cat "$tmpfile")"
    rm -f "$tmpfile"
    trap - EXIT INT TERM

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

# Internal helper: curl with retry (3 attempts, exponential backoff).
# Retries on: curl network errors (exit 6/7/28) and HTTP 5xx responses.
# Usage: _agamemnon_curl_with_retry [-X METHOD] URL [-H header] [-d body]
_agamemnon_curl_with_retry() {
    local attempt=1
    local max_attempts=3
    local delay=1

    while [[ $attempt -le $max_attempts ]]; do
        local http_code
        local response
        local tmpfile
        tmpfile="$(mktemp)"
        chmod 600 "$tmpfile"

        http_code="$(curl -s --max-time 10 -w "%{http_code}" -o "$tmpfile" "$@" 2>/dev/null)"
        local curl_exit=$?

        response="$(cat "$tmpfile")"
        rm -f "$tmpfile"

        # Retry on network errors: could not resolve host (6), failed to connect (7), timeout (28)
        if [[ $curl_exit -eq 6 || $curl_exit -eq 7 || $curl_exit -eq 28 ]]; then
            echo "WARN: curl network error (exit ${curl_exit}), attempt ${attempt}/${max_attempts}" >&2
        elif [[ $curl_exit -ne 0 ]]; then
            echo "ERROR: curl failed (exit ${curl_exit}) for: $*" >&2
            return 1
        elif [[ "${http_code:0:1}" == "5" ]]; then
            # Retry on HTTP 5xx (server errors)
            echo "WARN: HTTP ${http_code} from Agamemnon, attempt ${attempt}/${max_attempts}" >&2
        else
            # Success or non-retryable error
            if [[ "${http_code:0:1}" != "2" ]]; then
                echo "ERROR: HTTP ${http_code} from Agamemnon" >&2
                echo "  URL: $*" >&2
                if [[ -n "$response" ]]; then
                    echo "  Body: ${response}" >&2
                fi
                return 1
            fi
            echo "$response"
            return 0
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            sleep "$delay"
            delay=$((delay * 2))
        fi
        attempt=$((attempt + 1))
    done

    echo "ERROR: All ${max_attempts} attempts failed for: $*" >&2
    return 1
}

# List all agents registered on this host.
agamemnon_list_agents() {
    _agamemnon_curl_with_retry "${AGAMEMNON_URL}/v1/agents"
}

# Get a single agent by ID.
agamemnon_get_agent() {
    local agent_id="$1"
    _validate_agent_name "$agent_id"
    _agamemnon_curl_with_retry "${AGAMEMNON_URL}/v1/agents/${agent_id}"
}

# Get a single agent by name (rich resolution).
agamemnon_by_name() {
    local name="$1"
    _validate_agent_name "$name"
    _agamemnon_curl_with_retry "${AGAMEMNON_URL}/v1/agents/by-name/${name}"
}

# Create a new agent. $1 = JSON body.
# Required fields: name, program, workingDirectory
agamemnon_create_agent() {
    local body="$1"
    _agamemnon_curl_with_retry -X POST \
        "${AGAMEMNON_URL}/v1/agents" \
        -H 'Content-Type: application/json' \
        -d "${body}"
}

# Partially update an agent. $1 = agent ID, $2 = JSON patch body.
agamemnon_update_agent() {
    local agent_id="$1"
    local body="$2"
    _validate_agent_name "$agent_id"
    _agamemnon_curl_with_retry -X PATCH \
        "${AGAMEMNON_URL}/v1/agents/${agent_id}" \
        -H 'Content-Type: application/json' \
        -d "${body}"
}

# Delete an agent (hard delete creates a backup).
# Always stop first for graceful shutdown.
agamemnon_delete_agent() {
    local agent_id="$1"
    _validate_agent_name "$agent_id"
    _agamemnon_curl_with_retry -X DELETE "${AGAMEMNON_URL}/v1/agents/${agent_id}?hard=true"
}

# Start an agent (starts tmux session + AI program).
agamemnon_wake_agent() {
    local agent_id="$1"
    _validate_agent_name "$agent_id"
    _agamemnon_curl_with_retry -X POST \
        "${AGAMEMNON_URL}/v1/agents/${agent_id}/start" \
        -H 'Content-Type: application/json' \
        -d '{}'
}

# Stop an agent (graceful stop: Ctrl-C, exit, kill tmux).
agamemnon_hibernate_agent() {
    local agent_id="$1"
    _validate_agent_name "$agent_id"
    _agamemnon_curl_with_retry -X POST \
        "${AGAMEMNON_URL}/v1/agents/${agent_id}/stop" \
        -H 'Content-Type: application/json' \
        -d '{}'
}

# Create a Docker-deployed agent.
agamemnon_docker_create() {
    local body="$1"
    _agamemnon_curl_with_retry -X POST \
        "${AGAMEMNON_URL}/v1/agents/docker" \
        -H 'Content-Type: application/json' \
        -d "${body}"
}

# Helper: get agent ID by name. Returns empty string if not found.
agamemnon_id_by_name() {
    local name="$1"
    _validate_agent_name "$name"
    agamemnon_list_agents | jq -r --arg name "$name" \
        '.[] | select(.name == $name) | .id // empty'
}

# Helper: get agent status by name. Returns "unknown" if not found.
agamemnon_status_by_name() {
    local name="$1"
    _validate_agent_name "$name"
    agamemnon_list_agents | jq -r --arg name "$name" \
        '.[] | select(.name == $name) | .status // "unknown"'
}
