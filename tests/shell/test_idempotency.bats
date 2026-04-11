#!/usr/bin/env bats
# tests/shell/test_idempotency.bats
#
# Idempotency tests: running apply.sh twice in a row must produce zero
# changes on the second run.
#
# Uses PATH-injected mock stubs (tests/shell/mocks/) and AGENTS_ROOT to
# point apply.sh at fixture YAML trees without touching the real agents/ dir.

load helpers.bash

REPO_ROOT_REAL="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
APPLY="${REPO_ROOT_REAL}/scripts/apply.sh"

setup() {
    setup_mocks
    AGENT_DIR="$(setup_fixtures)"
    export MOCK_AGENT_STATE_FILE
    MOCK_AGENT_STATE_FILE="$(mktemp)"
    echo "[]" > "$MOCK_AGENT_STATE_FILE"

    write_agent_fixture "$AGENT_DIR" "hermes" "test-agent-alpha" "active"

    # Point apply.sh at our fixture tree instead of the real agents/ dir
    export AGENTS_ROOT="$AGENT_DIR"
}

teardown() {
    rm -f "${MOCK_AGENT_STATE_FILE:-}"
    rm -rf "${AGENT_DIR:-}"
}

@test "first apply creates and starts the agent" {
    run bash "$APPLY" hermes
    [ "$status" -eq 0 ]
    assert_contains "$output" "created=1"
    assert_contains "$output" "woken=1"
    assert_contains "$output" "errors=0"
}

@test "second apply after convergence reports all unchanged" {
    # Prime state: agent already exists and is online
    cat > "$MOCK_AGENT_STATE_FILE" <<'JSON'
[{"id":"agent-001","name":"test-agent-alpha","label":"Test Agent test-agent-alpha",
  "program":"claude-code","workingDirectory":"/tmp/test-test-agent-alpha",
  "programArgs":"","taskDescription":"Test agent for test-agent-alpha",
  "tags":["test"],"owner":"testuser","role":"member","status":"online"}]
JSON

    run bash "$APPLY" hermes
    [ "$status" -eq 0 ]
    assert_contains "$output" "created=0"
    assert_contains "$output" "updated=0"
    assert_contains "$output" "woken=0"
    assert_contains "$output" "errors=0"
}

@test "apply twice: second run has zero creates, updates, and errors" {
    # First run — agent doesn't exist yet
    run bash "$APPLY" hermes
    [ "$status" -eq 0 ]
    assert_contains "$output" "created=1"

    # Second run — agent now exists and is online (mock persists state)
    run bash "$APPLY" hermes
    [ "$status" -eq 0 ]
    assert_contains "$output" "created=0"
    assert_contains "$output" "updated=0"
    assert_contains "$output" "errors=0"
}

@test "api_calls counter appears in summary" {
    run bash "$APPLY" hermes
    [ "$status" -eq 0 ]
    assert_contains "$output" "api_calls="
}

@test "post-apply convergence check is printed" {
    run bash "$APPLY" hermes
    [ "$status" -eq 0 ]
    assert_contains "$output" "Post-apply convergence check"
}
