#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
# tests/unit/test_check_gitleaks_version_skew.bats
#
# Issue #559: verify the gitleaks-version-skew detector catches each axis of
# disagreement and accepts aligned pins.

# shellcheck disable=SC2034
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
CHECKER="${SCRIPT_DIR}/scripts/check-gitleaks-version-skew.sh"

TMP_DIR=""

setup() {
    TMP_DIR="$(mktemp -d)"
    mkdir -p "${TMP_DIR}/.github/workflows"
}

teardown() {
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
}

# Helper: write the three pin sites with the given versions.
_write_fixtures() {
    local workflow_v="$1"
    local toml_v="$2"
    local precommit_v="$3"

    cat > "${TMP_DIR}/.github/workflows/_required.yml" <<EOF
name: Required Checks
env:
  GITLEAKS_VERSION: "${workflow_v}"
EOF

    cat > "${TMP_DIR}/.gitleaks.toml" <<EOF
# Myrmidons gitleaks configuration
# Pinned version: v${toml_v}
title = "fixture"
EOF

    cat > "${TMP_DIR}/.pre-commit-config.yaml" <<EOF
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v${precommit_v}
    hooks:
      - id: gitleaks-system
EOF
}

_run_checker() {
    WORKFLOW_FILE="${TMP_DIR}/.github/workflows/_required.yml" \
        GITLEAKS_TOML="${TMP_DIR}/.gitleaks.toml" \
        PRECOMMIT_CONFIG="${TMP_DIR}/.pre-commit-config.yaml" \
        bash "$CHECKER" 2>&1
}

# ---------------------------------------------------------------------------
# Happy path: all three sites agree → exit 0
# ---------------------------------------------------------------------------

@test "gitleaks-version-skew: aligned versions exit 0" {
    _write_fixtures "8.24.3" "8.24.3" "8.24.3"
    run _run_checker
    [ "$status" -eq 0 ]
    [[ "$output" == *"aligned"* ]]
    [[ "$output" == *"v8.24.3"* ]]
}

# ---------------------------------------------------------------------------
# Skew axis 1: workflow drifts from the others
# ---------------------------------------------------------------------------

@test "gitleaks-version-skew: workflow drift exits 1" {
    _write_fixtures "8.30.1" "8.24.3" "8.24.3"
    run _run_checker
    [ "$status" -eq 1 ]
    [[ "$output" == *"skew detected"* ]]
    [[ "$output" == *"v8.30.1"* ]]
    [[ "$output" == *"v8.24.3"* ]]
    [[ "$output" == *"_required.yml"* ]]
}

# ---------------------------------------------------------------------------
# Skew axis 2: .gitleaks.toml drifts from the others
# ---------------------------------------------------------------------------

@test "gitleaks-version-skew: toml drift exits 1" {
    _write_fixtures "8.24.3" "8.30.1" "8.24.3"
    run _run_checker
    [ "$status" -eq 1 ]
    [[ "$output" == *"skew detected"* ]]
    [[ "$output" == *".gitleaks.toml"* ]]
    [[ "$output" == *"v8.30.1"* ]]
}

# ---------------------------------------------------------------------------
# Skew axis 3: pre-commit rev drifts from the others
# ---------------------------------------------------------------------------

@test "gitleaks-version-skew: pre-commit rev drift exits 1" {
    _write_fixtures "8.24.3" "8.24.3" "8.30.1"
    run _run_checker
    [ "$status" -eq 1 ]
    [[ "$output" == *"skew detected"* ]]
    [[ "$output" == *".pre-commit-config.yaml"* ]]
    [[ "$output" == *"v8.30.1"* ]]
}

# ---------------------------------------------------------------------------
# All three differ
# ---------------------------------------------------------------------------

@test "gitleaks-version-skew: three-way skew exits 1" {
    _write_fixtures "8.20.0" "8.24.3" "8.30.1"
    run _run_checker
    [ "$status" -eq 1 ]
    [[ "$output" == *"v8.20.0"* ]]
    [[ "$output" == *"v8.24.3"* ]]
    [[ "$output" == *"v8.30.1"* ]]
}

# ---------------------------------------------------------------------------
# Missing 'Pinned version:' comment in toml → error (cannot validate)
# ---------------------------------------------------------------------------

@test "gitleaks-version-skew: missing toml pin comment exits 1" {
    _write_fixtures "8.24.3" "8.24.3" "8.24.3"
    cat > "${TMP_DIR}/.gitleaks.toml" <<EOF
# Myrmidons gitleaks configuration
# No pin comment here
title = "fixture"
EOF
    run _run_checker
    [ "$status" -eq 1 ]
    [[ "$output" == *"Pinned version"* ]]
}

# ---------------------------------------------------------------------------
# Workflow accepts unquoted version
# ---------------------------------------------------------------------------

@test "gitleaks-version-skew: unquoted workflow version parses correctly" {
    _write_fixtures "8.24.3" "8.24.3" "8.24.3"
    cat > "${TMP_DIR}/.github/workflows/_required.yml" <<EOF
env:
  GITLEAKS_VERSION: 8.24.3
EOF
    run _run_checker
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Regression guard: real repo files are aligned
# ---------------------------------------------------------------------------

@test "gitleaks-version-skew: real repo pins are aligned" {
    run bash "$CHECKER"
    [ "$status" -eq 0 ]
}
