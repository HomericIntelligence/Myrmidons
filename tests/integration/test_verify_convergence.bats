#!/usr/bin/env bats
# tests/integration/test_verify_convergence.bats
#
# Integration tests for the verify_convergence call path in apply.sh (#374).
#
# These tests invoke apply.sh end-to-end against a mock Agamemnon server using
# a routes config file.
#
# Routes design for "ok" scenario (convergence-routes-ok.json):
#   - All GET /api/v1/agents → agent exists with status=active, label="OldLabel"
#     (the stale label triggers an UPDATE action in the reconciler)
#   - PATCH /api/v1/agents/* → 200 (update succeeds)
#
# The stale label forces compute_drift to return UPDATE, which populates
# _MODIFIED_NAMES. verify_convergence then re-fetches, sees status=active,
# and reports "[ok] converged" — proving the re-fetch path is exercised.
#
# Routes design for "fail" scenario (convergence-routes-fail.json):
#   - All GET /api/v1/agents → agent exists with status=offline, desired=active
#     (triggers WAKE; re-fetch also returns offline → convergence fails)
#   - PATCH /api/v1/agents/* → 200 (wake succeeds per API, but agent stays offline)
#
# Covers issue #374 (missing integration test for F-03 convergence bug).

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
FIXTURES_DIR="${SCRIPT_DIR}/tests/fixtures"
HELPERS_DIR="${SCRIPT_DIR}/tests/helpers"
APPLY_SH="${SCRIPT_DIR}/scripts/apply.sh"
MOCK_PORT=18086
MOCK_PID_FILE="/tmp/bats-convergence-mock-$$.pid"

# ---------------------------------------------------------------------------
# Mock server helpers
# ---------------------------------------------------------------------------

_start_mock_server_routes() {
    local routes_file="$1"
    python3 "${HELPERS_DIR}/mock_server.py" "$MOCK_PORT" --routes "$routes_file" \
        > /dev/null 2>&1 &
    echo $! > "$MOCK_PID_FILE"
    sleep 0.3
}

_stop_mock_server() {
    if [[ -f "$MOCK_PID_FILE" ]]; then
        kill "$(cat "$MOCK_PID_FILE")" 2>/dev/null || true
        rm -f "$MOCK_PID_FILE"
    fi
}

# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

_CONV_TEST_HOST=""
_CONV_SNAPSHOT_DIR=""

_setup_test_agent() {
    _CONV_TEST_HOST="convtest-$$-${RANDOM}"
    mkdir -p "${SCRIPT_DIR}/agents/${_CONV_TEST_HOST}"
    printf 'apiVersion: myrmidons/v1\nkind: Agent\nmetadata:\n  name: convergence-agent\n  host: %s\nspec:\n  label: Convergence Agent\n  program: claude-code\n  model: null\n  workingDirectory: /tmp/conv\n  programArgs: ""\n  taskDescription: "convergence integration test"\n  tags: []\n  owner: ci\n  role: member\n  deployment:\n    type: local\n  desiredState: active\n' \
        "$_CONV_TEST_HOST" \
        > "${SCRIPT_DIR}/agents/${_CONV_TEST_HOST}/convergence-agent.yaml"
}

_cleanup_test_agent() {
    if [[ -n "${_CONV_TEST_HOST:-}" ]]; then
        rm -rf "${SCRIPT_DIR}/agents/${_CONV_TEST_HOST}"
        _CONV_TEST_HOST=""
    fi
}

setup() {
    export AGAMEMNON_URL="http://127.0.0.1:${MOCK_PORT}"
    export NO_COLOR=1
    _CONV_SNAPSHOT_DIR="$(mktemp -d)"
    _setup_test_agent
}

teardown() {
    _stop_mock_server
    _cleanup_test_agent
    rm -rf "${_CONV_SNAPSHOT_DIR:-}"
    unset NO_COLOR
}

# ---------------------------------------------------------------------------
# Test 1: happy path — agent has drifted label, UPDATE applied, convergence ok
#
# Routes design (convergence-routes-ok.json):
#   All GET /api/v1/agents    → agent active, label="OldLabel" (label drift triggers UPDATE)
#   PATCH /api/v1/agents/*    → 200 active (update applied successfully)
#
# Expected: apply.sh patches the label drift and verify_convergence sees
# status=active after the re-fetch, reporting "[ok] converged".
# ---------------------------------------------------------------------------

@test "verify_convergence: re-fetch confirms active status after UPDATE — reports [ok]" {
    _start_mock_server_routes "${FIXTURES_DIR}/convergence-routes-ok.json"

    run bash "$APPLY_SH" "$_CONV_TEST_HOST" --yes \
        --snapshot-dir "$_CONV_SNAPSHOT_DIR" 2>&1 || true

    [[ "$output" == *"[ok] convergence-agent: converged"* ]]
    [[ "$output" == *"Convergence:"* ]]
}

# ---------------------------------------------------------------------------
# Test 2: verify_convergence calls agamemnon_list_agents (not cached state)
#
# The same routes setup as test 1. If verify_convergence had used the pre-apply
# agents_json cache (as the shadowing bug F-03 effectively did), it would not
# reach the re-fetch code path at all and _MODIFIED_NAMES would be checked
# against stale data. The "[ok]" result proves the canonical verify_convergence
# definition (with the re-fetch) is the one being called.
# ---------------------------------------------------------------------------

@test "verify_convergence: calls agamemnon_list_agents for re-fetch, not cached pre-apply state" {
    _start_mock_server_routes "${FIXTURES_DIR}/convergence-routes-ok.json"

    run bash "$APPLY_SH" "$_CONV_TEST_HOST" --yes \
        --snapshot-dir "$_CONV_SNAPSHOT_DIR" 2>&1 || true

    # Must NOT report NOT converged — that would indicate cached offline state was used
    [[ "$output" != *"NOT converged"* ]]

    # Must report successfully converged — proves the re-fetch returned "active"
    [[ "$output" == *"[ok] convergence-agent: converged"* ]]
}

# ---------------------------------------------------------------------------
# Test 3: non-convergence detected — mock always returns offline
#
# Routes design (convergence-routes-fail.json):
#   All GET /api/v1/agents  → agent offline  (desired=active, triggers WAKE)
#   PATCH /api/v1/agents/*  → 200 offline    (wake API call succeeds but agent stays offline)
#
# Expected: apply.sh issues the WAKE call but the convergence re-fetch still
# sees status=offline. verify_convergence reports "[!] NOT converged".
# ---------------------------------------------------------------------------

@test "verify_convergence: reports NOT converged when re-fetch shows agent still offline" {
    _start_mock_server_routes "${FIXTURES_DIR}/convergence-routes-fail.json"

    run bash "$APPLY_SH" "$_CONV_TEST_HOST" --yes \
        --snapshot-dir "$_CONV_SNAPSHOT_DIR" 2>&1 || true

    [[ "$output" == *"NOT converged"* ]]
}

# ---------------------------------------------------------------------------
# Test 4: prune-convergence path — pruned agent still present in API
#
# Routes design (convergence-routes-prune.json):
#   All GET /api/v1/agents  → two agents: convergence-agent (managed, active)
#                             and unmanaged-prune-agent (unmanaged, active)
#   PATCH /api/v1/agents/*  → 200 offline  (hibernate succeeds)
#   DELETE /api/v1/agents/* → 200          (delete appears to succeed)
#   default_body            → still returns both agents (delete had no effect)
#
# With --prune, apply.sh calls handle_unmanaged for unmanaged-prune-agent,
# which hibernates then deletes it. The mock DELETE returns 200 but the
# subsequent GET still returns the agent. verify_convergence checks
# _PRUNED_NAMES and finds unmanaged-prune-agent still present, reporting
# "pruned but still present in API (convergence failed)".
# ---------------------------------------------------------------------------

@test "verify_convergence: detects pruned agent still present in API — reports convergence failed" {
    _start_mock_server_routes "${FIXTURES_DIR}/convergence-routes-prune.json"

    run bash "$APPLY_SH" "$_CONV_TEST_HOST" --prune --yes \
        --snapshot-dir "$_CONV_SNAPSHOT_DIR" 2>&1 || true

    [[ "$output" == *"pruned but still present in API (convergence failed)"* ]]
}

# ---------------------------------------------------------------------------
# Test 5: WAKE convergence using once route (issue #433)
#
# Routes design (convergence-routes-wake-once.json):
#   First GET /api/v1/agents (once) → agent offline  (triggers WAKE)
#   PATCH /api/v1/agents/*          → 200 active
#   All subsequent GET              → agent active  (default_body)
#
# The once route drives WAKE on the first list. The re-fetch after WAKE
# hits the default_body and sees status=active, so verify_convergence
# reports "[ok] converged" — without any label-drift workaround.
# ---------------------------------------------------------------------------

@test "verify_convergence: WAKE — once route drives offline→active state transition, reports [ok]" {
    _start_mock_server_routes "${FIXTURES_DIR}/convergence-routes-wake-once.json"

    run bash "$APPLY_SH" "$_CONV_TEST_HOST" --yes \
        --snapshot-dir "$_CONV_SNAPSHOT_DIR" 2>&1 || true

    [[ "$output" == *"[ok] convergence-agent: converged"* ]]
    [[ "$output" != *"NOT converged"* ]]
}

# ---------------------------------------------------------------------------
# Test 6: CREATE convergence using once route (issue #433)
#
# Routes design (convergence-routes-create-once.json):
#   First GET /api/v1/agents (once) → []  (agent absent — triggers CREATE)
#   POST /api/v1/agents             → 201 active
#   All subsequent GET              → agent active  (default_body)
#
# The once route makes the first list return empty, forcing a CREATE.
# The re-fetch after CREATE hits the default_body and sees status=active,
# so verify_convergence reports "[ok] converged".
# ---------------------------------------------------------------------------

@test "verify_convergence: CREATE — once route drives absent→active state transition, reports [ok]" {
    _start_mock_server_routes "${FIXTURES_DIR}/convergence-routes-create-once.json"

    run bash "$APPLY_SH" "$_CONV_TEST_HOST" --yes \
        --snapshot-dir "$_CONV_SNAPSHOT_DIR" 2>&1 || true

    [[ "$output" == *"[ok] convergence-agent: converged"* ]]
    [[ "$output" != *"NOT converged"* ]]
}
