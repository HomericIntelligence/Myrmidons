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

# Show desired vs actual state for all agents (or a specific host); pass fleet="" to filter by fleet
status HOST=host fleet="":
    #!/usr/bin/env bash
    set -euo pipefail
    args=({{HOST}})
    if [[ -n "{{fleet}}" ]]; then args+=(--fleet "{{fleet}}"); fi
    AGAMEMNON_URL={{agamemnon_url}} bash scripts/status.sh "${args[@]}"

# Show desired vs actual state for a named fleet
status-fleet FLEET:
    AGAMEMNON_URL={{agamemnon_url}} bash scripts/status.sh --fleet {{FLEET}}

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

# Dry-run: show what apply would do (no changes made); pass fleet="<name>" to target a fleet
plan HOST=host fleet="":
    #!/usr/bin/env bash
    set -euo pipefail
    args=({{HOST}} --dry-run)
    if [[ -n "{{fleet}}" ]]; then args+=(--fleet "{{fleet}}"); fi
    AGAMEMNON_URL={{agamemnon_url}} bash scripts/apply.sh "${args[@]}"

# =============================================================================
# Apply
# =============================================================================

# Reconcile desired state → Agamemnon (creates/updates/starts/stops); pass fleet="<name>" to target a fleet
apply HOST=host fleet="":
    #!/usr/bin/env bash
    set -euo pipefail
    args=({{HOST}})
    if [[ -n "{{fleet}}" ]]; then args+=(--fleet "{{fleet}}"); fi
    AGAMEMNON_URL={{agamemnon_url}} bash scripts/apply.sh "${args[@]}"

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

# Validate all agent YAML files (schema check without committing)
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
# Testing
# =============================================================================

# Run all tests (unit + integration) using bats-core
test:
    @echo "Running unit tests..."
    bats tests/unit/
    @echo ""
    @echo "Running integration tests..."
    bats tests/integration/

# Run only unit tests
test-unit:
    bats tests/unit/

# Run only integration tests
test-integration:
    bats tests/integration/

# =============================================================================
# Hooks
# =============================================================================

# Install the pre-commit hook into .git/hooks/
install-hooks:
    cp hooks/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    @echo "pre-commit hook installed."
