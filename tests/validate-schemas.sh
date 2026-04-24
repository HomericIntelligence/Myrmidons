#!/usr/bin/env bash
# tests/validate-schemas.sh — CI: validate all agent YAML files
#
# Used by .github/workflows/validate.yml on every PR.
# Runs the same checks as the pre-commit hook but against ALL YAML files,
# not just staged ones.
#
# Usage:
#   ./tests/validate-schemas.sh
#
# Exit codes:
#   0 = all valid
#   1 = validation errors found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ERRORS=0
CHECKED=0

if ! command -v yq &>/dev/null; then
    echo "ERROR: yq is required for schema validation." >&2
    echo "  Install: curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq" >&2
    exit 1
fi

echo "Validating all agent and fleet YAML files..."
echo ""

# Associative array to track agent names for uniqueness check
declare -A agent_names

# Find all YAML files (excluding templates)
while IFS= read -r -d '' file; do
    [[ "$file" == *"/_templates/"* ]] && continue

    CHECKED=$((CHECKED + 1))
    echo -n "  ${file#"${REPO_ROOT}/"}: "

    # YAML syntax check
    if ! yq eval '.' "$file" > /dev/null 2>&1; then
        echo "FAIL (invalid YAML syntax)"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    api_version="$(yq eval '.apiVersion // ""' "$file")"
    kind="$(yq eval '.kind // ""' "$file")"

    # apiVersion check
    if [[ "$api_version" != "myrmidons/v1" ]]; then
        echo "FAIL (expected apiVersion=myrmidons/v1, got '${api_version}')"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    # kind check
    if [[ "$kind" != "Agent" && "$kind" != "Fleet" ]]; then
        echo "FAIL (expected kind=Agent or Fleet, got '${kind}')"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    if [[ "$kind" == "Fleet" ]]; then
        field_errors=()
        fleet_name="$(yq eval '.metadata.name // ""' "$file")"
        [[ -z "$fleet_name" ]] && field_errors+=("metadata.name is required in Fleet")

        # Validate Fleet filename matches metadata.name (same convention as Agents)
        if [[ -n "$fleet_name" ]]; then
            expected_filename="$(echo "$fleet_name" | tr '[:upper:]' '[:lower:]').yaml"
            actual_filename="$(basename "$file")"
            if [[ "$actual_filename" != "$expected_filename" ]]; then
                field_errors+=("filename '$actual_filename' does not match metadata.name '$fleet_name' (expected '$expected_filename')")
            fi
        fi

        if [[ ${#field_errors[@]} -gt 0 ]]; then
            echo "FAIL"
            for err in "${field_errors[@]}"; do
                echo "      - ${err}"
            done
            ERRORS=$((ERRORS + 1))
        else
            echo "ok (Fleet: ${fleet_name})"
        fi

        # Track names for uniqueness check (only non-empty names to avoid false positives)
        [[ -n "$fleet_name" ]] && agent_names["$fleet_name"]+=" $file"
        continue
    fi

    # Agent validation
    field_errors=()

    name="$(yq eval '.metadata.name // ""' "$file")"
    host="$(yq eval '.metadata.host // ""' "$file")"
    program="$(yq eval '.spec.program // ""' "$file")"
    workdir="$(yq eval '.spec.workingDirectory // ""' "$file")"
    desired_state="$(yq eval '.spec.desiredState // ""' "$file")"
    deploy_type="$(yq eval '.spec.deployment.type // "local"' "$file")"

    [[ -z "$name" ]] && field_errors+=("metadata.name is required")
    [[ -z "$host" ]] && field_errors+=("metadata.host is required")
    [[ -z "$program" ]] && field_errors+=("spec.program is required")
    [[ -z "$workdir" ]] && field_errors+=("spec.workingDirectory is required")

    # Validate spec.program against known enum
    if [[ -n "$program" ]]; then
        case "$program" in
            claude-code|aider|codex|goose|cline|opencode|codebuff|ampcode|none) ;;
            *) field_errors+=("spec.program must be one of: claude-code aider codex goose cline opencode codebuff ampcode none (got '${program}')") ;;
        esac
    fi

    if [[ -n "$desired_state" ]]; then
        [[ "$desired_state" != "active" && "$desired_state" != "hibernated" ]] && \
            field_errors+=("spec.desiredState must be 'active' or 'hibernated'")
    fi

    if [[ "$deploy_type" != "local" && "$deploy_type" != "docker" ]]; then
        field_errors+=("spec.deployment.type must be 'local' or 'docker'")
    fi

    # Validate docker image is present when deployment.type=docker
    if [[ "$deploy_type" == "docker" ]]; then
        docker_image="$(yq eval '.spec.deployment.docker.image // ""' "$file")"
        [[ -z "$docker_image" ]] && field_errors+=("spec.deployment.docker.image is required when deployment.type is 'docker'")
    fi

    # Validate metadata.host matches the parent directory name
    if [[ -n "$host" ]]; then
        dir_host="$(basename "$(dirname "$file")")"
        if [[ "$dir_host" != "$host" ]]; then
            field_errors+=("metadata.host '${host}' does not match directory '${dir_host}'")
        fi
    fi

    # Warn if workingDirectory does not exist (skipped in CI)
    if [[ -n "$workdir" && "${CI:-}" != "true" ]]; then
        if [[ ! -d "$workdir" ]]; then
            echo "WARNING: ${file#"${REPO_ROOT}/"}: spec.workingDirectory '${workdir}' does not exist on this host" >&2
        fi
    fi

    if [[ ${#field_errors[@]} -gt 0 ]]; then
        echo "FAIL"
        for err in "${field_errors[@]}"; do
            echo "      - ${err}"
        done
        ERRORS=$((ERRORS + 1))
    else
        echo "ok (Agent: ${name})"
    fi

    # Track names for uniqueness check (only non-empty names to avoid false positives)
    [[ -n "$name" ]] && agent_names["$name"]+=" $file"

done < <(find "${REPO_ROOT}/agents" "${REPO_ROOT}/fleets" \
    -name "*.yaml" -print0 2>/dev/null)

# Cross-file name uniqueness check
for agent_name in "${!agent_names[@]}"; do
    files_with_name="${agent_names[$agent_name]}"
    # Count non-empty tokens (file paths are separated by spaces)
    count=0
    for f in $files_with_name; do
        [[ -n "$f" ]] && count=$((count + 1))
    done
    if [[ $count -gt 1 ]]; then
        echo "  ERROR: duplicate metadata.name '${agent_name}' found in:"
        for f in $files_with_name; do
            [[ -n "$f" ]] && echo "    - ${f#"${REPO_ROOT}/"}"
        done
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
echo "Checked: ${CHECKED} files, Errors: ${ERRORS}"

if [[ $ERRORS -gt 0 ]]; then
    exit 1
fi
exit 0
