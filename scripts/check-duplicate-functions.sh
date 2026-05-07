#!/usr/bin/env bash
# scripts/check-duplicate-functions.sh — lint guard for duplicate shell function definitions
#
# Scans shell scripts for function names defined more than once within the same file.
# This prevents the silent-shadowing pattern from issue #369 (dual verify_convergence).
#
# Suppression format (inline, on the duplicate definition line):
#   function_name() { # allow-duplicate-function: <justification>
#
# Usage:
#   ./scripts/check-duplicate-functions.sh                  # scan scripts/ directory
#   ./scripts/check-duplicate-functions.sh file1.sh ...     # scan specific files
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
    mapfile -t FILES < <(printf '%s\n' "$@")
else
    mapfile -t FILES < <(find "${REPO_ROOT}/scripts" "${REPO_ROOT}/hooks" -name "*.sh" | sort)
fi

for file in "${FILES[@]}"; do
    [[ ! -f "$file" ]] && continue
    FILES_CHECKED=$((FILES_CHECKED + 1))

    # Extract all function definition lines: lines matching NAME() or NAME ()
    # Capture line number and function name.
    declare -A seen_funcs
    declare -A seen_lines
    unset seen_funcs seen_lines
    declare -A seen_funcs
    declare -A seen_lines

    while IFS=':' read -r lineno content; do
        # Strip leading whitespace to handle indented functions
        stripped="${content#"${content%%[! ]*}"}"

        # Extract function name (handle both `name()` and `function name`)
        func_name=""
        if [[ "$stripped" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(\) ]]; then
            func_name="${BASH_REMATCH[1]}"
        elif [[ "$stripped" =~ ^function[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*(\(\))? ]]; then
            func_name="${BASH_REMATCH[1]}"
        fi

        [[ -z "$func_name" ]] && continue

        if [[ -n "${seen_funcs[$func_name]+_}" ]]; then
            # Check for suppression annotation on this line
            if echo "$content" | grep -q '# allow-duplicate-function:'; then
                continue
            fi
            echo "ERROR: ${file}:${lineno}: duplicate function definition '${func_name}' (first defined at line ${seen_lines[$func_name]})."
            echo "       To suppress: append  # allow-duplicate-function: <justification>  on the duplicate definition line."
            VIOLATIONS=$((VIOLATIONS + 1))
        else
            seen_funcs["$func_name"]=1
            seen_lines["$func_name"]="$lineno"
        fi
    done < <(grep -n '^\s*\(function \+\)\?[A-Za-z_][A-Za-z0-9_]*\s*()\|^\s*function \+[A-Za-z_][A-Za-z0-9_]*' "$file" 2>/dev/null || true)
done

if [[ $VIOLATIONS -gt 0 ]]; then
    echo ""
    echo "check-duplicate-functions: ${VIOLATIONS} violation(s) found in ${FILES_CHECKED} file(s)."
    echo "Remove the duplicate definition or add a # allow-duplicate-function: <justification> annotation."
    exit 1
fi

exit 0
