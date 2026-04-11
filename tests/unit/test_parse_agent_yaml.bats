#!/usr/bin/env bats
# tests/unit/test_parse_agent_yaml.bats — Unit tests for parse_agent_yaml()
#
# Tests that the YAML parser correctly extracts all fields from agent definitions.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
FIXTURES="${REPO_ROOT}/tests/fixtures"

setup() {
    # shellcheck source=scripts/lib/reconcile.sh
    source "${REPO_ROOT}/scripts/lib/reconcile.sh"
}

# Helper: parse YAML and extract a single key value
parse_field() {
    local file="$1"
    local key="$2"
    parse_agent_yaml "$file" | grep "^${key}=" | cut -d= -f2-
}

@test "parse_agent_yaml: extracts name from minimal YAML" {
    result="$(parse_field "${FIXTURES}/minimal.yaml" "name")"
    [ "$result" = "minimal-agent" ]
}

@test "parse_agent_yaml: extracts host from minimal YAML" {
    result="$(parse_field "${FIXTURES}/minimal.yaml" "host")"
    [ "$result" = "hermes" ]
}

@test "parse_agent_yaml: extracts program from minimal YAML" {
    result="$(parse_field "${FIXTURES}/minimal.yaml" "program")"
    [ "$result" = "claude-code" ]
}

@test "parse_agent_yaml: extracts workingDirectory from minimal YAML" {
    result="$(parse_field "${FIXTURES}/minimal.yaml" "workingDirectory")"
    [ "$result" = "/home/mvillmow/minimal" ]
}

@test "parse_agent_yaml: desiredState defaults to active in minimal YAML" {
    result="$(parse_field "${FIXTURES}/minimal.yaml" "desiredState")"
    [ "$result" = "active" ]
}

@test "parse_agent_yaml: deploymentType defaults to local in minimal YAML" {
    result="$(parse_field "${FIXTURES}/minimal.yaml" "deploymentType")"
    [ "$result" = "local" ]
}

@test "parse_agent_yaml: extracts label from full YAML" {
    result="$(parse_field "${FIXTURES}/full.yaml" "label")"
    [ "$result" = "Full Agent" ]
}

@test "parse_agent_yaml: extracts programArgs from full YAML" {
    result="$(parse_field "${FIXTURES}/full.yaml" "programArgs")"
    [ "$result" = "--verbose" ]
}

@test "parse_agent_yaml: extracts taskDescription from full YAML" {
    result="$(parse_field "${FIXTURES}/full.yaml" "taskDescription")"
    [ "$result" = "A fully specified agent for testing" ]
}

@test "parse_agent_yaml: extracts tags as comma-joined string" {
    result="$(parse_field "${FIXTURES}/full.yaml" "tags")"
    [ "$result" = "test,unit" ]
}

@test "parse_agent_yaml: extracts owner from full YAML" {
    result="$(parse_field "${FIXTURES}/full.yaml" "owner")"
    [ "$result" = "mvillmow" ]
}

@test "parse_agent_yaml: extracts role from full YAML" {
    result="$(parse_field "${FIXTURES}/full.yaml" "role")"
    [ "$result" = "member" ]
}

@test "parse_agent_yaml: outputs all required keys" {
    keys="$(parse_agent_yaml "${FIXTURES}/full.yaml" | cut -d= -f1 | sort)"
    required_keys="deploymentType desiredState dockerCpus dockerImage dockerMemory host label model name owner programArgs program role tags taskDescription workingDirectory"
    for key in $required_keys; do
        echo "$keys" | grep -q "^${key}$"
    done
}

@test "parse_agent_yaml: empty programArgs when not set in minimal YAML" {
    result="$(parse_field "${FIXTURES}/minimal.yaml" "programArgs")"
    [ "$result" = "" ] || [ -z "$result" ]
}

@test "parse_agent_yaml: empty tags when not set in minimal YAML" {
    result="$(parse_field "${FIXTURES}/minimal.yaml" "tags")"
    [ "$result" = "" ] || [ -z "$result" ]
}
