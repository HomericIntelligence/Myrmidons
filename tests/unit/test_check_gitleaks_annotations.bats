#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# tests/unit/test_check_gitleaks_annotations.bats
#
# Issue #561: lint guard for .gitleaks.toml allowlist annotation policy.
#
# Verifies scripts/check-gitleaks-annotations.sh enforces that every regex /
# path / commit / fingerprint entry inside an [allowlist] block carries an
# inline `# gitleaks-allowlist: <non-empty justification>` comment.

# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
CHECKER="${SCRIPT_DIR}/scripts/check-gitleaks-annotations.sh"

TMP_DIR=""

setup() {
    TMP_DIR="$(mktemp -d)"
}

teardown() {
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
}

# Helper: write content to a .gitleaks.toml fixture under TMP_DIR.
_write_toml() {
    local name="$1"
    local content="$2"
    local path="${TMP_DIR}/${name}"
    printf '%s' "$content" > "$path"
    printf '%s\n' "$path"
}

# ---------------------------------------------------------------------------
# Test: fully-annotated fixture passes (exit 0)
# ---------------------------------------------------------------------------

@test "check-gitleaks-annotations: compliant fixture exits 0" {
    file="$(_write_toml compliant.toml '# Test fixture
title = "Myrmidons gitleaks configuration"

[extend]
useDefault = true

[allowlist]
description = "Test fixtures and documentation examples"
regexes = [
  '"'"''"'"''"'"'your-token-here'"'"''"'"''"'"',         # gitleaks-allowlist: placeholder token in CLAUDE.md
  '"'"''"'"''"'"'fake-api-key'"'"''"'"''"'"',            # gitleaks-allowlist: doc example, not a real credential
]
paths = [
  '"'"''"'"''"'"'tests/.*'"'"''"'"''"'"',                # gitleaks-allowlist: test fixtures contain fake secrets
]
')"
    run bash "$CHECKER" "$file"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Test: missing annotation on a regex entry → exit 1 with line number
# ---------------------------------------------------------------------------

@test "check-gitleaks-annotations: missing annotation fails with line number" {
    file="$(_write_toml missing.toml '# Test fixture
title = "Myrmidons gitleaks configuration"

[allowlist]
description = "Test fixtures"
regexes = [
  '"'"''"'"''"'"'your-token-here'"'"''"'"''"'"',         # gitleaks-allowlist: ok justification
  '"'"''"'"''"'"'missing-annotation'"'"''"'"''"'"',
]
')"
    run bash "$CHECKER" "$file"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing # gitleaks-allowlist: annotation"* ]]
    # The offending entry is on line 8 of the fixture above.
    [[ "$output" == *":8:"* ]]
}

# ---------------------------------------------------------------------------
# Test: annotation present but empty → exit 1
# ---------------------------------------------------------------------------

@test "check-gitleaks-annotations: empty justification fails" {
    file="$(_write_toml empty.toml '[allowlist]
description = "Test fixtures"
regexes = [
  '"'"''"'"''"'"'token'"'"''"'"''"'"',                   # gitleaks-allowlist:
]
')"
    run bash "$CHECKER" "$file"
    [ "$status" -eq 1 ]
    [[ "$output" == *"empty gitleaks-allowlist justification"* ]]
}

# ---------------------------------------------------------------------------
# Test: entries outside [allowlist] are not enforced
# ---------------------------------------------------------------------------

@test "check-gitleaks-annotations: entries outside [allowlist] are ignored" {
    file="$(_write_toml outside.toml '[extend]
useDefault = true

[[rules]]
id = "my-rule"
regex = '"'"''"'"''"'"'some-pattern'"'"''"'"''"'"'
')"
    run bash "$CHECKER" "$file"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Test: paths entries also require annotations
# ---------------------------------------------------------------------------

@test "check-gitleaks-annotations: paths entries without annotation fail" {
    file="$(_write_toml paths.toml '[allowlist]
description = "Test fixtures"
paths = [
  '"'"''"'"''"'"'tests/.*'"'"''"'"''"'"',
]
')"
    run bash "$CHECKER" "$file"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing # gitleaks-allowlist: annotation"* ]]
}

# ---------------------------------------------------------------------------
# Test: real repo .gitleaks.toml passes (regression guard for issue #562)
# ---------------------------------------------------------------------------

@test "check-gitleaks-annotations: real repository .gitleaks.toml passes" {
    run bash "$CHECKER" "${SCRIPT_DIR}/.gitleaks.toml"
    [ "$status" -eq 0 ]
}
