#!/usr/bin/env bash
# tests/test_lock.sh — Automated tests for scripts/lib/lock.sh
#
# Usage:
#   ./tests/test_lock.sh
#
# Exit codes:
#   0 = all tests passed
#   1 = one or more tests failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/lock.sh
source "${REPO_ROOT}/scripts/lib/lock.sh"

PASS=0
FAIL=0
TMPDIR_TESTS="$(mktemp -d)"

cleanup() {
    rm -rf "$TMPDIR_TESTS"
}
trap cleanup EXIT

# -----------------------------------------------------------------------------
# Test harness helpers
# -----------------------------------------------------------------------------

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_true() {
    local desc="$1"
    local result="$2"
    if [[ "$result" -eq 0 ]]; then
        pass "$desc"
    else
        fail "$desc (expected success, got exit $result)"
    fi
}

assert_false() {
    local desc="$1"
    local result="$2"
    if [[ "$result" -ne 0 ]]; then
        pass "$desc"
    else
        fail "$desc (expected failure, got exit 0)"
    fi
}

assert_file_exists() {
    local desc="$1"
    local file="$2"
    if [[ -f "$file" ]]; then
        pass "$desc"
    else
        fail "$desc (file does not exist: $file)"
    fi
}

assert_file_absent() {
    local desc="$1"
    local file="$2"
    if [[ ! -f "$file" ]]; then
        pass "$desc"
    else
        fail "$desc (file should not exist: $file)"
    fi
}

assert_equals() {
    local desc="$1"
    local expected="$2"
    local actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$desc"
    else
        fail "$desc (expected='${expected}', actual='${actual}')"
    fi
}

# -----------------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------------

echo "Running lock tests..."
echo ""

# --- Test 1: acquire_lock creates the lockfile ---
echo "Test 1: acquire_lock creates lockfile"
{
    lockfile="${TMPDIR_TESTS}/test1.lock"
    acquire_lock "$lockfile" 0
    assert_file_exists "lockfile exists after acquire" "$lockfile"
    release_lock "$lockfile"
    assert_file_absent "lockfile removed after release" "$lockfile"
}

# --- Test 2: lockfile contains our PID ---
echo "Test 2: lockfile contains current PID"
{
    lockfile="${TMPDIR_TESTS}/test2.lock"
    acquire_lock "$lockfile" 0
    pid_in_file="$(cat "$lockfile")"
    assert_equals "lockfile contains current PID" "$$" "$pid_in_file"
    release_lock "$lockfile"
}

# --- Test 3: release_lock is idempotent (no error on missing file) ---
echo "Test 3: release_lock is idempotent"
{
    lockfile="${TMPDIR_TESTS}/test3.lock"
    # release without acquire — should not error
    result=0
    release_lock "$lockfile" || result=$?
    assert_true "release_lock on missing file does not error" "$result"
}

# --- Test 4: break_stale_lock on dead PID removes lockfile ---
echo "Test 4: break_stale_lock removes stale lock (dead PID)"
{
    lockfile="${TMPDIR_TESTS}/test4.lock"
    # Write a PID that cannot possibly be alive (PID 1 would be init; use a
    # very high PID that doesn't exist instead)
    dead_pid=99999999
    echo "$dead_pid" > "$lockfile"
    result=0
    break_stale_lock "$lockfile" 2>/dev/null || result=$?
    assert_true "break_stale_lock returns 0 for dead PID" "$result"
    assert_file_absent "lockfile removed for dead PID" "$lockfile"
}

# --- Test 5: break_stale_lock on live PID exits with error ---
echo "Test 5: break_stale_lock fails on live PID"
{
    lockfile="${TMPDIR_TESTS}/test5.lock"
    # Write our own PID — we are definitely alive
    echo "$$" > "$lockfile"
    result=0
    # Run in subshell so exit doesn't kill our test script
    (break_stale_lock "$lockfile" 2>/dev/null) || result=$?
    assert_false "break_stale_lock exits non-zero for live PID" "$result"
    # Cleanup
    rm -f "$lockfile"
}

# --- Test 6: break_stale_lock on empty/invalid PID treats as stale ---
echo "Test 6: break_stale_lock treats invalid PID as stale"
{
    lockfile="${TMPDIR_TESTS}/test6.lock"
    echo "not-a-pid" > "$lockfile"
    result=0
    break_stale_lock "$lockfile" 2>/dev/null || result=$?
    assert_true "break_stale_lock returns 0 for invalid PID" "$result"
    assert_file_absent "lockfile removed for invalid PID" "$lockfile"
}

# --- Test 7: break_stale_lock on missing file is a no-op ---
echo "Test 7: break_stale_lock no-op on missing lockfile"
{
    lockfile="${TMPDIR_TESTS}/test7.lock"
    result=0
    break_stale_lock "$lockfile" 2>/dev/null || result=$?
    assert_true "break_stale_lock returns 0 when no lockfile" "$result"
}

# --- Test 8: --force flag triggers stale lock removal (via acquire_lock) ---
echo "Test 8: acquire_lock with force=1 removes stale lock"
{
    lockfile="${TMPDIR_TESTS}/test8.lock"
    dead_pid=99999999
    echo "$dead_pid" > "$lockfile"
    result=0
    acquire_lock "$lockfile" 1 2>/dev/null || result=$?
    assert_true "acquire_lock with force=1 succeeds after stale removal" "$result"
    assert_file_exists "lockfile re-created by acquire after force" "$lockfile"
    release_lock "$lockfile"
}

# --- Test 9: Second acquire_lock in background blocks and proceeds after release ---
echo "Test 9: second acquire blocks until first releases"
{
    lockfile="${TMPDIR_TESTS}/test9.lock"
    result_file="${TMPDIR_TESTS}/test9_result"

    acquire_lock "$lockfile" 0

    # Launch background process that tries to acquire same lock
    (
        acquire_lock "$lockfile" 0
        echo "acquired" > "$result_file"
        release_lock "$lockfile"
    ) &
    bg_pid=$!

    # Give the background process a moment to block on flock
    sleep 0.2

    # It should not have acquired yet (we still hold it)
    if [[ -f "$result_file" ]]; then
        fail "background process should not have acquired lock while held"
    else
        pass "background process blocks while lock is held"
    fi

    # Release our lock — background should proceed
    release_lock "$lockfile"

    # Wait for background to complete
    wait "$bg_pid" 2>/dev/null || true
    sleep 0.1

    if [[ -f "$result_file" && "$(cat "$result_file")" == "acquired" ]]; then
        pass "background process acquired lock after release"
    else
        fail "background process did not acquire lock after release"
    fi
}

# --- Test 10: release_lock removes file after trap simulation ---
echo "Test 10: release_lock cleans up on simulated EXIT trap"
{
    lockfile="${TMPDIR_TESTS}/test10.lock"
    result_file="${TMPDIR_TESTS}/test10_result"

    (
        acquire_lock "$lockfile" 0
        trap "release_lock \"$lockfile\"; echo 'released' > \"$result_file\"" EXIT
        # Simulate crash via exit 1
        exit 1
    ) 2>/dev/null || true

    sleep 0.1
    assert_file_absent "lockfile removed by EXIT trap on crash" "$lockfile"
    if [[ -f "$result_file" && "$(cat "$result_file")" == "released" ]]; then
        pass "EXIT trap release_lock ran on crash exit"
    else
        fail "EXIT trap release_lock did not run on crash exit"
    fi
}

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo "================================"
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
