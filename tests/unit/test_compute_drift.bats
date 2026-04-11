#!/usr/bin/env bats
# tests/unit/test_compute_drift.bats — Unit tests for compute_drift()
#
# Tests all drift states: UNCHANGED, CREATE (caller logic), WAKE, HIBERNATE, UPDATE.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
FIXTURES="${REPO_ROOT}/tests/fixtures"

setup() {
    # shellcheck source=scripts/lib/reconcile.sh
    source "${REPO_ROOT}/scripts/lib/reconcile.sh"

    ACTIVE_JSON="$(cat "${FIXTURES}/agent_active.json")"
    HIBERNATED_JSON="$(cat "${FIXTURES}/agent_hibernated.json")"
}

# Helper: call compute_drift with standard test args
# Usage: run_drift <desired_state> <actual_json> [label] [program] [workdir] [args] [desc] [tags]
run_drift() {
    local desired="$1"
    local json="$2"
    local label="${3:-Test Agent}"
    local program="${4:-claude-code}"
    local workdir="${5:-/home/mvillmow/test}"
    local args="${6:-}"
    local desc="${7:-A test agent}"
    local tags="${8:-test,unit}"

    compute_drift "test-agent" "$desired" "$json" \
        "$label" "$program" "$workdir" "$args" "$desc" "$tags"
}

# ── UNCHANGED ─────────────────────────────────────────────────────────────────

@test "compute_drift: UNCHANGED when all fields match (active agent)" {
    result="$(run_drift "active" "$ACTIVE_JSON")"
    [ "$result" = "UNCHANGED" ]
}

@test "compute_drift: UNCHANGED when agent is hibernated and desired is hibernated" {
    # Call compute_drift directly to avoid default-arg issue with empty tags
    result="$(compute_drift "sleeping-agent" "hibernated" "$HIBERNATED_JSON" \
        "Sleeping Agent" "aider" "/home/mvillmow/sleep" "" "A hibernated agent" "")"
    [ "$result" = "UNCHANGED" ]
}

# ── WAKE ──────────────────────────────────────────────────────────────────────

@test "compute_drift: WAKE when desired=active and actual=offline" {
    result="$(compute_drift "sleeping-agent" "active" "$HIBERNATED_JSON" \
        "Sleeping Agent" "aider" "/home/mvillmow/sleep" "" "A hibernated agent" "")"
    [ "$result" = "WAKE" ]
}

@test "compute_drift: not WAKE when desired=active and actual=active" {
    result="$(run_drift "active" "$ACTIVE_JSON")"
    [ "$result" != "WAKE" ]
}

# ── HIBERNATE ─────────────────────────────────────────────────────────────────

@test "compute_drift: HIBERNATE when desired=hibernated and actual=active" {
    result="$(run_drift "hibernated" "$ACTIVE_JSON")"
    [ "$result" = "HIBERNATE" ]
}

@test "compute_drift: HIBERNATE when desired=hibernated and actual=online" {
    online_json='{"id":"x","name":"a","label":"Test Agent","program":"claude-code","workingDirectory":"/home/mvillmow/test","programArgs":"","taskDescription":"A test agent","tags":["test","unit"],"status":"online"}'
    result="$(run_drift "hibernated" "$online_json")"
    [ "$result" = "HIBERNATE" ]
}

@test "compute_drift: not HIBERNATE when desired=hibernated and actual=offline" {
    result="$(compute_drift "sleeping-agent" "hibernated" "$HIBERNATED_JSON" \
        "Sleeping Agent" "aider" "/home/mvillmow/sleep" "" "A hibernated agent" "")"
    [ "$result" != "HIBERNATE" ]
}

# ── UPDATE ────────────────────────────────────────────────────────────────────

@test "compute_drift: UPDATE when label differs" {
    result="$(run_drift "active" "$ACTIVE_JSON" "Different Label")"
    [[ "$result" == UPDATE:* ]]
    [[ "$result" == *"label"* ]]
}

@test "compute_drift: UPDATE when program differs" {
    result="$(run_drift "active" "$ACTIVE_JSON" "Test Agent" "aider")"
    [[ "$result" == UPDATE:* ]]
    [[ "$result" == *"program"* ]]
}

@test "compute_drift: UPDATE when workingDirectory differs" {
    result="$(run_drift "active" "$ACTIVE_JSON" "Test Agent" "claude-code" "/different/path")"
    [[ "$result" == UPDATE:* ]]
    [[ "$result" == *"workingDirectory"* ]]
}

@test "compute_drift: UPDATE when programArgs differs" {
    result="$(run_drift "active" "$ACTIVE_JSON" "Test Agent" "claude-code" \
        "/home/mvillmow/test" "--new-flag")"
    [[ "$result" == UPDATE:* ]]
    [[ "$result" == *"programArgs"* ]]
}

@test "compute_drift: UPDATE when taskDescription differs" {
    result="$(run_drift "active" "$ACTIVE_JSON" "Test Agent" "claude-code" \
        "/home/mvillmow/test" "" "Different description")"
    [[ "$result" == UPDATE:* ]]
    [[ "$result" == *"taskDescription"* ]]
}

@test "compute_drift: UPDATE when tags differ" {
    result="$(run_drift "active" "$ACTIVE_JSON" "Test Agent" "claude-code" \
        "/home/mvillmow/test" "" "A test agent" "other,tags")"
    [[ "$result" == UPDATE:* ]]
    [[ "$result" == *"tags"* ]]
}

@test "compute_drift: UPDATE lists multiple drifted fields" {
    result="$(run_drift "active" "$ACTIVE_JSON" "Different Label" "aider")"
    [[ "$result" == UPDATE:* ]]
    [[ "$result" == *"label"* ]]
    [[ "$result" == *"program"* ]]
}

# ── PATH NORMALIZATION ────────────────────────────────────────────────────────

@test "compute_drift: UNCHANGED when tilde path matches expanded path" {
    tilde_json='{"id":"x","name":"a","label":"Test Agent","program":"claude-code","workingDirectory":"'"${HOME}/test"'","programArgs":"","taskDescription":"A test agent","tags":["test","unit"],"status":"active"}'
    result="$(compute_drift "test-agent" "active" "$tilde_json" \
        "Test Agent" "claude-code" "~/test" "" "A test agent" "test,unit")"
    [ "$result" = "UNCHANGED" ]
}

# ── TAG SORT STABILITY ────────────────────────────────────────────────────────

@test "compute_drift: UNCHANGED when tags same but different order in YAML" {
    result="$(compute_drift "test-agent" "active" "$ACTIVE_JSON" \
        "Test Agent" "claude-code" "/home/mvillmow/test" "" "A test agent" "unit,test")"
    [ "$result" = "UNCHANGED" ]
}
