#!/usr/bin/env bash
# tests/test-check-dangerous-flags.sh — unit tests for scripts/check-dangerous-flags.sh
#
# Creates temporary YAML fixtures and verifies detector behavior.
#
# Usage:
#   ./tests/test-check-dangerous-flags.sh
#
# Exit codes:
#   0 = all tests passed
#   1 = one or more tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DETECTOR="${REPO_ROOT}/scripts/check-dangerous-flags.sh"

PASS=0
FAIL=0
TMPDIR_LOCAL="$(mktemp -d)"

cleanup() {
    rm -rf "$TMPDIR_LOCAL"
}
trap cleanup EXIT

assert_exit() {
    local description="$1"
    local expected_exit="$2"
    local file="$3"

    actual_exit=0
    "$DETECTOR" "$file" >/dev/null 2>&1 || actual_exit=$?

    if [[ "$actual_exit" -eq "$expected_exit" ]]; then
        echo "  PASS: ${description}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${description}"
        echo "        expected exit ${expected_exit}, got ${actual_exit}"
        FAIL=$((FAIL + 1))
    fi
}

echo "Testing scripts/check-dangerous-flags.sh..."
echo ""

# --- Test 1: bare flag without suppression → exit 1 (violation)
cat > "${TMPDIR_LOCAL}/violation.yaml" <<'EOF'
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: test-agent
  host: hermes
spec:
  program: claude-code
  workingDirectory: /tmp/test
  programArgs: "--dangerously-skip-permissions"
  desiredState: active
EOF
assert_exit "bare --dangerously-skip-permissions without suppression → exit 1" 1 "${TMPDIR_LOCAL}/violation.yaml"

# --- Test 2: flag with suppression annotation → exit 0
cat > "${TMPDIR_LOCAL}/suppressed.yaml" <<'EOF'
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: test-agent
  host: hermes
spec:
  program: claude-code
  workingDirectory: /tmp/test
  programArgs: "--dangerously-skip-permissions" # skip-permissions-lint: test justification
  desiredState: active
EOF
assert_exit "suppressed line with # skip-permissions-lint: → exit 0" 0 "${TMPDIR_LOCAL}/suppressed.yaml"

# --- Test 3: flag alongside another flag, without suppression → exit 1
cat > "${TMPDIR_LOCAL}/combined-violation.yaml" <<'EOF'
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: test-agent
  host: hermes
spec:
  program: claude-code
  workingDirectory: /tmp/test
  programArgs: "--dangerously-skip-permissions --model claude-opus-4-6"
  desiredState: active
EOF
assert_exit "combined flags without suppression → exit 1" 1 "${TMPDIR_LOCAL}/combined-violation.yaml"

# --- Test 4: flag alongside another flag, with suppression → exit 0
cat > "${TMPDIR_LOCAL}/combined-suppressed.yaml" <<'EOF'
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: test-agent
  host: hermes
spec:
  program: claude-code
  workingDirectory: /tmp/test
  programArgs: "--dangerously-skip-permissions --model claude-opus-4-6" # skip-permissions-lint: justified
  desiredState: active
EOF
assert_exit "combined flags with suppression → exit 0" 0 "${TMPDIR_LOCAL}/combined-suppressed.yaml"

# --- Test 5: benign YAML with no dangerous flag → exit 0
cat > "${TMPDIR_LOCAL}/benign.yaml" <<'EOF'
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: test-agent
  host: hermes
spec:
  program: claude-code
  workingDirectory: /tmp/test
  programArgs: "--model claude-opus-4-6"
  desiredState: active
EOF
assert_exit "benign YAML with no dangerous flag → exit 0" 0 "${TMPDIR_LOCAL}/benign.yaml"

# --- Test 6: empty programArgs → exit 0
cat > "${TMPDIR_LOCAL}/empty-args.yaml" <<'EOF'
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: test-agent
  host: hermes
spec:
  program: claude-code
  workingDirectory: /tmp/test
  programArgs: ""
  desiredState: active
EOF
assert_exit "empty programArgs → exit 0" 0 "${TMPDIR_LOCAL}/empty-args.yaml"

# --- Test 7: Fleet YAML with bare flag → exit 1
cat > "${TMPDIR_LOCAL}/fleet-violation.yaml" <<'EOF'
apiVersion: myrmidons/v1
kind: Fleet
metadata:
  name: test-fleet
  host: hermes
spec:
  agents:
    - name: agent1
      program: claude-code
      workingDirectory: /tmp/test
      programArgs: "--dangerously-skip-permissions"
      desiredState: active
EOF
assert_exit "Fleet YAML with bare flag → exit 1" 1 "${TMPDIR_LOCAL}/fleet-violation.yaml"

# --- Test 8: Fleet YAML with suppressed flag → exit 0
cat > "${TMPDIR_LOCAL}/fleet-suppressed.yaml" <<'EOF'
apiVersion: myrmidons/v1
kind: Fleet
metadata:
  name: test-fleet
  host: hermes
spec:
  agents:
    - name: agent1
      program: claude-code
      workingDirectory: /tmp/test
      programArgs: "--dangerously-skip-permissions" # skip-permissions-lint: ephemeral container with timeout guardrail
      desiredState: active
EOF
assert_exit "Fleet YAML with suppressed flag → exit 0" 0 "${TMPDIR_LOCAL}/fleet-suppressed.yaml"

# --- Test 9: default scan (no args) against repo — should exit 0 after fixes
echo -n "  Testing default scan of repo agents/ and fleets/ after fixes: "
default_exit=0
(cd "${REPO_ROOT}" && ./scripts/check-dangerous-flags.sh) >/dev/null 2>&1 || default_exit=$?
if [[ "$default_exit" -eq 0 ]]; then
    echo "PASS (exit 0)"
    PASS=$((PASS + 1))
else
    echo "FAIL (exit ${default_exit} — violations remain in repo)"
    FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
