#!/usr/bin/env bash
# scripts/lib/api.sh — ai-maestro API client
#
# Thin wrapper around curl calls to the ai-maestro REST API.
# All functions print raw JSON to stdout. Callers parse with jq.
#
# Usage:
#   source scripts/lib/api.sh
#   aim_list_agents | jq '.[].name'

set -euo pipefail

AIM_HOST="${AIM_HOST:-http://localhost:23000}"

# Check that ai-maestro is reachable before making calls.
aim_check_connection() {
    if ! curl -sf --max-time 5 "${AIM_HOST}/api/sessions" > /dev/null 2>&1; then
        echo "ERROR: Cannot reach ai-maestro at ${AIM_HOST}" >&2
        echo "  Is ai-maestro running? Check: pm2 status ai-maestro" >&2
        return 1
    fi
}

# List all agents registered on this host.
aim_list_agents() {
    curl -sf "${AIM_HOST}/api/agents"
}

# Get a single agent by ID.
aim_get_agent() {
    local agent_id="$1"
    curl -sf "${AIM_HOST}/api/agents/${agent_id}"
}

# Get a single agent by name (rich resolution).
aim_by_name() {
    local name="$1"
    curl -sf "${AIM_HOST}/api/agents/by-name/${name}"
}

# Create a new agent. $1 = JSON body.
# Required fields: name, program, workingDirectory
aim_create_agent() {
    local body="$1"
    curl -sf -X POST \
        "${AIM_HOST}/api/agents" \
        -H 'Content-Type: application/json' \
        -d "${body}"
}

# Partially update an agent. $1 = agent ID, $2 = JSON patch body.
aim_update_agent() {
    local agent_id="$1"
    local body="$2"
    curl -sf -X PATCH \
        "${AIM_HOST}/api/agents/${agent_id}" \
        -H 'Content-Type: application/json' \
        -d "${body}"
}

# Delete an agent (hard delete creates a backup).
# Always hibernate first for graceful shutdown.
aim_delete_agent() {
    local agent_id="$1"
    curl -sf -X DELETE "${AIM_HOST}/api/agents/${agent_id}?hard=true"
}

# Wake an agent (starts tmux session + AI program).
aim_wake_agent() {
    local agent_id="$1"
    curl -sf -X POST \
        "${AIM_HOST}/api/agents/${agent_id}/wake" \
        -H 'Content-Type: application/json' \
        -d '{}'
}

# Hibernate an agent (graceful stop: Ctrl-C, exit, kill tmux).
aim_hibernate_agent() {
    local agent_id="$1"
    curl -sf -X POST \
        "${AIM_HOST}/api/agents/${agent_id}/hibernate" \
        -H 'Content-Type: application/json' \
        -d '{}'
}

# Create a Docker-deployed agent.
aim_docker_create() {
    local body="$1"
    curl -sf -X POST \
        "${AIM_HOST}/api/agents/docker/create" \
        -H 'Content-Type: application/json' \
        -d "${body}"
}

# Helper: get agent ID by name. Returns empty string if not found.
aim_id_by_name() {
    local name="$1"
    aim_list_agents | jq -r --arg name "$name" \
        '.[] | select(.name == $name) | .id // empty'
}

# Helper: get agent status by name. Returns "unknown" if not found.
aim_status_by_name() {
    local name="$1"
    aim_list_agents | jq -r --arg name "$name" \
        '.[] | select(.name == $name) | .status // "unknown"'
}
