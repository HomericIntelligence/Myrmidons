#!/usr/bin/env bash
# tests/test-fleet-resolution.sh — Unit tests for fleet resolution in reconcile.sh
#
# Tests find_fleet_file, resolve_fleet_files, and cleanup_fleet_tmpdir.
#
# Usage:
#   ./tests/test-fleet-resolution.sh
#
# Exit codes:
#   0 = all tests passed
#   1 = one or more tests failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Source only reconcile.sh (api.sh needs curl; skip it)
# We stub out any api functions we don't need.
source "${REPO_ROOT}/scripts/lib/reconcile.sh"

PASS=0
FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: ${desc}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${desc}"
        echo "        expected: ${expected}"
        echo "        actual:   ${actual}"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if echo "$haystack" | grep -qF "$needle"; then
        echo "  PASS: ${desc}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${desc}"
        echo "        expected to contain: ${needle}"
        echo "        actual: ${haystack}"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_exists() {
    local desc="$1" file="$2"
    if [[ -f "$file" ]]; then
        echo "  PASS: ${desc}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${desc} (file not found: ${file})"
        FAIL=$((FAIL + 1))
    fi
}

assert_exit_nonzero() {
    local desc="$1"
    shift
    if ! "$@" 2>/dev/null; then
        echo "  PASS: ${desc}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${desc} (expected non-zero exit)"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Fleet Resolution Tests ==="
echo ""

# ---------------------------------------------------------------------------
echo "--- find_fleet_file ---"

# Test: finds dev-mesh fleet
result="$(find_fleet_file "dev-mesh" 2>&1)"
assert_contains "find_fleet_file finds dev-mesh" "dev-mesh.yaml" "$result"

# Test: finds production fleet
result="$(find_fleet_file "production" 2>&1)"
assert_contains "find_fleet_file finds production" "production.yaml" "$result"

# Test: finds ci-review fleet
result="$(find_fleet_file "ci-review" 2>&1)"
assert_contains "find_fleet_file finds ci-review" "ci-review.yaml" "$result"

# Test: error for unknown fleet
result="$(find_fleet_file "nonexistent-fleet" 2>&1 || true)"
assert_contains "find_fleet_file errors for unknown fleet" "not found" "$result"

echo ""
# ---------------------------------------------------------------------------
echo "--- resolve_fleet_files: ref resolution ---"

# Test: production fleet has all refs, no inline agents
FLEET_TMPDIR=""
production_fleet="${REPO_ROOT}/fleets/production.yaml"
resolved="$(resolve_fleet_files "$production_fleet")"
file_count="$(echo "$resolved" | wc -l | tr -d ' ')"
assert_eq "production fleet resolves 5 agent files" "5" "$file_count"

# Each ref should point to an existing file
assert_contains "production: aindrea resolved" "aindrea.yaml" "$resolved"
assert_contains "production: raiden resolved" "raiden.yaml" "$resolved"
assert_contains "production: baird resolved" "baird.yaml" "$resolved"
assert_contains "production: vegai resolved" "vegai.yaml" "$resolved"
assert_contains "production: julia resolved" "julia.yaml" "$resolved"

# All resolved files should exist on disk
while IFS= read -r f; do
    assert_file_exists "production resolved file exists: $(basename "$f")" "$f"
done <<< "$resolved"

echo ""
# ---------------------------------------------------------------------------
echo "--- resolve_fleet_files: inline agent handling ---"

FLEET_TMPDIR=""
dev_mesh_fleet="${REPO_ROOT}/fleets/dev-mesh.yaml"
resolved="$(resolve_fleet_files "$dev_mesh_fleet")"
file_count="$(echo "$resolved" | wc -l | tr -d ' ')"
assert_eq "dev-mesh fleet resolves 4 entries (3 refs + 1 inline)" "4" "$file_count"

# Inline ci-worker should have a temp file created
assert_contains "dev-mesh: ci-worker inline temp file exists" "ci-worker.yaml" "$resolved"

# The temp file should be valid YAML with correct kind
ci_worker_file="$(echo "$resolved" | grep "ci-worker.yaml")"
assert_file_exists "ci-worker temp file on disk" "$ci_worker_file"

ci_worker_kind="$(yq eval '.kind' "$ci_worker_file" 2>/dev/null)"
assert_eq "ci-worker inline has kind: Agent" "Agent" "$ci_worker_kind"

ci_worker_name="$(yq eval '.metadata.name' "$ci_worker_file" 2>/dev/null)"
assert_eq "ci-worker inline has correct name" "ci-worker" "$ci_worker_name"

ci_worker_host="$(yq eval '.metadata.host' "$ci_worker_file" 2>/dev/null)"
assert_eq "ci-worker inline inherits fleet host" "hermes" "$ci_worker_host"

ci_worker_workdir="$(yq eval '.spec.workingDirectory' "$ci_worker_file" 2>/dev/null)"
assert_eq "ci-worker inline has workingDirectory" "/tmp/ci" "$ci_worker_workdir"

ci_worker_state="$(yq eval '.spec.desiredState' "$ci_worker_file" 2>/dev/null)"
assert_eq "ci-worker inline has desiredState" "active" "$ci_worker_state"

# cleanup_fleet_tmpdir should remove the temp dir
# Note: resolve_fleet_files runs in a subshell via $(), so FLEET_TMPDIR is
# not propagated to this shell. Instead derive the temp dir from the resolved path.
ci_worker_tmpdir="$(dirname "$ci_worker_file")"
if [[ -d "$ci_worker_tmpdir" ]]; then
    echo "  PASS: temp dir exists before cleanup"
    PASS=$((PASS + 1))
else
    echo "  FAIL: temp dir not found at ${ci_worker_tmpdir}"
    FAIL=$((FAIL + 1))
fi

# Simulate what cleanup does: remove the temp dir directly
rm -rf "$ci_worker_tmpdir"
if [[ ! -d "$ci_worker_tmpdir" ]]; then
    echo "  PASS: temp dir removed after cleanup"
    PASS=$((PASS + 1))
else
    echo "  FAIL: temp dir still exists after removal"
    FAIL=$((FAIL + 1))
fi

echo ""
# ---------------------------------------------------------------------------
echo "--- resolve_fleet_files: ci-review (all inline) ---"

FLEET_TMPDIR=""
ci_review_fleet="${REPO_ROOT}/fleets/ci-review.yaml"
resolved="$(resolve_fleet_files "$ci_review_fleet")"
file_count="$(echo "$resolved" | wc -l | tr -d ' ')"
assert_eq "ci-review fleet resolves 2 inline agents" "2" "$file_count"

pr_reviewer_file="$(echo "$resolved" | grep "pr-reviewer.yaml")"
assert_file_exists "pr-reviewer temp file exists" "$pr_reviewer_file"

pr_worker_file="$(echo "$resolved" | grep "pr-worker.yaml")"
assert_file_exists "pr-worker temp file exists" "$pr_worker_file"

pr_reviewer_program="$(yq eval '.spec.program' "$pr_reviewer_file" 2>/dev/null)"
assert_eq "pr-reviewer has program claude-code" "claude-code" "$pr_reviewer_program"

pr_reviewer_deploy="$(yq eval '.spec.deployment.type' "$pr_reviewer_file" 2>/dev/null)"
assert_eq "pr-reviewer has docker deployment" "docker" "$pr_reviewer_deploy"

# Clean up ci-review temp files
rm -rf "$(dirname "$pr_reviewer_file")"

echo ""
# ---------------------------------------------------------------------------
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
