#!/usr/bin/env bash
# scripts/check-bats-run-or-true.sh — Lint guard: flag `run ... || true` in BATS files
#
# In BATS, `run COMMAND` captures the exit code of COMMAND into `$status`.
# Appending `|| true` to the run line wraps COMMAND in an `OR` expression whose
# subshell always exits 0, so `$status` is never meaningful and any subsequent
# `[ "$status" -eq N ]` assertion is silently meaningless. This antipattern
# shipped in Tests 1, 2, and 3 before #398 and was difficult to spot in review.
#
# Use BATS's intended idiom instead:
#
#     run COMMAND ...
#     [ "$status" -eq 0 ]   # or whatever exit code is expected
#
# If you genuinely need the command to never abort the test regardless of exit
# code, do NOT use `|| true` on the `run` line — just rely on `run`'s own
# capture and assert on `$status` (or assert nothing). See issue #507.
#
# Exit codes:
#   0 — no violations
#   1 — one or more violations found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Collect .bats files: either args from pre-commit, or scan tests/ tree.
if [[ $# -gt 0 ]]; then
    FILES=("$@")
else
    mapfile -t FILES < <(find "${REPO_ROOT}/tests" -name '*.bats' -type f)
fi

violations=0

for file in "${FILES[@]}"; do
    # Only inspect .bats files even if other paths slip through.
    [[ "$file" == *.bats ]] || continue
    [[ -f "$file" ]] || continue

    # Match lines that start with optional whitespace, then `run ` (BATS's
    # exit-code-capturing builtin), with `|| true` somewhere on the same line.
    # We deliberately key on `^[[:space:]]*run[[:space:]]` to avoid false
    # positives from arbitrary commands that happen to contain `|| true`
    # (which BATS-internal `run` already neutralizes by capturing $status).
    while IFS= read -r match; do
        [[ -n "$match" ]] || continue
        lineno="${match%%:*}"
        line="${match#*:}"
        printf '%s:%s: BATS antipattern: `run ... || true` discards $status — drop `|| true` and assert on $status instead (see issue #507)\n    %s\n' \
            "$file" "$lineno" "$line" >&2
        violations=$((violations + 1))
    done < <(grep -nE '^[[:space:]]*run[[:space:]].*\|\|[[:space:]]*true([[:space:]]*$|[[:space:]]+#)' "$file" || true)
done

if (( violations > 0 )); then
    printf '\n%d BATS `run ... || true` antipattern violation(s) found.\n' "$violations" >&2
    exit 1
fi

exit 0
