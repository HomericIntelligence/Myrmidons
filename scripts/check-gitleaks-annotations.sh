#!/usr/bin/env bash
# scripts/check-gitleaks-annotations.sh — lint guard for .gitleaks.toml allowlist entries
#
# Enforces the project policy that every regex / path / commit / fingerprint
# entry inside a `[allowlist]` block of .gitleaks.toml carries an inline
# justification annotation:
#
#   '''your-placeholder-token''',   # gitleaks-allowlist: <justification>
#
# Entries without a non-empty justification cause this script to exit non-zero
# and print the offending line numbers.
#
# Usage:
#   ./scripts/check-gitleaks-annotations.sh                  # lint <repo>/.gitleaks.toml
#   ./scripts/check-gitleaks-annotations.sh path/to/.gitleaks.toml ...
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
    FILES=("${REPO_ROOT}/.gitleaks.toml")
fi

# Recognises an entry line that requires a justification annotation.
#
# Entries inside `regexes = [ ... ]`, `paths = [ ... ]`, `commits = [ ... ]`,
# or `fingerprints = [ ... ]` arrays look like one of:
#
#     '''regex-or-path''',
#     '''regex-or-path'''
#     "double-quoted-value",
#     "double-quoted-value"
#     abcdef1234567890,                   # 40-char SHA commit hash
#     "abcdef..:rule-id:path",            # gitleaks fingerprint string
#
# The conservative trigger: any non-blank, non-comment, non-bracket, non-header,
# non-`key = value` line inside an [allowlist] section is treated as a data
# entry that must carry an annotation.
_is_entry_line() {
    local content="$1"
    local trimmed="${content#"${content%%[![:space:]]*}"}"
    [[ -z "$trimmed" ]] && return 1
    [[ "$trimmed" == "#"* ]] && return 1
    [[ "$trimmed" == "["* ]] && return 1
    [[ "$trimmed" == "]"* ]] && return 1
    # Skip key = value assignments (e.g. `description = "..."`, `regexes = [`).
    if [[ "$trimmed" =~ ^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*= ]]; then
        return 1
    fi
    return 0
}

for file in "${FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "ERROR: ${file}: file not found"
        VIOLATIONS=$((VIOLATIONS + 1))
        continue
    fi

    FILES_CHECKED=$((FILES_CHECKED + 1))

    in_allowlist=0
    lineno=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))

        # Track which TOML section we're in. A line like `[allowlist]` or
        # `[[allowlist]]` enters; any other top-level `[section]` exits.
        if [[ "$line" =~ ^[[:space:]]*\[\[?allowlist(\..*)?\]?\][[:space:]]*$ ]]; then
            in_allowlist=1
            continue
        elif [[ "$line" =~ ^[[:space:]]*\[ ]]; then
            in_allowlist=0
            continue
        fi

        [[ $in_allowlist -eq 1 ]] || continue
        _is_entry_line "$line" || continue

        # Require `# gitleaks-allowlist: <non-empty>` on the same line.
        if [[ "$line" =~ \#[[:space:]]*gitleaks-allowlist:[[:space:]]*([^[:space:]].*)?$ ]]; then
            justification="${BASH_REMATCH[1]:-}"
            justification="${justification%"${justification##*[![:space:]]}"}"
            if [[ -z "$justification" ]]; then
                echo "ERROR: ${file}:${lineno}: empty gitleaks-allowlist justification."
                echo "       Expected:  # gitleaks-allowlist: <non-empty justification>"
                echo "       Line:      ${line}"
                VIOLATIONS=$((VIOLATIONS + 1))
            fi
        else
            echo "ERROR: ${file}:${lineno}: allowlist entry missing # gitleaks-allowlist: annotation."
            echo "       Expected suffix:  # gitleaks-allowlist: <justification>"
            echo "       Line:             ${line}"
            VIOLATIONS=$((VIOLATIONS + 1))
        fi
    done < "$file"
done

if [[ $VIOLATIONS -gt 0 ]]; then
    echo ""
    echo "check-gitleaks-annotations: ${VIOLATIONS} violation(s) found in ${FILES_CHECKED} file(s)."
    echo "Add '# gitleaks-allowlist: <justification>' to each allowlist entry in .gitleaks.toml."
    exit 1
fi

exit 0
