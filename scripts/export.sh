#!/usr/bin/env bash
# scripts/export.sh — Bootstrap: export current ai-maestro agents to YAML
#
# Reads the current agent registry from ai-maestro and writes one YAML
# file per agent into agents/<host>/.
#
# Usage:
#   ./scripts/export.sh hermes
#   ./scripts/export.sh                # defaults to "hermes"
#
# This is the Phase 1 bootstrap script. Run it once to seed Myrmidons
# from the current ai-maestro state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/api.sh
source "${SCRIPT_DIR}/lib/api.sh"

HOST="${1:-hermes}"
OUTPUT_DIR="${REPO_ROOT}/agents/${HOST}"

main() {
    check_jq
    aim_check_connection

    echo "Exporting agents from ai-maestro (${AIM_HOST}) for host: ${HOST}"
    echo ""

    mkdir -p "${OUTPUT_DIR}"

    local agents_json
    agents_json="$(aim_list_agents)"

    local count
    count="$(echo "$agents_json" | jq 'length')"

    if [[ "$count" -eq 0 ]]; then
        echo "No agents found in ai-maestro."
        exit 0
    fi

    echo "$agents_json" | jq -c '.[]' | while IFS= read -r agent; do
        export_agent "$agent"
    done

    echo ""
    echo "Exported ${count} agents to ${OUTPUT_DIR}/"
}

check_jq() {
    if ! command -v jq &>/dev/null; then
        echo "ERROR: jq is required. Install: apt install jq" >&2
        exit 1
    fi
}

# Derive a safe filename from agent name (replaces - and _ with -)
agent_filename() {
    local name="$1"
    # Use label (lowercased) if available, else use name
    echo "${name}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
}

# Map program name → default AchaeanFleet image name
program_to_image() {
    local prog="$1"
    case "$prog" in
        claude-code|claude) echo "achaean-claude:latest" ;;
        codex)              echo "achaean-codex:latest" ;;
        aider)              echo "achaean-aider:latest" ;;
        goose)              echo "achaean-goose:latest" ;;
        cline)              echo "achaean-cline:latest" ;;
        opencode)           echo "achaean-opencode:latest" ;;
        codebuff)           echo "achaean-codebuff:latest" ;;
        ampcode)            echo "achaean-ampcode:latest" ;;
        none|worker|"")     echo "achaean-worker:latest" ;;
        *)                  echo "achaean-worker:latest" ;;
    esac
}

export_agent() {
    local agent_json="$1"

    local name label program model workdir args desc owner role status deployment_type
    name="$(echo "$agent_json" | jq -r '.name')"
    label="$(echo "$agent_json" | jq -r '.label // .name')"
    program="$(echo "$agent_json" | jq -r '.program // "claude-code"')"
    model="$(echo "$agent_json" | jq -r '.model // "null"')"
    workdir="$(echo "$agent_json" | jq -r '.workingDirectory // ""')"
    args="$(echo "$agent_json" | jq -r '.programArgs // ""')"
    desc="$(echo "$agent_json" | jq -r '.taskDescription // ""')"
    owner="$(echo "$agent_json" | jq -r '.owner // "mvillmow"')"
    role="$(echo "$agent_json" | jq -r '.role // "member"')"
    status="$(echo "$agent_json" | jq -r '.status // "offline"')"
    deployment_type="$(echo "$agent_json" | jq -r '.deployment.type // "local"')"

    # Map current status to desiredState
    local desired_state="hibernated"
    if [[ "$status" == "active" || "$status" == "online" ]]; then
        desired_state="active"
    fi

    # Build tags YAML list
    local tags_yaml
    tags_yaml="$(echo "$agent_json" | jq -r '.tags // [] | if length == 0 then "  tags: []" else "  tags:\n" + (map("    - " + .) | join("\n")) end')"

    # Determine filename from label (lowercased, spaces→dashes)
    local label_lower
    label_lower="$(echo "$label" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
    local outfile="${OUTPUT_DIR}/${label_lower}.yaml"

    # Handle model: if "null" string, write null (no quotes)
    local model_yaml
    if [[ "$model" == "null" || -z "$model" ]]; then
        model_yaml="null"
    else
        model_yaml="\"${model}\""
    fi

    # Map program → correct docker image
    local docker_image
    docker_image="$(program_to_image "$program")"

    # Use jq to safely quote string fields that may contain special characters.
    # Scalar YAML strings only need quoting when they contain: :, #, {, }, [, ], , &, * ! | > ' " % @ `
    # Using double-quoted YAML strings throughout is safe and simple.
    local name_yaml label_yaml program_yaml workdir_yaml owner_yaml role_yaml
    name_yaml="$(echo "$name" | jq -Rr '.')"
    label_yaml="$(echo "$label" | jq -Rr '.')"
    program_yaml="$(echo "$program" | jq -Rr '.')"
    workdir_yaml="$(echo "$workdir" | jq -Rr '.')"
    owner_yaml="$(echo "$owner" | jq -Rr '.')"
    role_yaml="$(echo "$role" | jq -Rr '.')"

    # args and desc always get explicit double-quotes in the YAML
    local args_escaped desc_escaped
    args_escaped="$(echo "$args" | jq -Rr '.')"
    desc_escaped="$(echo "$desc" | jq -Rr '.')"

    cat > "$outfile" <<YAML
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: ${name_yaml}
  host: ${HOST}
spec:
  label: ${label_yaml}
  program: ${program_yaml}
  model: ${model_yaml}
  workingDirectory: ${workdir_yaml}
  programArgs: "${args_escaped}"
  taskDescription: "${desc_escaped}"
${tags_yaml}
  owner: ${owner_yaml}
  role: ${role_yaml}
  deployment:
    type: ${deployment_type}
    docker:
      image: ${docker_image}
      cpus: 2
      memory: 4g
  desiredState: ${desired_state}
YAML

    echo "  ${outfile}"
}

main "$@"
