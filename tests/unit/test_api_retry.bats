#!/usr/bin/env bats
# tests/unit/test_api_retry.bats — Unit tests for _agamemnon_curl_with_retry()
#
# Uses a mock curl in tests/mocks/ prepended to PATH to intercept calls.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
MOCKS_DIR="${REPO_ROOT}/tests/mocks"

setup() {
    # Prepend mocks dir so mock curl is found first
    export PATH="${MOCKS_DIR}:${PATH}"
    export AGAMEMNON_URL="http://test.local:8080"

    # shellcheck source=scripts/lib/api.sh
    source "${REPO_ROOT}/scripts/lib/api.sh"

    # Use a temp file to track call counts
    CALL_COUNT_FILE="$(mktemp)"
    export MOCK_CURL_CALL_COUNT_FILE="$CALL_COUNT_FILE"
}

teardown() {
    rm -f "$CALL_COUNT_FILE"
    unset MOCK_CURL_HTTP_CODE MOCK_CURL_BODY MOCK_CURL_EXIT_CODE MOCK_CURL_CALL_COUNT_FILE
}

call_count() {
    cat "$CALL_COUNT_FILE" 2>/dev/null || echo "0"
}

# ── SUCCESS ON FIRST ATTEMPT ──────────────────────────────────────────────────

@test "_agamemnon_curl_with_retry: succeeds on first attempt with HTTP 200" {
    export MOCK_CURL_HTTP_CODE=200
    export MOCK_CURL_BODY='{"ok":true}'

    result="$(_agamemnon_curl_with_retry "${AGAMEMNON_URL}/v1/agents")"
    [ "$result" = '{"ok":true}' ]
    [ "$(call_count)" = "1" ]
}

@test "_agamemnon_curl_with_retry: returns body on HTTP 201" {
    export MOCK_CURL_HTTP_CODE=201
    export MOCK_CURL_BODY='{"id":"new-123"}'

    result="$(_agamemnon_curl_with_retry -X POST "${AGAMEMNON_URL}/v1/agents" \
        -H 'Content-Type: application/json' -d '{}')"
    [ "$result" = '{"id":"new-123"}' ]
}

# ── NON-RETRYABLE ERRORS ─────────────────────────────────────────────────────

@test "_agamemnon_curl_with_retry: fails immediately on HTTP 404 (no retry)" {
    export MOCK_CURL_HTTP_CODE=404
    export MOCK_CURL_BODY='{"error":"not found"}'

    run _agamemnon_curl_with_retry "${AGAMEMNON_URL}/v1/agents/nonexistent"
    [ "$status" -ne 0 ]
    [ "$(call_count)" = "1" ]
}

@test "_agamemnon_curl_with_retry: fails immediately on HTTP 400 (no retry)" {
    export MOCK_CURL_HTTP_CODE=400
    export MOCK_CURL_BODY='{"error":"bad request"}'

    run _agamemnon_curl_with_retry "${AGAMEMNON_URL}/v1/agents"
    [ "$status" -ne 0 ]
    [ "$(call_count)" = "1" ]
}

@test "_agamemnon_curl_with_retry: fails immediately on non-retryable curl exit code" {
    export MOCK_CURL_EXIT_CODE=1
    export MOCK_CURL_HTTP_CODE=000

    run _agamemnon_curl_with_retry "${AGAMEMNON_URL}/v1/agents"
    [ "$status" -ne 0 ]
    [ "$(call_count)" = "1" ]
}

# ── RETRYABLE ERRORS ─────────────────────────────────────────────────────────

@test "_agamemnon_curl_with_retry: retries 3 times on HTTP 503" {
    export MOCK_CURL_HTTP_CODE=503
    export MOCK_CURL_BODY='{"error":"service unavailable"}'

    run _agamemnon_curl_with_retry "${AGAMEMNON_URL}/v1/agents"
    [ "$status" -ne 0 ]
    [ "$(call_count)" = "3" ]
}

@test "_agamemnon_curl_with_retry: retries 3 times on HTTP 500" {
    export MOCK_CURL_HTTP_CODE=500
    export MOCK_CURL_BODY='{"error":"internal server error"}'

    run _agamemnon_curl_with_retry "${AGAMEMNON_URL}/v1/agents"
    [ "$status" -ne 0 ]
    [ "$(call_count)" = "3" ]
}

@test "_agamemnon_curl_with_retry: retries 3 times on curl exit 6 (host not found)" {
    export MOCK_CURL_EXIT_CODE=6
    export MOCK_CURL_HTTP_CODE=000

    run _agamemnon_curl_with_retry "${AGAMEMNON_URL}/v1/agents"
    [ "$status" -ne 0 ]
    [ "$(call_count)" = "3" ]
}

@test "_agamemnon_curl_with_retry: retries 3 times on curl exit 7 (connection refused)" {
    export MOCK_CURL_EXIT_CODE=7
    export MOCK_CURL_HTTP_CODE=000

    run _agamemnon_curl_with_retry "${AGAMEMNON_URL}/v1/agents"
    [ "$status" -ne 0 ]
    [ "$(call_count)" = "3" ]
}

@test "_agamemnon_curl_with_retry: retries 3 times on curl exit 28 (timeout)" {
    export MOCK_CURL_EXIT_CODE=28
    export MOCK_CURL_HTTP_CODE=000

    run _agamemnon_curl_with_retry "${AGAMEMNON_URL}/v1/agents"
    [ "$status" -ne 0 ]
    [ "$(call_count)" = "3" ]
}

# ── INPUT VALIDATION ─────────────────────────────────────────────────────────

@test "_validate_agent_name: accepts valid names" {
    run _validate_agent_name "my-agent"
    [ "$status" = "0" ]

    run _validate_agent_name "agent_123"
    [ "$status" = "0" ]

    run _validate_agent_name "ABC"
    [ "$status" = "0" ]
}

@test "_validate_agent_name: rejects names with slashes" {
    run _validate_agent_name "../../etc/passwd"
    [ "$status" -ne 0 ]
}

@test "_validate_agent_name: rejects names with spaces" {
    run _validate_agent_name "my agent"
    [ "$status" -ne 0 ]
}

@test "_validate_agent_name: rejects names with shell metacharacters" {
    run _validate_agent_name 'agent$(whoami)'
    [ "$status" -ne 0 ]
}

@test "_validate_agent_name: rejects empty string" {
    run _validate_agent_name ""
    [ "$status" -ne 0 ]
}
