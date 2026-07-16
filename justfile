# Myrmidons justfile — dataset operational helpers
# Usage: just <recipe>
# Requires: just, yq, jq

# Default: show help
default:
    @just --list

# =============================================================================
# Validation
# =============================================================================

# Validate all agent YAML files (schema check)
validate:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v yq &>/dev/null; then
        echo "ERROR: yq not found. Install: https://github.com/mikefarah/yq" >&2
        exit 1
    fi
    errors=0
    while IFS= read -r file; do
        echo -n "  ${file}: "
        if ! yq eval '.' "$file" > /dev/null 2>&1; then
            echo "FAIL (invalid YAML)"
            errors=$((errors + 1))
            continue
        fi
        api_version="$(yq eval '.apiVersion // ""' "$file")"
        if [[ "$api_version" != "myrmidons/v1" ]]; then
            echo "FAIL (apiVersion: expected myrmidons/v1, got ${api_version})"
            errors=$((errors + 1))
            continue
        fi
        echo "ok"
    done < <(find agents -name "*.yaml" ! -path "*/_templates/*" 2>/dev/null)
    if [[ $errors -gt 0 ]]; then
        echo ""
        echo "Validation: ${errors} error(s)" >&2
        exit 1
    fi
    echo "All YAML files valid."
    echo ""
    echo "Checking name uniqueness..."
    pixi run lint-names
    echo ""
    echo "Running shellcheck..."
    pixi run lint-shell

# =============================================================================
# Packaging
# =============================================================================

# Build a versioned dataset snapshot archive into dist/
package:
    bash scripts/package-dataset.sh

# =============================================================================
# Testing & Linting
# =============================================================================

# Run all tests
test:
    bash tests/validate-schemas.sh

# Run shellcheck on all shell scripts
lint:
    shellcheck scripts/*.sh hooks/pre-commit tests/*.sh

# Run lint and test together
check: lint test

# =============================================================================
# Hooks
# =============================================================================

# Install all git hooks: copies the dangerous-flags hook AND registers the pre-commit framework
install-hooks:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v pixi &>/dev/null; then
        printf 'ERROR: pixi is not installed.\n'
        printf '  Install it: curl -fsSL https://pixi.sh/install.sh | bash\n'
        printf '  Then re-run: just install-hooks\n'
        printf '  See CONTRIBUTING.md for full setup instructions.\n'
        exit 1
    fi
    if ! pixi run --environment lint pre-commit --version &>/dev/null; then
        printf 'ERROR: pre-commit is not available in the pixi lint environment.\n'
        printf '  Run: pixi install --environment lint\n'
        printf '  Then re-run: just install-hooks\n'
        printf '  See CONTRIBUTING.md for full setup instructions.\n'
        exit 1
    fi
    cp hooks/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    pixi run --environment lint pre-commit install
    printf 'Hooks installed: dangerous-flags hook + pre-commit framework (.pre-commit-config.yaml).\n'

# Legacy: install only the dangerous-flags hook script (no pre-commit framework)
install-hooks-legacy:
    cp hooks/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    @echo "Legacy hook installed (dangerous-flags only, no pre-commit framework)."
