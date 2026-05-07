#!/usr/bin/env bash
# tests/test-check-schema-hints.sh — unit tests for scripts/check-schema-hints.sh
#
# Creates temporary YAML fixtures and verifies detector behavior.
#
# Usage:
#   ./tests/test-check-schema-hints.sh
#
# Exit codes:
#   0 = all tests passed
#   1 = one or more tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DETECTOR="${REPO_ROOT}/scripts/check-schema-hints.sh"

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

echo "Testing scripts/check-schema-hints.sh..."
echo ""

# --- Test 1: correct canonical hint on line 1 → exit 0
cat > "${TMPDIR_LOCAL}/correct.yaml" <<'EOF'
# yaml-language-server: $schema=../../schemas/agent-v1.schema.json
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: test-agent
  host: hermes
spec:
  program: claude-code
  workingDirectory: /tmp/test
  desiredState: active
EOF
assert_exit "correct canonical hint → exit 0" 0 "${TMPDIR_LOCAL}/correct.yaml"

# --- Test 2: missing hint entirely (no comment on line 1) → exit 1
cat > "${TMPDIR_LOCAL}/missing.yaml" <<'EOF'
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: test-agent
  host: hermes
spec:
  program: claude-code
  workingDirectory: /tmp/test
  desiredState: active
EOF
assert_exit "missing hint on line 1 → exit 1" 1 "${TMPDIR_LOCAL}/missing.yaml"

# --- Test 3: malformed hint — dollar-sign missing (the original issue69 bug) → exit 1
cat > "${TMPDIR_LOCAL}/malformed-no-dollar.yaml" <<'EOF'
# yaml-language-server: =../../schemas/agent-v1.schema.json
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: test-agent
  host: hermes
spec:
  program: claude-code
  workingDirectory: /tmp/test
  desiredState: active
EOF
assert_exit "malformed hint: missing \$schema= prefix → exit 1" 1 "${TMPDIR_LOCAL}/malformed-no-dollar.yaml"

# --- Test 4: malformed hint — 'schema=' without dollar → exit 1
cat > "${TMPDIR_LOCAL}/malformed-no-dollar2.yaml" <<'EOF'
# yaml-language-server: schema=../../schemas/agent-v1.schema.json
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: test-agent
  host: hermes
spec:
  program: claude-code
  workingDirectory: /tmp/test
  desiredState: active
EOF
assert_exit "malformed hint: schema= without dollar → exit 1" 1 "${TMPDIR_LOCAL}/malformed-no-dollar2.yaml"

# --- Test 5: malformed hint — wrong case ($Schema= instead of $schema=) → exit 1
cat > "${TMPDIR_LOCAL}/malformed-wrong-case.yaml" <<'EOF'
# yaml-language-server: $Schema=../../schemas/agent-v1.schema.json
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: test-agent
  host: hermes
spec:
  program: claude-code
  workingDirectory: /tmp/test
  desiredState: active
EOF
assert_exit "malformed hint: wrong case \$Schema= → exit 1" 1 "${TMPDIR_LOCAL}/malformed-wrong-case.yaml"

# --- Test 6: suppression annotation on line 1 → exit 0
cat > "${TMPDIR_LOCAL}/suppressed.yaml" <<'EOF'
# schema-hint-skip: template file, schema path varies per deployment target
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: test-agent
  host: hermes
spec:
  program: claude-code
  workingDirectory: /tmp/test
  desiredState: active
EOF
assert_exit "suppression annotation # schema-hint-skip: → exit 0" 0 "${TMPDIR_LOCAL}/suppressed.yaml"

# --- Test 7: _templates/ file without a schema hint → exit 0 (skipped)
mkdir -p "${TMPDIR_LOCAL}/_templates"
cat > "${TMPDIR_LOCAL}/_templates/no-hint.yaml" <<'EOF'
# Template: Claude Code agent (local deployment)
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: template-agent
  host: hermes
spec:
  program: claude-code
  workingDirectory: /tmp/test
  desiredState: active
EOF
assert_exit "_templates/ file skipped → exit 0" 0 "${TMPDIR_LOCAL}/_templates/no-hint.yaml"

# --- Test 8: Fleet YAML without hint → exit 1
cat > "${TMPDIR_LOCAL}/fleet-missing.yaml" <<'EOF'
apiVersion: myrmidons/v1
kind: Fleet
metadata:
  name: test-fleet
  host: hermes
spec:
  agents:
    - ref: hermes/aindrea
EOF
assert_exit "Fleet YAML without schema hint → exit 1" 1 "${TMPDIR_LOCAL}/fleet-missing.yaml"

# --- Test 9: Fleet YAML with correct hint → exit 0
cat > "${TMPDIR_LOCAL}/fleet-correct.yaml" <<'EOF'
# yaml-language-server: $schema=../../schemas/fleet-v1.schema.json
apiVersion: myrmidons/v1
kind: Fleet
metadata:
  name: test-fleet
  host: hermes
spec:
  agents:
    - ref: hermes/aindrea
EOF
assert_exit "Fleet YAML with correct schema hint → exit 0" 0 "${TMPDIR_LOCAL}/fleet-correct.yaml"

# --- Test 10: default scan (no args) against repo — should exit 0 on clean baseline
echo -n "  Testing default scan of repo agents/ and fleets/: "
default_exit=0
(cd "${REPO_ROOT}" && ./scripts/check-schema-hints.sh) >/dev/null 2>&1 || default_exit=$?
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
