#!/usr/bin/env bats
# tests/unit/test_build_create_json.bats — Unit tests for build_create_json()
#
# Tests that the JSON create payload is built correctly from YAML field values.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    # shellcheck source=scripts/lib/reconcile.sh
    source "${REPO_ROOT}/scripts/lib/reconcile.sh"
}

# Helper: build JSON and extract a field with jq
build_field() {
    local field="$1"
    shift
    build_create_json "$@" | jq -r "$field"
}

@test "build_create_json: sets name field" {
    result="$(build_field ".name" "my-agent" "My Agent" "claude-code" \
        "/work" "" "Does stuff" "" "mvillmow" "member")"
    [ "$result" = "my-agent" ]
}

@test "build_create_json: sets label field" {
    result="$(build_field ".label" "my-agent" "My Agent" "claude-code" \
        "/work" "" "Does stuff" "" "mvillmow" "member")"
    [ "$result" = "My Agent" ]
}

@test "build_create_json: sets program field" {
    result="$(build_field ".program" "my-agent" "My Agent" "claude-code" \
        "/work" "" "Does stuff" "" "mvillmow" "member")"
    [ "$result" = "claude-code" ]
}

@test "build_create_json: sets workingDirectory field" {
    result="$(build_field ".workingDirectory" "my-agent" "My Agent" "claude-code" \
        "/home/mvillmow/project" "" "Does stuff" "" "mvillmow" "member")"
    [ "$result" = "/home/mvillmow/project" ]
}

@test "build_create_json: sets programArgs field" {
    result="$(build_field ".programArgs" "my-agent" "My Agent" "claude-code" \
        "/work" "--verbose" "Does stuff" "" "mvillmow" "member")"
    [ "$result" = "--verbose" ]
}

@test "build_create_json: sets taskDescription field" {
    result="$(build_field ".taskDescription" "my-agent" "My Agent" "claude-code" \
        "/work" "" "Does important things" "" "mvillmow" "member")"
    [ "$result" = "Does important things" ]
}

@test "build_create_json: sets owner field" {
    result="$(build_field ".owner" "my-agent" "My Agent" "claude-code" \
        "/work" "" "Does stuff" "" "alice" "member")"
    [ "$result" = "alice" ]
}

@test "build_create_json: sets role field" {
    result="$(build_field ".role" "my-agent" "My Agent" "claude-code" \
        "/work" "" "Does stuff" "" "mvillmow" "admin")"
    [ "$result" = "admin" ]
}

@test "build_create_json: empty tags_csv produces empty JSON array" {
    result="$(build_field ".tags | length" "my-agent" "My Agent" "claude-code" \
        "/work" "" "Does stuff" "" "mvillmow" "member")"
    [ "$result" = "0" ]
}

@test "build_create_json: single tag produces single-element JSON array" {
    result="$(build_field ".tags[0]" "my-agent" "My Agent" "claude-code" \
        "/work" "" "Does stuff" "myproject" "mvillmow" "member")"
    [ "$result" = "myproject" ]
}

@test "build_create_json: comma-separated tags split into JSON array" {
    result="$(build_field ".tags | length" "my-agent" "My Agent" "claude-code" \
        "/work" "" "Does stuff" "tag1,tag2,tag3" "mvillmow" "member")"
    [ "$result" = "3" ]
}

@test "build_create_json: comma-separated tags preserves each tag value" {
    json="$(build_create_json "my-agent" "My Agent" "claude-code" \
        "/work" "" "Does stuff" "alpha,beta" "mvillmow" "member")"
    echo "$json" | jq -e '.tags | contains(["alpha"])'
    echo "$json" | jq -e '.tags | contains(["beta"])'
}

@test "build_create_json: output is valid JSON" {
    result="$(build_create_json "my-agent" "My Agent" "claude-code" \
        "/work" "" "Does stuff" "tag1" "mvillmow" "member")"
    echo "$result" | jq . > /dev/null
}

@test "build_create_json: special characters in taskDescription are escaped" {
    result="$(build_field ".taskDescription" "my-agent" "My Agent" "claude-code" \
        "/work" "" 'Handles "quotes" and backslash\' "" "mvillmow" "member")"
    [[ "$result" == *'quotes'* ]]
}
