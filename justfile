# Myrmidons justfile — operational task runner
# Usage: just <recipe>
# Requires: just, yq, jq, curl (and a running ProjectAgamemnon)

# Default: show help
default:
    @just --list

# =============================================================================
# Variables
# =============================================================================

host := env_var_or_default("HOST", "hermes")
agamemnon_url := env_var_or_default("AGAMEMNON_URL", "http://localhost:8080")

# =============================================================================
# Observability
# =============================================================================

# Show desired vs actual state for all agents (or a specific host)
status HOST=host:
    AGAMEMNON_URL={{agamemnon_url}} bash scripts/status.sh {{HOST}}

# Display the last reconciliation report (JSON)
report:
    #!/usr/bin/env bash
    set -euo pipefail
    report_file="reports/last-reconciliation.json"
    if [[ ! -f "$report_file" ]]; then
        echo "No reconciliation report found. Run 'just apply' first." >&2
        exit 1
    fi
    jq '.' "$report_file"

# =============================================================================
# Planning
# =============================================================================

# Dry-run: show what apply would do (no changes made)
plan HOST=host:
    AGAMEMNON_URL={{agamemnon_url}} bash scripts/apply.sh {{HOST}} --dry-run

# =============================================================================
# Apply
# =============================================================================

# Reconcile desired state → Agamemnon (creates/updates/starts/stops)
apply HOST=host:
    AGAMEMNON_URL={{agamemnon_url}} bash scripts/apply.sh {{HOST}}

# Apply with --prune (removes agents in Agamemnon that are not in YAML)
apply-prune HOST=host:
    AGAMEMNON_URL={{agamemnon_url}} bash scripts/apply.sh {{HOST}} --prune

# =============================================================================
# Bootstrap
# =============================================================================

# Export current Agamemnon agents to YAML (bootstrap — run once)
export HOST=host:
    AGAMEMNON_URL={{agamemnon_url}} bash scripts/export.sh {{HOST}}

# =============================================================================
# Validation
# =============================================================================

# Run all validation checks (YAML schemas + documentation drift)
validate: validate-schemas test-drift

# Validate all agent YAML files (schema check without committing)
validate-schemas:
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

# Check documentation files for overclaims about unimplemented features
test-drift:
    #!/usr/bin/env bash
    set -euo pipefail
    chmod +x tests/detect-doc-drift.sh
    ./tests/detect-doc-drift.sh

# =============================================================================
# Linting
# =============================================================================

# Run all linters via pre-commit (shellcheck, yamllint, schema validation)
lint:
    pre-commit run --all-files

# =============================================================================
# Hooks
# =============================================================================

# Install pre-commit framework hooks (recommended)
install-hooks:
    pre-commit install
    @echo "pre-commit hooks installed via pre-commit framework."

# Install the legacy pre-commit hook into .git/hooks/ (backward compatibility)
install-hooks-legacy:
    cp hooks/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    @echo "Legacy pre-commit hook installed."
