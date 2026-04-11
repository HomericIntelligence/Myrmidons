#!/usr/bin/env bats
# tests/shell/test_convergence.bats
#
# Tests for --verify flag and post-apply convergence behaviour.

load helpers.bash

REPO_ROOT_REAL="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
APPLY="${REPO_ROOT_REAL}/scripts/apply.sh"

setup() {
    setup_mocks
    AGENT_DIR="$(setup_fixtures)"
    export MOCK_AGENT_STATE_FILE
    MOCK_AGENT_STATE_FILE="$(mktemp)"
    echo "[]" > "$MOCK_AGENT_STATE_FILE"

    write_agent_fixture "$AGENT_DIR" "hermes" "verify-agent" "active"
    export AGENTS_ROOT="$AGENT_DIR"
    export APPLY_VERIFY_TIMEOUT=2
}

teardown() {
    rm -f "${MOCK_AGENT_STATE_FILE:-}"
    rm -rf "${AGENT_DIR:-}"
}

@test "--verify exits 0 when all agents converge" {
    # Pre-populate state: agent already exists online
    cat > "$MOCK_AGENT_STATE_FILE" <<'JSON'
[{"id":"a1","name":"verify-agent","label":"Test Agent verify-agent",
  "program":"claude-code","workingDirectory":"/tmp/test-verify-agent",
  "programArgs":"","taskDescription":"Test agent for verify-agent",
  "tags":["test"],"owner":"testuser","role":"member","status":"online"}]
JSON

    run bash "$APPLY" hermes --verify
    [ "$status" -eq 0 ]
    assert_contains "$output" "converged"
}

@test "--verify exits non-zero when an agent has a drifted field after apply" {
    # Agent exists but with wrong label — mock curl will update it in-place,
    # but we make the label drift persist by writing a stale-state fixture.
    # To simulate drift remaining: write desired YAML with a label that
    # doesn't match the API, and pre-set the state file to have the "wrong"
    # label AND disable the PATCH operation by making the state file read-only
    # for the duration of the apply (it will try to update and succeed in the
    # mock, so we need a different approach).
    #
    # Simplest approach: make the agent missing after apply by clearing the
    # state file right after the create so verify sees MISSING.
    # We do this by setting MOCK_AGENT_STATE_FILE to a new file that starts
    # empty, so create succeeds but the verify re-fetch returns empty.
    # Actually the mock persists state in the file, so create will be there.
    #
    # Best approach: use desired=hibernated but mock always returns online.
    write_agent_fixture "$AGENT_DIR" "hermes" "drifted-agent" "hibernated"

    # Put agent in Agamemnon as "online" (desired=hibernated → hibernate action)
    # The mock's hibernate call WILL update status to offline. So after apply the
    # agent WILL converge. We need convergence to FAIL.
    #
    # Override mock curl so the /stop call silently no-ops (returns 200 but
    # doesn't update state), simulating a silent API failure.
    cat > "${MOCKS_DIR}/curl" <<'MOCKEOF'
#!/usr/bin/env bash
STATE_FILE="${MOCK_AGENT_STATE_FILE:-/tmp/mock_agent_state.json}"
method="GET"; url=""; output_file=""; write_out=""; body=""
i=1
while [[ $i -le $# ]]; do
    arg="${!i}"
    case "$arg" in
        -X) i=$((i+1)); method="${!i}" ;;
        -o) i=$((i+1)); output_file="${!i}" ;;
        -w) i=$((i+1)); write_out="${!i}" ;;
        -d) i=$((i+1)); body="${!i}" ;;
        -H|--max-time) i=$((i+1)) ;;
        -s|-f|-sf|-fs) ;;
        http://*) url="$arg" ;;
    esac
    i=$((i+1))
done
[[ ! -f "$STATE_FILE" ]] && echo "[]" > "$STATE_FILE"
respond() {
    local code="$1" body_out="$2"
    [[ -n "$output_file" ]] && printf '%s' "$body_out" > "$output_file" || printf '%s' "$body_out"
    [[ "$write_out" == "%{http_code}" ]] && printf '%s' "$code"
    return 0
}
path="${url#http://mock-agamemnon:8080}"
case "${method} ${path}" in
    "GET /v1/health") respond "200" '{"status":"ok"}' ;;
    "GET /v1/agents") respond "200" "$(cat "$STATE_FILE")" ;;
    "POST /v1/agents")
        id="agent-$(date +%s%3N)"
        new_agent="$(echo "$body" | jq --arg id "$id" --arg s "offline" '. + {id:$id,status:$s}')"
        jq --argjson a "$new_agent" '. + [$a]' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        respond "201" "$new_agent" ;;
    "POST /v1/agents/"*/start)
        aid="${path#/v1/agents/}"; aid="${aid%/start}"
        jq --arg id "$aid" 'map(if .id==$id then .status="online" else . end)' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        respond "200" '{"status":"ok"}' ;;
    "POST /v1/agents/"*/stop)
        # Silent no-op: return 200 but do NOT update state (simulate silent wake failure)
        respond "200" '{"status":"ok"}' ;;
    "PATCH /v1/agents/"*)
        aid="${path#/v1/agents/}"
        jq --arg id "$aid" --argjson p "$body" 'map(if .id==$id then . + $p else . end)' "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
        agent="$(jq -r --arg id "$aid" '.[] | select(.id==$id)' "$STATE_FILE")"
        respond "200" "$agent" ;;
    *) respond "404" '{"error":"not found"}' ;;
esac
exit 0
MOCKEOF
    chmod +x "${MOCKS_DIR}/curl"

    cat > "$MOCK_AGENT_STATE_FILE" <<'JSON'
[{"id":"a2","name":"drifted-agent","label":"Test Agent drifted-agent",
  "program":"claude-code","workingDirectory":"/tmp/test-drifted-agent",
  "programArgs":"","taskDescription":"Test agent for drifted-agent",
  "tags":["test"],"owner":"testuser","role":"member","status":"online"}]
JSON

    run bash "$APPLY" hermes --verify
    [ "$status" -ne 0 ]
    assert_contains "$output" "drifted"
}

@test "post-apply status is printed without --verify" {
    cat > "$MOCK_AGENT_STATE_FILE" <<'JSON'
[{"id":"a1","name":"verify-agent","label":"Test Agent verify-agent",
  "program":"claude-code","workingDirectory":"/tmp/test-verify-agent",
  "programArgs":"","taskDescription":"Test agent for verify-agent",
  "tags":["test"],"owner":"testuser","role":"member","status":"online"}]
JSON

    run bash "$APPLY" hermes
    [ "$status" -eq 0 ]
    assert_contains "$output" "Post-apply convergence check"
    assert_contains "$output" "Convergence:"
}

@test "api_calls is tracked and non-zero" {
    run bash "$APPLY" hermes
    [ "$status" -eq 0 ]
    calls="$(echo "$output" | grep -oP 'api_calls=\K[0-9]+')"
    [ "$calls" -gt 0 ]
}
