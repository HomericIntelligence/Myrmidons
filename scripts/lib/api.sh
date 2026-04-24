#!/usr/bin/env bash
# scripts/lib/api.sh — ProjectAgamemnon API client
#
# Thin wrapper around curl calls to the ProjectAgamemnon REST API.
# All functions print raw JSON to stdout. Callers parse with jq.
#
# Usage:
#   source scripts/lib/api.sh
#   agamemnon_list_agents | jq '.[].name'
#
# TLS environment variables:
#   AGAMEMNON_CA_CERT     Path to custom CA certificate bundle (PEM)
#   AGAMEMNON_CLIENT_CERT Path to client certificate for mutual TLS (PEM)
#   AGAMEMNON_CLIENT_KEY  Path to client private key for mutual TLS (PEM)
#   AGAMEMNON_TLS_VERIFY  Set to "false" or "0" to disable TLS verification
#                         (insecure — only for development; emits a loud warning)

set -euo pipefail

AGAMEMNON_URL="${AGAMEMNON_URL:-http://localhost:8080}"
AGAMEMNON_API_KEY="${AGAMEMNON_API_KEY:-}"

# Build the TLS flags array for curl based on environment variables.
# Populates the global _AGAMEMNON_TLS_FLAGS array; call once at source time.
_agamemnon_build_tls_flags() {
    _AGAMEMNON_TLS_FLAGS=()

    # Disable TLS verification escape hatch — warn loudly.
    local tls_verify="${AGAMEMNON_TLS_VERIFY:-true}"
    if [[ "$tls_verify" == "false" || "$tls_verify" == "0" ]]; then
        echo "WARNING: TLS verification is DISABLED (AGAMEMNON_TLS_VERIFY=${tls_verify})." >&2
        echo "  This is insecure and must not be used in production." >&2
        _AGAMEMNON_TLS_FLAGS+=(--insecure)
    fi

    # Custom CA certificate bundle.
    if [[ -n "${AGAMEMNON_CA_CERT:-}" ]]; then
        _AGAMEMNON_TLS_FLAGS+=(--cacert "${AGAMEMNON_CA_CERT}")
    fi

    # Mutual TLS: client certificate + key.
    if [[ -n "${AGAMEMNON_CLIENT_CERT:-}" ]]; then
        _AGAMEMNON_TLS_FLAGS+=(--cert "${AGAMEMNON_CLIENT_CERT}")
    fi
    if [[ -n "${AGAMEMNON_CLIENT_KEY:-}" ]]; then
        _AGAMEMNON_TLS_FLAGS+=(--key "${AGAMEMNON_CLIENT_KEY}")
    fi
}

# Initialise TLS flags when this library is sourced.
_agamemnon_build_tls_flags

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

# Validate that AGAMEMNON_URL is set and has a recognised scheme (http/https).
# Call this early in any entry-point script before issuing API calls.
validate_agamemnon_url() {
    local url="${AGAMEMNON_URL:-}"
    if [[ -z "$url" ]]; then
        echo "ERROR: AGAMEMNON_URL is not set." >&2
        echo "  Export AGAMEMNON_URL before running this script." >&2
        echo "  Example: export AGAMEMNON_URL=http://localhost:8080" >&2
        return 1
    fi
    case "$url" in
        http://*|https://*)
            ;;
        *)
            echo "ERROR: AGAMEMNON_URL has an unrecognised scheme: ${url}" >&2
            echo "  Expected a URL beginning with http:// or https://" >&2
            return 1
            ;;
    esac
}

# Check that Agamemnon is reachable before making calls.
agamemnon_check_connection() {
    _agamemnon_auth_headers
    if ! curl -sf --max-time 5 "${_AGAMEMNON_TLS_FLAGS[@]+"${_AGAMEMNON_TLS_FLAGS[@]}"}" \
            "${_AUTH_HEADERS[@]+"${_AUTH_HEADERS[@]}"}" "${AGAMEMNON_URL}/v1/health" > /dev/null 2>&1; then
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
            "${_AGAMEMNON_TLS_FLAGS[@]+"${_AGAMEMNON_TLS_FLAGS[@]}"}" "${_AUTH_HEADERS[@]+"${_AUTH_HEADERS[@]}"}" "$@" 2>/dev/null)"
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
                if [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
                    echo "ERROR: Authentication failed (HTTP ${http_code}) — check AGAMEMNON_API_KEY" >&2
                else
                    echo "ERROR: HTTP ${http_code} from Agamemnon" >&2
                    echo "  URL: $*" >&2
                    if [[ -n "$response" ]]; then
                        echo "  Body: ${response}" >&2
                    fi
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
