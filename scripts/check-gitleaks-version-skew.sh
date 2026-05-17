#!/usr/bin/env bash
# scripts/check-gitleaks-version-skew.sh — detect skew across gitleaks version pins.
#
# Issue #559: the gitleaks binary version is pinned in THREE places. If they
# drift out of sync, CI and pre-commit scan with different rulesets, which
# means PR checks and merges can produce different findings.
#
# The three pin sites are:
#   1. .github/workflows/_required.yml — env.GITLEAKS_VERSION
#   2. .gitleaks.toml                  — header comment "Pinned version: vX.Y.Z"
#   3. .pre-commit-config.yaml         — rev: under the gitleaks-system hook
#
# This script extracts each pinned version, normalises them (strips a leading
# "v"), and exits non-zero with a diff if they disagree.
#
# Usage:
#   ./scripts/check-gitleaks-version-skew.sh
#
# Optional environment overrides (used by the BATS suite):
#   WORKFLOW_FILE      — path to _required.yml          (default: .github/workflows/_required.yml)
#   GITLEAKS_TOML      — path to .gitleaks.toml         (default: .gitleaks.toml)
#   PRECOMMIT_CONFIG   — path to .pre-commit-config.yaml (default: .pre-commit-config.yaml)
#
# Exit codes:
#   0 = all three pins agree
#   1 = skew detected, or a pin could not be extracted

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

WORKFLOW_FILE="${WORKFLOW_FILE:-${REPO_ROOT}/.github/workflows/_required.yml}"
GITLEAKS_TOML="${GITLEAKS_TOML:-${REPO_ROOT}/.gitleaks.toml}"
PRECOMMIT_CONFIG="${PRECOMMIT_CONFIG:-${REPO_ROOT}/.pre-commit-config.yaml}"

errors=0

_fail() {
    echo "ERROR: $*" >&2
    errors=$((errors + 1))
}

# ---------------------------------------------------------------------------
# 1. Workflow env.GITLEAKS_VERSION
# ---------------------------------------------------------------------------
# Matches:   GITLEAKS_VERSION: "8.24.3"
# Or:        GITLEAKS_VERSION: 8.24.3
workflow_version=""
if [[ -f "$WORKFLOW_FILE" ]]; then
    # Tolerate grep no-match: use a non-pipefail subshell.
    workflow_version="$(set +o pipefail; \
        grep -E '^[[:space:]]+GITLEAKS_VERSION:' "$WORKFLOW_FILE" \
        | head -n 1 \
        | sed -E 's/^[[:space:]]+GITLEAKS_VERSION:[[:space:]]*"?v?([0-9]+\.[0-9]+\.[0-9]+)"?[[:space:]]*$/\1/')"
else
    _fail "workflow file not found: ${WORKFLOW_FILE}"
fi
if [[ -z "$workflow_version" || "$workflow_version" == *"GITLEAKS_VERSION"* ]]; then
    _fail "could not extract GITLEAKS_VERSION from ${WORKFLOW_FILE}"
    workflow_version=""
fi

# ---------------------------------------------------------------------------
# 2. .gitleaks.toml header "Pinned version: vX.Y.Z"
# ---------------------------------------------------------------------------
toml_version=""
if [[ -f "$GITLEAKS_TOML" ]]; then
    toml_version="$(set +o pipefail; \
        grep -E '^#[[:space:]]*Pinned version:[[:space:]]*v?[0-9]+\.[0-9]+\.[0-9]+' "$GITLEAKS_TOML" \
        | head -n 1 \
        | sed -E 's/^#[[:space:]]*Pinned version:[[:space:]]*v?([0-9]+\.[0-9]+\.[0-9]+).*$/\1/')"
else
    _fail "gitleaks config not found: ${GITLEAKS_TOML}"
fi
if [[ -z "$toml_version" ]]; then
    _fail "could not extract 'Pinned version: vX.Y.Z' header comment from ${GITLEAKS_TOML}"
fi

# ---------------------------------------------------------------------------
# 3. .pre-commit-config.yaml gitleaks rev
# ---------------------------------------------------------------------------
# Find the rev: line immediately following the gitleaks repo declaration.
precommit_version=""
if [[ -f "$PRECOMMIT_CONFIG" ]]; then
    precommit_version="$(
        awk '
            /^[[:space:]]*-[[:space:]]*repo:[[:space:]]*https:\/\/github\.com\/gitleaks\/gitleaks[[:space:]]*$/ {
                in_block = 1
                next
            }
            in_block && /^[[:space:]]*rev:[[:space:]]*/ {
                line = $0
                sub(/^[[:space:]]*rev:[[:space:]]*/, "", line)
                sub(/[[:space:]]*(#.*)?$/, "", line)
                sub(/^v/, "", line)
                print line
                exit
            }
        ' "$PRECOMMIT_CONFIG"
    )"
else
    _fail "pre-commit config not found: ${PRECOMMIT_CONFIG}"
fi
if [[ -z "$precommit_version" ]]; then
    _fail "could not extract gitleaks rev from ${PRECOMMIT_CONFIG}"
fi

# ---------------------------------------------------------------------------
# Compare
# ---------------------------------------------------------------------------
if [[ $errors -gt 0 ]]; then
    exit 1
fi

if [[ "$workflow_version" == "$toml_version" && "$toml_version" == "$precommit_version" ]]; then
    echo "OK: gitleaks version aligned across all pin sites: v${workflow_version}"
    exit 0
fi

echo "ERROR: gitleaks version skew detected across pin sites:"
echo ""
printf '  %-30s %s\n' ".github/workflows/_required.yml" "v${workflow_version}"
printf '  %-30s %s\n' ".gitleaks.toml" "v${toml_version}"
printf '  %-30s %s\n' ".pre-commit-config.yaml" "v${precommit_version}"
echo ""
echo "All three sites must pin the same gitleaks version. See issue #559."
echo "When bumping gitleaks, update:"
echo "  - env.GITLEAKS_VERSION in .github/workflows/_required.yml"
echo "  - the 'Pinned version: vX.Y.Z' comment at the top of .gitleaks.toml"
echo "  - the rev: under the gitleaks-system hook in .pre-commit-config.yaml"
exit 1
