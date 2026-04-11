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
AGAMEMNON_TIMEOUT="${AGAMEMNON_TIMEOUT:-10}"

# Validate that AGAMEMNON_URL matches an expected safe format.
# Accepts only http:// or https:// followed by hostname/IP with optional port/path.
# Rejects embedded credentials, unusual characters, or other injection vectors.
_agamemnon_validate_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https?://[a-zA-Z0-9._-]+(:[0-9]+)?(/[a-zA-Z0-9._~:@!$&\'()*+,;=%-]*)*$ ]]; then
        echo "ERROR: AGAMEMNON_URL contains an invalid or unsafe value: '${url}'" >&2
        echo "  Expected format: http(s)://hostname[:port][/path]" >&2
        echo "  Only alphanumeric hostnames and standard URL characters are permitted." >&2
        return 1
    fi
}

# Check that Agamemnon is reachable before making calls.
# Also validates AGAMEMNON_URL format to prevent SSRF via env var injection.
agamemnon_check_connection() {
    _agamemnon_validate_url "${AGAMEMNON_URL}"

    echo "Connecting to Agamemnon at: ${AGAMEMNON_URL}"

    if ! curl -sf --max-time 5 "${AGAMEMNON_URL}/v1/health" > /dev/null 2>&1; then
        log_error "Cannot reach Agamemnon at ${AGAMEMNON_URL}"
        log_error "  Is Agamemnon running? Check your ProjectAgamemnon deployment."
        return 1
    fi
}

# Internal helper: curl with standard flags (timeout, error output on failure).
# Usage: _agamemnon_curl [-X METHOD] URL [-H header] [-d body]
_agamemnon_curl() {
    local http_code
    local response
    local tmpdir
    local tmpfile
    tmpdir="$(mktemp -d)"
    tmpfile="${tmpdir}/response"
    # Ensure private temp dir is cleaned up on function return, even if interrupted.
    trap "rm -rf '${tmpdir}'" RETURN

    # Write response body to tmpfile; capture HTTP status code separately.
    http_code="$(curl -s --max-time "${AGAMEMNON_TIMEOUT}" -w "%{http_code}" -o "$tmpfile" "$@")"
    local curl_exit=$?

    response="$(cat "$tmpfile")"
    # tmpdir cleaned up by trap on RETURN

    if [[ $curl_exit -ne 0 ]]; then
        log_error "curl failed (exit ${curl_exit}) for: $*"
        return 1
    fi

    if [[ "${http_code:0:1}" != "2" ]]; then
        log_error "HTTP ${http_code} from Agamemnon"
        log_error "  URL: $*"
        if [[ -n "$response" ]]; then
            log_error "  Body: ${response}"
        fi
        return 1
    fi

    echo "$response"
}

# Retry wrapper around _agamemnon_curl with exponential backoff.
# Retries on transient errors: curl exit 7 (connection refused), exit 28 (timeout),
# or HTTP 5xx responses. Fails immediately on HTTP 4xx (permanent errors).
# Usage: _agamemnon_curl_retry [-X METHOD] URL [-H header] [-d body]
_agamemnon_curl_retry() {
    local max_attempts=3
    local delay=1
    local attempt=1
    local http_code response tmpfile curl_exit

    while [[ $attempt -le $max_attempts ]]; do
        tmpfile="$(mktemp)"
        http_code="$(curl -s --max-time "${AGAMEMNON_TIMEOUT}" -w "%{http_code}" -o "$tmpfile" "$@" 2>/dev/null)"
        curl_exit=$?
        response="$(cat "$tmpfile")"
        rm -f "$tmpfile"

        # Success
        if [[ $curl_exit -eq 0 && "${http_code:0:1}" == "2" ]]; then
            echo "$response"
            return 0
        fi

        # Classify the failure
        local is_transient=0

        # curl exit 7 = connection refused, exit 28 = timeout
        if [[ $curl_exit -eq 7 || $curl_exit -eq 28 ]]; then
            is_transient=1
        elif [[ $curl_exit -ne 0 ]]; then
            # Other curl errors are not transient
            is_transient=0
        elif [[ "${http_code:0:1}" == "5" ]]; then
            # HTTP 5xx = server-side transient error
            is_transient=1
        fi
        # HTTP 4xx = permanent client error — fail immediately

        if [[ $is_transient -eq 0 ]]; then
            # Permanent failure — report and return
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

    # All attempts exhausted
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

# List all agents registered on this host.
agamemnon_list_agents() {
    _agamemnon_curl_retry "${AGAMEMNON_URL}/v1/agents"
}

# Get a single agent by ID.
agamemnon_get_agent() {
    local agent_id="$1"
    _agamemnon_curl_retry "${AGAMEMNON_URL}/v1/agents/${agent_id}"
}

# Get a single agent by name (rich resolution).
agamemnon_by_name() {
    local name="$1"
    _agamemnon_curl_retry "${AGAMEMNON_URL}/v1/agents/by-name/${name}"
}

# Create a new agent. $1 = JSON body.
# Required fields: name, program, workingDirectory
agamemnon_create_agent() {
    local body="$1"
    _agamemnon_curl_retry -X POST \
        "${AGAMEMNON_URL}/v1/agents" \
        -H 'Content-Type: application/json' \
        -d "${body}"
}

# Partially update an agent. $1 = agent ID, $2 = JSON patch body.
agamemnon_update_agent() {
    local agent_id="$1"
    local body="$2"
    _agamemnon_curl_retry -X PATCH \
        "${AGAMEMNON_URL}/v1/agents/${agent_id}" \
        -H 'Content-Type: application/json' \
        -d "${body}"
}

# Delete an agent (hard delete creates a backup).
# Always stop first for graceful shutdown.
agamemnon_delete_agent() {
    local agent_id="$1"
    _agamemnon_curl_retry -X DELETE "${AGAMEMNON_URL}/v1/agents/${agent_id}?hard=true"
}

# Start an agent (starts tmux session + AI program).
agamemnon_wake_agent() {
    local agent_id="$1"
    _agamemnon_curl_retry -X POST \
        "${AGAMEMNON_URL}/v1/agents/${agent_id}/start" \
        -H 'Content-Type: application/json' \
        -d '{}'
}

# Stop an agent (graceful stop: Ctrl-C, exit, kill tmux).
agamemnon_hibernate_agent() {
    local agent_id="$1"
    _agamemnon_curl_retry -X POST \
        "${AGAMEMNON_URL}/v1/agents/${agent_id}/stop" \
        -H 'Content-Type: application/json' \
        -d '{}'
}

# Create a Docker-deployed agent.
agamemnon_docker_create() {
    local body="$1"
    _agamemnon_curl_retry -X POST \
        "${AGAMEMNON_URL}/v1/agents/docker" \
        -H 'Content-Type: application/json' \
        -d "${body}"
}

# NOTE: The helpers below each call agamemnon_list_agents internally.
# They are not used by apply.sh (which manages its own cached list).
# Use only in scripts where a one-off lookup is acceptable.

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
        'map(select(.name == $name)) | if length > 0 then .[0].status // "unknown" else "unknown" end')"
    echo "$status"
}

