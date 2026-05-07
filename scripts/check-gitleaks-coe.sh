#!/usr/bin/env bash
# scripts/check-gitleaks-coe.sh
#
# Lint guard: detect prohibited 'continue-on-error: true' on gitleaks CI steps.
#
# Policy: Security scanning steps must fail the workflow on detected issues.
# Setting continue-on-error: true silently suppresses gitleaks results, creating a
# false sense of security. The correct approach is to use .gitleaks.toml allowlist
# entries with justification comments for false positives.
#
# This script searches all workflow files in .github/workflows/ for the pattern
# and exits 1 if found on any gitleaks step.
#
# Handles Windows line endings (CRLF) by normalizing before grep.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:=$(cd "${SCRIPT_DIR}/.." && pwd)}"
WORKFLOW_DIR="${REPO_ROOT}/.github/workflows"

if [[ ! -d "$WORKFLOW_DIR" ]]; then
    echo "ERROR: Workflow directory not found: $WORKFLOW_DIR" >&2
    exit 1
fi

FOUND=0

# Search all .yml workflow files
while IFS= read -r -d '' workflow_file; do
    # Normalize line endings (remove \r for CRLF files)
    normalized=$(tr -d '\r' < "$workflow_file")

    # Look for gitleaks step with continue-on-error: true
    # Pattern: gitleaks in a name or run step, followed by continue-on-error: true
    if grep -q "gitleaks" <<< "$normalized"; then
        # Check if this file has continue-on-error: true near a gitleaks reference
        if grep -E "continue-on-error:\s*true" <<< "$normalized" | grep -q .; then
            # More precise check: ensure continue-on-error is near gitleaks context
            if grep -B 5 -A 5 "gitleaks" <<< "$normalized" | grep -q "continue-on-error:\s*true"; then
                echo "ERROR: $workflow_file contains 'continue-on-error: true' with gitleaks"
                echo "  → Security scanning must fail the workflow on detected secrets"
                echo "  → Use .gitleaks.toml allowlist entries with justification comments instead"
                FOUND=$((FOUND + 1))
            fi
        fi
    fi
done < <(find "$WORKFLOW_DIR" -maxdepth 1 -name "*.yml" -print0)

if [[ $FOUND -gt 0 ]]; then
    echo ""
    echo "check-gitleaks-coe: found $FOUND workflow file(s) with prohibited continue-on-error on gitleaks."
    exit 1
fi

exit 0
