#!/usr/bin/env bash
# tests/shell/helpers.bash — Shared BATS helpers for apply.sh tests
#
# Provides mock-path setup, fixture generators, and common assertions.
# Source this file at the top of each BATS test file.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOCKS_DIR="${REPO_ROOT}/tests/shell/mocks"
FIXTURES_DIR="${REPO_ROOT}/tests/shell/fixtures"

# Prepend mock binaries to PATH so apply.sh picks them up instead of real tools.
setup_mocks() {
    export PATH="${MOCKS_DIR}:${PATH}"
    export AGAMEMNON_URL="http://mock-agamemnon:8080"
    export APPLY_VERIFY_TIMEOUT=5
}

# Point AGENT_DIR to a temp directory with fixture YAML files.
setup_fixtures() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    export AGENT_FIXTURES_DIR="$tmpdir"
    echo "$tmpdir"
}

# Write a minimal agent YAML fixture to a given directory.
# Usage: write_agent_fixture <dir> <host> <name> [desired_state]
write_agent_fixture() {
    local dir="$1"
    local host="$2"
    local name="$3"
    local desired_state="${4:-active}"
    local host_dir="${dir}/${host}"
    mkdir -p "$host_dir"
    cat > "${host_dir}/${name}.yaml" <<YAML
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: ${name}
  host: ${host}
spec:
  label: Test Agent ${name}
  program: claude-code
  model: null
  workingDirectory: /tmp/test-${name}
  programArgs: ""
  taskDescription: "Test agent for ${name}"
  tags: [test]
  owner: testuser
  role: member
  deployment:
    type: local
  desiredState: ${desired_state}
YAML
}

# Assert that a string contains a substring.
assert_contains() {
    local haystack="$1"
    local needle="$2"
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "ASSERTION FAILED: expected output to contain: ${needle}" >&2
        echo "Actual output:" >&2
        echo "$haystack" >&2
        return 1
    fi
}
