#!/usr/bin/env bash
# tests/test-validate-schemas.sh — Test harness for validate-schemas.sh
#
# Exercises the new validation checks added in issue #2:
#   - spec.program enum validation
#   - metadata.host / directory name matching
#   - spec.deployment.docker.image required when type=docker
#   - cross-file metadata.name uniqueness
#   - spec.workingDirectory existence warning (local only)
#
# Usage:
#   CI=true ./tests/test-validate-schemas.sh
#
# Exit codes:
#   0 = all tests passed
#   1 = one or more tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="${SCRIPT_DIR}/validate-schemas.sh"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures"

PASS=0
FAIL=0

# Helper: run validate-schemas.sh against a temporary agents/ tree
# Usage: run_validator <tmp_agents_root>
# Returns the exit code of the validator
run_validator() {
    local tmp_root="$1"
    # Override REPO_ROOT by symlinking/copying agents and fleets under tmp_root
    # The script uses REPO_ROOT derived from its own location; we pass a custom
    # directory by temporarily setting up a minimal tree with only the files we want.
    # We do this by calling the script with a wrapper that overrides REPO_ROOT via env.
    CI=true MYRMIDONS_TEST_AGENTS_ROOT="$tmp_root" bash -c "
        # Source the validator with overridden REPO_ROOT
        export CI=true
        _orig=\$(grep -n 'REPO_ROOT=' '${VALIDATE}' | head -1 | cut -d: -f1)
        # Run the script but override find paths
        bash <(sed 's|find \"\${REPO_ROOT}/agents\" \"\${REPO_ROOT}/fleets\"|find \"${tmp_root}/agents\" \"${tmp_root}/fleets\"|g' '${VALIDATE}')
    " 2>&1
}

# Helper: assert exit code
assert_exit() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    local output="$4"
    if [[ "$actual" -eq "$expected" ]]; then
        echo "  PASS: ${test_name}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${test_name} (expected exit ${expected}, got ${actual})"
        echo "  Output:"
        echo "$output" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

# Helper: assert output contains pattern
assert_output_contains() {
    local test_name="$1"
    local pattern="$2"
    local output="$3"
    if echo "$output" | grep -qF "$pattern"; then
        echo "  PASS: ${test_name}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${test_name} (expected output to contain '${pattern}')"
        echo "  Output:"
        echo "$output" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

# Helper: assert output does NOT contain pattern
assert_output_not_contains() {
    local test_name="$1"
    local pattern="$2"
    local output="$3"
    if ! echo "$output" | grep -qF "$pattern"; then
        echo "  PASS: ${test_name}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${test_name} (expected output NOT to contain '${pattern}')"
        echo "  Output:"
        echo "$output" | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

# Helper: build a temporary agent tree with specific fixtures
# Usage: make_tree <fixture_file>...
# Each arg is a relative path under fixtures/ that maps to the same relative path under tmp tree
make_tree() {
    local tmp
    tmp="$(mktemp -d)"
    mkdir -p "${tmp}/agents" "${tmp}/fleets"
    for src in "$@"; do
        local dest_rel="${src#"${FIXTURES_DIR}/"}"
        local dest="${tmp}/${dest_rel}"
        mkdir -p "$(dirname "$dest")"
        cp "$src" "$dest"
    done
    echo "$tmp"
}

echo "Running validate-schemas.sh tests..."
echo ""

# ─── Test 1: valid agent passes ───────────────────────────────────────────────
echo "Test 1: valid agent passes"
tree=$(make_tree "${FIXTURES_DIR}/agents/hermes/valid-agent.yaml")
output=$(run_validator "$tree" 2>&1)
rc=$?
rm -rf "$tree"
assert_exit "valid agent exits 0" 0 "$rc" "$output"
assert_output_contains "valid agent shows ok" "ok (Agent: test-valid-agent)" "$output"

# ─── Test 2: invalid program value fails ──────────────────────────────────────
echo ""
echo "Test 2: invalid spec.program value fails"
tree=$(make_tree "${FIXTURES_DIR}/agents/hermes/invalid-program.yaml")
output=$(run_validator "$tree" 2>&1)
rc=$?
rm -rf "$tree"
assert_exit "invalid program exits 1" 1 "$rc" "$output"
assert_output_contains "invalid program error message" "spec.program must be one of:" "$output"

# ─── Test 3: valid programs all accepted ──────────────────────────────────────
echo ""
echo "Test 3: all valid program values are accepted"
valid_programs=(claude-code aider codex goose cline opencode codebuff ampcode none)
for prog in "${valid_programs[@]}"; do
    tmp_yaml="$(mktemp --suffix=.yaml)"
    cat > "$tmp_yaml" <<EOF
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: test-prog-${prog}
  host: hermes
spec:
  label: Test
  program: ${prog}
  workingDirectory: /tmp
  deployment:
    type: local
  desiredState: active
EOF
    tree=$(mktemp -d)
    mkdir -p "${tree}/agents/hermes" "${tree}/fleets"
    cp "$tmp_yaml" "${tree}/agents/hermes/agent.yaml"
    rm "$tmp_yaml"
    output=$(run_validator "$tree" 2>&1)
    rc=$?
    rm -rf "$tree"
    assert_exit "program '${prog}' is accepted (exit 0)" 0 "$rc" "$output"
done

# ─── Test 4: host/directory mismatch fails ────────────────────────────────────
echo ""
echo "Test 4: metadata.host not matching directory fails"
tree=$(make_tree "${FIXTURES_DIR}/agents/wrongdir/invalid-host-mismatch.yaml")
output=$(run_validator "$tree" 2>&1)
rc=$?
rm -rf "$tree"
assert_exit "host mismatch exits 1" 1 "$rc" "$output"
assert_output_contains "host mismatch error message" "does not match directory" "$output"

# ─── Test 5: docker type without image fails ──────────────────────────────────
echo ""
echo "Test 5: deployment.type=docker without docker.image fails"
tree=$(make_tree "${FIXTURES_DIR}/agents/hermes/invalid-docker-no-image.yaml")
output=$(run_validator "$tree" 2>&1)
rc=$?
rm -rf "$tree"
assert_exit "docker no image exits 1" 1 "$rc" "$output"
assert_output_contains "docker no image error message" "spec.deployment.docker.image is required" "$output"

# ─── Test 6: docker type with image passes ────────────────────────────────────
echo ""
echo "Test 6: deployment.type=docker with docker.image passes"
tree=$(make_tree "${FIXTURES_DIR}/agents/hermes/valid-docker-agent.yaml")
output=$(run_validator "$tree" 2>&1)
rc=$?
rm -rf "$tree"
assert_exit "valid docker agent exits 0" 0 "$rc" "$output"
assert_output_not_contains "valid docker agent no image error" "spec.deployment.docker.image is required" "$output"

# ─── Test 7: duplicate names detected ─────────────────────────────────────────
echo ""
echo "Test 7: duplicate metadata.name across files fails"
tree=$(make_tree \
    "${FIXTURES_DIR}/agents/hermes/duplicate-name-a.yaml" \
    "${FIXTURES_DIR}/agents/hermes/duplicate-name-b.yaml")
output=$(run_validator "$tree" 2>&1)
rc=$?
rm -rf "$tree"
assert_exit "duplicate names exits 1" 1 "$rc" "$output"
assert_output_contains "duplicate names error message" "duplicate metadata.name 'test-duplicate-name'" "$output"

# ─── Test 8: unique names pass ────────────────────────────────────────────────
echo ""
echo "Test 8: unique names across files passes"
tree=$(make_tree \
    "${FIXTURES_DIR}/agents/hermes/valid-agent.yaml" \
    "${FIXTURES_DIR}/agents/hermes/valid-docker-agent.yaml")
output=$(run_validator "$tree" 2>&1)
rc=$?
rm -rf "$tree"
assert_exit "unique names exits 0" 0 "$rc" "$output"
assert_output_not_contains "no duplicate error when names unique" "duplicate metadata.name" "$output"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
echo ""

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
