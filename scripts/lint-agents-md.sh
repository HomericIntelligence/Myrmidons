#!/usr/bin/env bash
# scripts/lint-agents-md.sh — validate required sections in AGENTS.md
#
# Checks that all six required H2 sections are present in AGENTS.md.
# Prevents PRs from accidentally deleting or renaming a required section.
#
# Usage:
#   ./scripts/lint-agents-md.sh                       # check AGENTS.md at repo root
#   ./scripts/lint-agents-md.sh path/to/AGENTS.md     # check a specific file
#   ./scripts/lint-agents-md.sh -                     # read content from stdin
#   cat AGENTS.md | ./scripts/lint-agents-md.sh -     # equivalent
#   LINT_AGENTS_MD_FILE=path/to/AGENTS.md ./scripts/lint-agents-md.sh
#   LINT_AGENTS_MD_FILE=- ./scripts/lint-agents-md.sh < AGENTS.md
#
# Resolution order for the input source:
#   1. Positional argument (if given; "-" means stdin)
#   2. $LINT_AGENTS_MD_FILE environment variable (value "-" means stdin)
#   3. ${REPO_ROOT}/AGENTS.md as the final default
#
# Note: stdin is consumed only when explicitly requested via "-" (arg or env),
# so the default no-argument behaviour is preserved for pre-commit and CI use.
#
# Exit codes:
#   0 = all required sections present
#   1 = one or more sections missing, file not readable, or invalid input

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Resolve input source.
TARGET=""
READ_STDIN=0

if [[ $# -gt 0 ]]; then
    if [[ "$1" == "-" ]]; then
        READ_STDIN=1
    else
        TARGET="$1"
    fi
elif [[ -n "${LINT_AGENTS_MD_FILE:-}" ]]; then
    if [[ "${LINT_AGENTS_MD_FILE}" == "-" ]]; then
        READ_STDIN=1
    else
        TARGET="${LINT_AGENTS_MD_FILE}"
    fi
else
    TARGET="${REPO_ROOT}/AGENTS.md"
fi

# Materialise stdin into a temp file so we can grep it the same way as a path.
CLEANUP_TMP=""
# shellcheck disable=SC2329  # invoked indirectly via trap below
_lint_agents_md_cleanup() {
    if [[ -n "$CLEANUP_TMP" && -f "$CLEANUP_TMP" ]]; then
        rm -f "$CLEANUP_TMP"
    fi
}
trap _lint_agents_md_cleanup EXIT

if [[ $READ_STDIN -eq 1 ]]; then
    CLEANUP_TMP="$(mktemp -t lint-agents-md.XXXXXX)"
    cat > "$CLEANUP_TMP"
    TARGET="$CLEANUP_TMP"
    DISPLAY_NAME="<stdin>"
else
    DISPLAY_NAME="$TARGET"
fi

if [[ ! -f "$TARGET" ]]; then
    echo "ERROR: lint-agents-md: file not found: ${DISPLAY_NAME}"
    exit 1
fi

REQUIRED_SECTIONS=(
    "## Scope"
    "## Permitted Actions"
    "## Prohibited Actions"
    "## \`--dangerously-skip-permissions\` Policy"
    "## Fleet Coordination"
    "## Escalation — Human Review Required"
)

MISSING=0

for section in "${REQUIRED_SECTIONS[@]}"; do
    if ! grep -qF "$section" "$TARGET"; then
        echo "ERROR: lint-agents-md: required section missing from ${DISPLAY_NAME}: ${section}"
        MISSING=$((MISSING + 1))
    fi
done

if [[ $MISSING -gt 0 ]]; then
    echo ""
    echo "lint-agents-md: ${MISSING} required section(s) missing from ${DISPLAY_NAME}."
    echo "Restore the missing sections or update REQUIRED_SECTIONS in scripts/lint-agents-md.sh."
    exit 1
fi

exit 0
