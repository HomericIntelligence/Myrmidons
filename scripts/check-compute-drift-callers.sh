#!/usr/bin/env bash
# scripts/check-compute-drift-callers.sh
#
# Verify that every caller of compute_drift passes the same number of arguments
# that the function declares via its arity guard ([[ $# -ne N ]]).
#
# Exits 0 when all callers are in sync.
# Exits 1 and prints a human-readable report when any caller is out of sync.
#
# Runs:
#   - As a pre-commit hook (triggered when reconcile.sh or any caller is staged)
#   - In CI via .pre-commit-config.yaml (pre-commit run --all-files)
#   - Manually: ./scripts/check-compute-drift-callers.sh

# shellcheck disable=SC2034
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

RECONCILE="${REPO_ROOT}/scripts/lib/reconcile.sh"
CALLERS=(
    "${REPO_ROOT}/scripts/apply.sh"
    "${REPO_ROOT}/scripts/plan.sh"
    "${REPO_ROOT}/scripts/status.sh"
)

# ---------------------------------------------------------------------------
# Extract authoritative arity from reconcile.sh
# ---------------------------------------------------------------------------

# Matches:   if [[ $# -ne 13 ]]; then
declared_arity=""
declared_arity="$(grep -oP '\[\[ \$# -ne \K[0-9]+' "${RECONCILE}" | head -1)"

if [[ -z "$declared_arity" ]]; then
    echo "ERROR: could not find arity guard in ${RECONCILE}" >&2
    echo "       Expected pattern: [[ \$# -ne N ]] inside compute_drift" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Count args at each call site
# ---------------------------------------------------------------------------

# Join continuation lines (line ending with \) and count quoted "$..." tokens
# in the compute_drift call.  We join up to 5 continuation lines to handle
# any reasonable formatting.
count_call_args() {
    local file="$1"
    # Find the line number where compute_drift is called
    local call_line
    call_line="$(grep -n 'compute_drift ' "${file}" | head -1 | cut -d: -f1)"
    if [[ -z "$call_line" ]]; then
        echo "0"
        return
    fi

    # Read up to 6 lines starting at the call site and join continuation lines
    local joined=""
    local i
    for i in $(seq 0 5); do
        local lineno=$(( call_line + i ))
        local line
        line="$(sed -n "${lineno}p" "${file}")"
        # Strip trailing backslash-continuation
        joined+=" ${line%\\}"
        # Stop when the line does NOT end with a backslash (end of call)
        if [[ "$line" != *\\ ]]; then
            break
        fi
    done

    # Count "$..." tokens (each represents one positional argument).
    # grep -o finds each non-overlapping match; wc -l counts them.
    # We subtract 1 for the function name itself if it appears as a "$..." arg
    # (it doesn't — it's a bare word), so raw count equals arg count.
    local count
    count="$(echo "$joined" | grep -oP '"\$[^"]*"' | wc -l)"
    echo "$count"
}

# ---------------------------------------------------------------------------
# Validate each caller
# ---------------------------------------------------------------------------

errors=0

for caller in "${CALLERS[@]}"; do
    name="$(basename "${caller}")"
    actual_count="$(count_call_args "${caller}")"
    if [[ "$actual_count" -ne "$declared_arity" ]]; then
        echo "FAIL: ${name}: compute_drift called with ${actual_count} args (expected ${declared_arity})" >&2
        errors=$(( errors + 1 ))
    else
        echo "OK:   ${name}: compute_drift called with ${actual_count} args"
    fi
done

if [[ "$errors" -gt 0 ]]; then
    echo "" >&2
    echo "Authoritative arity declared in scripts/lib/reconcile.sh: ${declared_arity}" >&2
    echo "" >&2
    echo "To fix: update all callers listed above to pass exactly ${declared_arity} arguments." >&2
    echo "See ADR-009 §How to extend for the full lockstep checklist." >&2
    exit 1
fi

echo ""
echo "All callers pass exactly ${declared_arity} arguments to compute_drift."
