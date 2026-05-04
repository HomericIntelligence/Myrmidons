#!/usr/bin/env bash
# scripts/check-xtrace-guards.sh — lint guard for AGAMEMNON_API_KEY xtrace leaks
#
# Scans shell scripts for lines that expand ${AGAMEMNON_API_KEY} or $AGAMEMNON_API_KEY
# outside of a set +x / set -x guard block. Unguarded expansions cause the API key
# value to appear in bash -x trace output.
#
# Guard patterns recognised:
#   { set +x; } 2>/dev/null          — start of guard
#   if [[ $_had_xtrace -eq 1 ]]; then set -x; fi   — end of guard
#   set +x                            — bare start of guard
#   set -x                            — bare end of guard
#
# Suppression annotation (same line):
#   ${AGAMEMNON_API_KEY}  # xtrace-lint: ok
#
# Usage:
#   ./scripts/check-xtrace-guards.sh                  # scan all *.sh in repo
#   ./scripts/check-xtrace-guards.sh file1.sh ...     # scan specific files
#
# Exit codes:
#   0 = no violations
#   1 = violations found

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

VIOLATIONS=0
FILES_CHECKED=0

# Collect files to scan
if [[ $# -gt 0 ]]; then
    FILES=("$@")
else
    # Default: scan all .sh files tracked in git
    mapfile -t FILES < <(find "${REPO_ROOT}" \
        -name "*.sh" \
        -not -path "*/.pixi/*" \
        -not -path "*/_precommit_test_*" \
        2>/dev/null | sort)
fi

for file in "${FILES[@]}"; do
    [[ ! -f "$file" ]] && continue
    [[ "$file" != *.sh ]] && continue

    FILES_CHECKED=$((FILES_CHECKED + 1))

    # For each line that expands AGAMEMNON_API_KEY, check if it is within a
    # set +x guard block. We track guard state by scanning the file line by line.
    # Single-quoted heredocs (<<'WORD') are skipped — they are not executed.
    inside_guard=0
    heredoc_delim=""
    lineno=0
    while IFS= read -r line; do
        lineno=$((lineno + 1))

        # Track single-quoted heredoc blocks: variables inside are not expanded.
        if [[ -n "$heredoc_delim" ]]; then
            if [[ "$line" == "$heredoc_delim" ]]; then
                heredoc_delim=""
            fi
            continue
        fi
        # Detect start of a single-quoted heredoc: <<'WORD' or <<"WORD" (double-quoted also suppresses expansion)
        if echo "$line" | grep -qE "<<['\"][A-Za-z_][A-Za-z_0-9]*['\"]"; then
            heredoc_delim="$(echo "$line" | grep -oE "['\"][A-Za-z_][A-Za-z_0-9]*['\"]" | tr -d "'\"")"
            continue
        fi

        # Detect start of xtrace guard: { set +x; } or bare set +x
        if echo "$line" | grep -qE '^\s*\{\s*set \+x\s*;\s*\}\s*(2>/dev/null)?$|^\s*set \+x\s*$'; then
            inside_guard=1
            continue
        fi

        # Detect end of xtrace guard: set -x (bare or inside if block)
        if echo "$line" | grep -qE '^\s*(if \[\[.*_had_xtrace.*\]\];\s*then\s*)?set -x\s*(;\s*fi\s*)?$'; then
            inside_guard=0
            continue
        fi

        # Check if this line expands AGAMEMNON_API_KEY (not escaped \$ references)
        if echo "$line" | grep -qE '[^\\]\$\{?AGAMEMNON_API_KEY\}?|^\$\{?AGAMEMNON_API_KEY\}?'; then
            # Skip pure comment lines
            if echo "$line" | grep -qE '^\s*#'; then
                continue
            fi
            # Skip suppressed lines (inline annotation)
            if echo "$line" | grep -q '# xtrace-lint: ok'; then
                continue
            fi
            # Skip variable assignment lines: AGAMEMNON_API_KEY="${AGAMEMNON_API_KEY:-}"
            # These normalise the variable and do not embed the value in HTTP headers.
            if echo "$line" | grep -qE '^\s*AGAMEMNON_API_KEY='; then
                continue
            fi

            if [[ $inside_guard -eq 0 ]]; then
                echo "ERROR: ${file}:${lineno}: AGAMEMNON_API_KEY expanded without xtrace guard."
                echo "       Wrap with: { set +x; } 2>/dev/null ... if [[ \$_had_xtrace -eq 1 ]]; then set -x; fi"
                echo "       To suppress: append  # xtrace-lint: ok  on the same line."
                VIOLATIONS=$((VIOLATIONS + 1))
            fi
        fi
    done < "$file"
done

if [[ $VIOLATIONS -gt 0 ]]; then
    echo ""
    echo "check-xtrace-guards: ${VIOLATIONS} violation(s) found in ${FILES_CHECKED} file(s)."
    echo "AGAMEMNON_API_KEY must only be expanded inside a set +x / set -x guard block."
    exit 1
fi

exit 0
