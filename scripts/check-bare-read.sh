#!/usr/bin/env bash
# scripts/check-bare-read.sh — Lint guard: flag bare `read -r` without -t in scripts/
#
# Interactive yes/no prompts must use confirm_with_timeout() from scripts/lib/prompt.sh.
# Free-text data-entry reads (prompt_field, prompt_enum, tags) are intentionally
# bare and must carry a "# data-entry read — no timeout intentional" comment on
# the same line to be exempt.
#
# Exit codes:
#   0 — no violations found
#   1 — one or more violations found (bare read without -t and without exemption)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Files to check: all .sh files under scripts/, excluding prompt.sh itself
# (which contains the reference implementation).
mapfile -t FILES < <(
    find "${SCRIPT_DIR}" -maxdepth 2 -name '*.sh' \
        ! -path '*/lib/prompt.sh' \
        ! -path '*/check-bare-read.sh'
)

violations=0

for file in "${FILES[@]}"; do
    while IFS= read -r -d '' match; do
        lineno="${match%%:*}"
        line="${match#*:}"

        # Skip pipeline/loop reads: `while ... read`, `IFS= read`, etc.
        if [[ "$line" =~ while[[:space:]] ]] || [[ "$line" =~ \|[[:space:]]*read ]]; then
            continue
        fi

        # Skip lines that have a -t flag (already have timeout)
        if [[ "$line" =~ read[[:space:]]+-[a-zA-Z]*t ]]; then
            continue
        fi

        # Skip lines marked as intentional data-entry reads
        if [[ "$line" == *"# data-entry read — no timeout intentional"* ]]; then
            continue
        fi

        echo "${file}:${lineno}: bare 'read -r' without -t — use confirm_with_timeout() or add '# data-entry read — no timeout intentional'"
        violations=$((violations + 1))
    done < <(grep -nZ 'read -r' "$file" 2>/dev/null || true)
done

if [[ $violations -gt 0 ]]; then
    echo ""
    echo "Found ${violations} bare read(s). Interactive yes/no prompts must use confirm_with_timeout()."
    echo "See scripts/lib/prompt.sh for usage."
    exit 1
fi
