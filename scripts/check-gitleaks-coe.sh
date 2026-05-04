#!/usr/bin/env bash
# scripts/check-gitleaks-coe.sh — regression guard
#
# Fails if any workflow file has `continue-on-error` on the line immediately
# following a `gitleaks detect` step. This prevents the gitleaks scan from
# silently passing when secrets are found.
#
# Usage:
#   ./scripts/check-gitleaks-coe.sh [file ...]
#
# Exit codes:
#   0 = no violations
#   1 = violation found

set -euo pipefail

files=("$@")
if [[ ${#files[@]} -eq 0 ]]; then
    mapfile -t files < <(find .github/workflows -name '*.yml' | sort)
fi

rc=0
for f in "${files[@]}"; do
    # Look for a line containing 'gitleaks detect' immediately followed by
    # a line containing 'continue-on-error'.
    if grep -n 'gitleaks detect' "$f" | while IFS=: read -r lineno _; do
        nextline=$(sed -n "$((lineno + 1))p" "$f")
        if echo "$nextline" | grep -q 'continue-on-error'; then
            echo "ERROR: $f line $lineno: gitleaks detect step has continue-on-error — remove it so scan failures block CI." >&2
            exit 1
        fi
    done; then
        :
    else
        rc=1
    fi
done
exit "$rc"
