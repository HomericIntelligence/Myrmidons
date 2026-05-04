#!/usr/bin/env bash
# tests/test-check-xtrace-guards.sh — unit tests for scripts/check-xtrace-guards.sh
#
# Creates temporary shell script fixtures and verifies detector behavior.
#
# Usage:
#   ./tests/test-check-xtrace-guards.sh
#
# Exit codes:
#   0 = all tests passed
#   1 = one or more tests failed

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DETECTOR="${REPO_ROOT}/scripts/check-xtrace-guards.sh"

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

echo "Testing scripts/check-xtrace-guards.sh..."
echo ""

# --- Test 1: bare ${AGAMEMNON_API_KEY} in curl invocation → exit 1
cat > "${TMPDIR_LOCAL}/violation.sh" <<'EOF'
#!/usr/bin/env bash
curl -H "Authorization: Bearer ${AGAMEMNON_API_KEY}" http://example.com
EOF
assert_exit "bare \${AGAMEMNON_API_KEY} in curl without guard → exit 1" 1 "${TMPDIR_LOCAL}/violation.sh"

# --- Test 2: bare $AGAMEMNON_API_KEY (no braces) in curl → exit 1
cat > "${TMPDIR_LOCAL}/violation-no-braces.sh" <<'EOF'
#!/usr/bin/env bash
curl -H "X-API-Key: $AGAMEMNON_API_KEY" http://example.com
EOF
assert_exit "bare \$AGAMEMNON_API_KEY (no braces) without guard → exit 1" 1 "${TMPDIR_LOCAL}/violation-no-braces.sh"

# --- Test 3: expansion inside { set +x; } / set -x guard → exit 0
cat > "${TMPDIR_LOCAL}/guarded.sh" <<'EOF'
#!/usr/bin/env bash
local _had_xtrace=0
if [[ "$-" == *x* ]]; then _had_xtrace=1; fi
{ set +x; } 2>/dev/null
curl -H "Authorization: Bearer ${AGAMEMNON_API_KEY}" http://example.com
if [[ $_had_xtrace -eq 1 ]]; then set -x; fi
EOF
assert_exit "expansion inside { set +x; } ... set -x guard → exit 0" 0 "${TMPDIR_LOCAL}/guarded.sh"

# --- Test 4: expansion inside bare set +x / set -x guard → exit 0
cat > "${TMPDIR_LOCAL}/guarded-bare.sh" <<'EOF'
#!/usr/bin/env bash
set +x
curl -H "Authorization: Bearer ${AGAMEMNON_API_KEY}" http://example.com
set -x
EOF
assert_exit "expansion inside bare set +x / set -x guard → exit 0" 0 "${TMPDIR_LOCAL}/guarded-bare.sh"

# --- Test 5: suppression annotation on expansion line → exit 0
cat > "${TMPDIR_LOCAL}/suppressed.sh" <<'EOF'
#!/usr/bin/env bash
curl -H "Authorization: Bearer ${AGAMEMNON_API_KEY}" http://example.com # xtrace-lint: ok
EOF
assert_exit "suppressed with # xtrace-lint: ok annotation → exit 0" 0 "${TMPDIR_LOCAL}/suppressed.sh"

# --- Test 6: variable assignment (normalisation) → exit 0
cat > "${TMPDIR_LOCAL}/assignment.sh" <<'EOF'
#!/usr/bin/env bash
AGAMEMNON_API_KEY="${AGAMEMNON_API_KEY:-}"
echo "setup done"
EOF
assert_exit "variable assignment line AGAMEMNON_API_KEY= → exit 0" 0 "${TMPDIR_LOCAL}/assignment.sh"

# --- Test 7: comment-only reference → exit 0
cat > "${TMPDIR_LOCAL}/comment.sh" <<'EOF'
#!/usr/bin/env bash
# Authenticate with ${AGAMEMNON_API_KEY} before calling the API.
echo "hello"
EOF
assert_exit "comment-only reference → exit 0" 0 "${TMPDIR_LOCAL}/comment.sh"

# --- Test 8: no AGAMEMNON_API_KEY reference at all → exit 0
cat > "${TMPDIR_LOCAL}/no-key.sh" <<'EOF'
#!/usr/bin/env bash
curl http://example.com
EOF
assert_exit "no AGAMEMNON_API_KEY reference → exit 0" 0 "${TMPDIR_LOCAL}/no-key.sh"

# --- Test 9: multiple files, one violation one clean → exit 1
cat > "${TMPDIR_LOCAL}/multi-clean.sh" <<'EOF'
#!/usr/bin/env bash
echo "nothing here"
EOF
cat > "${TMPDIR_LOCAL}/multi-dirty.sh" <<'EOF'
#!/usr/bin/env bash
curl -H "X-API-Key: ${AGAMEMNON_API_KEY}" http://example.com
EOF
actual_exit=0
"$DETECTOR" "${TMPDIR_LOCAL}/multi-clean.sh" "${TMPDIR_LOCAL}/multi-dirty.sh" >/dev/null 2>&1 || actual_exit=$?
if [[ "$actual_exit" -eq 1 ]]; then
    echo "  PASS: multiple files, one dirty → exit 1"
    PASS=$((PASS + 1))
else
    echo "  FAIL: multiple files, one dirty → expected exit 1, got ${actual_exit}"
    FAIL=$((FAIL + 1))
fi

# --- Test 10: violation after a guard block ends → exit 1
cat > "${TMPDIR_LOCAL}/post-guard.sh" <<'EOF'
#!/usr/bin/env bash
{ set +x; } 2>/dev/null
curl -H "Authorization: Bearer ${AGAMEMNON_API_KEY}" http://example.com/guarded
if [[ $_had_xtrace -eq 1 ]]; then set -x; fi
curl -H "Authorization: Bearer ${AGAMEMNON_API_KEY}" http://example.com/unguarded
EOF
assert_exit "expansion after guard block ends → exit 1" 1 "${TMPDIR_LOCAL}/post-guard.sh"

# --- Test 11: default scan of repo — should exit 0 (all expansions guarded)
echo -n "  Testing default scan of repo *.sh files: "
default_exit=0
(cd "${REPO_ROOT}" && ./scripts/check-xtrace-guards.sh) >/dev/null 2>&1 || default_exit=$?
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
