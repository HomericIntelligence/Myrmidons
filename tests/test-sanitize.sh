#!/usr/bin/env bash
# tests/test-sanitize.sh — Unit and integration tests for scripts/lib/sanitize.sh
#
# Tests:
#   1. json_escape correctly round-trips special characters
#   2. validate_field accepts clean values
#   3. validate_field rejects null bytes
#   4. validate_field rejects C0 control characters
#   5. validate_field permits tab, LF, CR
#   6. Integration: agent with quotes/backslashes/newlines in taskDescription
#      produces valid JSON via build_create_json (roundtrip)
#
# Usage:
#   ./tests/test-sanitize.sh
# Exit codes:
#   0 = all tests passed
#   1 = one or more tests failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${REPO_ROOT}/scripts/lib/sanitize.sh"
source "${REPO_ROOT}/scripts/lib/reconcile.sh"

PASS=0
FAIL=0

run_test() {
    local name="$1"
    local result="$2"    # "pass" or "fail"
    if [[ "$result" == "pass" ]]; then
        echo "  PASS: ${name}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${name}"
        FAIL=$((FAIL + 1))
    fi
}

assert_eq() {
    local name="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        run_test "$name" "pass"
    else
        run_test "$name" "fail"
        echo "       expected: $(printf '%s' "$expected" | cat -v)"
        echo "       actual:   $(printf '%s' "$actual" | cat -v)"
    fi
}

assert_exit0() {
    local name="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        run_test "$name" "pass"
    else
        run_test "$name" "fail"
    fi
}

assert_exit1() {
    local name="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        run_test "$name" "fail"
    else
        run_test "$name" "pass"
    fi
}

echo "=== sanitize.sh tests ==="
echo ""

# ── json_escape ────────────────────────────────────────────────────────────────
echo "-- json_escape --"

assert_eq "simple string" '"hello"' "$(json_escape "hello")"

assert_eq "double quotes escaped" '"He said \"hello\""' \
    "$(json_escape 'He said "hello"')"

assert_eq "backslash escaped" '"foo\\\\bar"' \
    "$(json_escape 'foo\\bar')"

assert_eq "newline escaped" "$(printf '"line1\\nline2"')" \
    "$(json_escape $'line1\nline2')"

assert_eq "tab escaped" "$(printf '"col1\\tcol2"')" \
    "$(json_escape $'col1\tcol2')"

assert_eq "unicode passthrough" '"caf\u00e9"' \
    "$(json_escape "$(printf 'caf\xc3\xa9')")"

assert_eq "empty string" '""' "$(json_escape "")"

# ── validate_field ─────────────────────────────────────────────────────────────
echo ""
echo "-- validate_field --"

assert_exit0 "clean ascii"       validate_field "f" "hello world"
assert_exit0 "with double quote" validate_field "f" 'He said "hello"'
assert_exit0 "with backslash"    validate_field "f" 'foo\bar'
assert_exit0 "with newline"      validate_field "f" $'line1\nline2'
assert_exit0 "with tab"          validate_field "f" $'col1\tcol2'
assert_exit0 "with CR"           validate_field "f" $'foo\rbar'
assert_exit0 "empty value"       validate_field "f" ""

# Control characters that must be rejected
assert_exit1 "SOH (0x01)"  validate_field "f" $'\x01'
assert_exit1 "BEL (0x07)"  validate_field "f" $'\x07'
assert_exit1 "BS  (0x08)"  validate_field "f" $'\x08'
assert_exit1 "VT  (0x0B)"  validate_field "f" $'\x0b'
assert_exit1 "FF  (0x0C)"  validate_field "f" $'\x0c'
assert_exit1 "SO  (0x0E)"  validate_field "f" $'\x0e'
assert_exit1 "DEL (0x7F)"  validate_field "f" $'\x7f'
assert_exit1 "ESC (0x1B)"  validate_field "f" $'\x1b'

# ── Integration: roundtrip via build_create_json ───────────────────────────────
echo ""
echo "-- Integration: special characters through build_create_json --"

# Agent with the exact value from the success criteria in issue #53
TRICKY_DESC='He said "hello" and
 left'
TRICKY_ARGS='--flag="with spaces" --another='\''single'\'''

json_out="$(build_create_json \
    "test-agent" \
    "Test Agent" \
    "claude-code" \
    "/home/mvillmow/projects/test" \
    "$TRICKY_ARGS" \
    "$TRICKY_DESC" \
    "ci,test" \
    "mvillmow" \
    "member")"

# Verify the output is valid JSON
assert_exit0 "output is valid JSON" bash -c "echo \"\$json_out\" | jq . > /dev/null"

# Verify taskDescription roundtrips correctly
roundtripped_desc="$(echo "$json_out" | jq -r '.taskDescription')"
assert_eq "taskDescription roundtrip" "$TRICKY_DESC" "$roundtripped_desc"

# Verify programArgs roundtrips correctly
roundtripped_args="$(echo "$json_out" | jq -r '.programArgs')"
assert_eq "programArgs roundtrip" "$TRICKY_ARGS" "$roundtripped_args"

# Verify backslashes roundtrip
BACKSLASH_DESC='path is C:\Users\test and "quoted"'
json_bs="$(build_create_json "a" "A" "claude-code" "/tmp" "" "$BACKSLASH_DESC" "" "u" "member")"
assert_exit0 "backslash desc is valid JSON"   bash -c "echo \"\$json_bs\" | jq . > /dev/null"
roundtripped_bs="$(echo "$json_bs" | jq -r '.taskDescription')"
assert_eq "backslash roundtrip" "$BACKSLASH_DESC" "$roundtripped_bs"

# ── Integration: validate_agent_fields rejects bad input ──────────────────────
echo ""
echo "-- Integration: validate_agent_fields --"

assert_exit0 "clean fields accepted" \
    validate_agent_fields "myagent" "My Agent" "claude-code" \
        "/home/mvillmow/proj" "" "He said \"hello\"" "ci" "mvillmow" "member"

assert_exit1 "ESC in desc rejected" \
    validate_agent_fields "myagent" "My Agent" "claude-code" \
        "/home/mvillmow/proj" "" $'bad\x1bvalue' "" "mvillmow" "member"

assert_exit1 "BEL in name rejected" \
    validate_agent_fields $'bad\x07name' "My Agent" "claude-code" \
        "/home/mvillmow/proj" "" "" "" "mvillmow" "member"

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo "================================================"
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
