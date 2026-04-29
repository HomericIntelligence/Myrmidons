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

# Field-level diff: desired YAML vs actual Agamemnon state (optional --agent filter)
# Usage: just diff               — diff all agents
#        just diff hermes        — diff agents for a specific host
#        just diff "" my-agent   — diff a single agent across all hosts
#        just diff hermes my-agent — diff a single agent on a specific host
diff HOST="" AGENT="":
    #!/usr/bin/env bash
    set -euo pipefail
    args=()
    if [[ -n "{{HOST}}" ]]; then args+=({{HOST}}); fi
    if [[ -n "{{AGENT}}" ]]; then args+=(--agent "{{AGENT}}"); fi
    AGAMEMNON_URL={{agamemnon_url}} bash scripts/diff.sh "${args[@]+"${args[@]}"}"

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

# Retry: re-apply agents from .myrmidons/failed-agents.txt (issue #269)
retry HOST=host:
    AGAMEMNON_URL={{agamemnon_url}} bash scripts/apply.sh {{HOST}} --retry

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
# Testing & Linting
# =============================================================================

# Run all tests
test:
    bash tests/validate-schemas.sh

# Run shellcheck on all shell scripts
lint:
    shellcheck scripts/*.sh scripts/lib/*.sh hooks/pre-commit tests/*.sh

# Run lint and test together
check: lint test

# =============================================================================
# Hooks
# =============================================================================

# Install all git hooks: copies the dangerous-flags hook AND registers the pre-commit framework
install-hooks:
    cp hooks/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    pixi run pre-commit install
    @echo "Hooks installed: dangerous-flags hook + pre-commit framework (.pre-commit-config.yaml)."

# Legacy: install only the dangerous-flags hook script (no pre-commit framework)
install-hooks-legacy:
    cp hooks/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    @echo "Legacy hook installed (dangerous-flags only, no pre-commit framework)."
