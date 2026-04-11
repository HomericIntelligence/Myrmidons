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
# Configuration
# =============================================================================

# Show effective configuration (merged from defaults, .myrmidons.yaml, .myrmidons.local.yaml, env)
config:
    #!/usr/bin/env bash
    set -euo pipefail
    source scripts/lib/config.sh
    show_config

# =============================================================================
# Observability
# =============================================================================

# Show desired vs actual state for all agents (or a specific host)
status HOST=host:
    AGAMEMNON_URL={{agamemnon_url}} bash scripts/status.sh {{HOST}}

# =============================================================================
# Planning
# =============================================================================

# Show field-level diff between desired YAML state and actual Agamemnon state
diff HOST=host:
    AGAMEMNON_URL={{agamemnon_url}} bash scripts/diff.sh {{HOST}}

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

# Reconcile and fail if any agent still drifts after apply
apply-verify HOST=host:
    AGAMEMNON_URL={{agamemnon_url}} bash scripts/apply.sh {{HOST}} --verify

# =============================================================================
# Rollback
# =============================================================================

# Restore agents to their state from the most recent pre-apply snapshot
rollback:
    AGAMEMNON_URL={{agamemnon_url}} bash scripts/rollback.sh

# List available snapshots
snapshots:
    @bash scripts/rollback.sh --list

# =============================================================================
# Bootstrap
# =============================================================================

# Export current Agamemnon agents to YAML (bootstrap — run once)
export HOST=host:
    AGAMEMNON_URL={{agamemnon_url}} bash scripts/export.sh {{HOST}}

# =============================================================================
# Validation
# =============================================================================

# Run shell (BATS) tests for apply.sh idempotency and convergence
test-shell:
    bats tests/shell/

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

# =============================================================================
# Scaffolding
# =============================================================================

# Scaffold a new agent YAML interactively (or pass flags for non-interactive mode)
# Examples:
#   just new-agent
#   just new-agent -- --name my-agent --host hermes --program claude-code \
#     --working-directory /home/mvillmow/MyProject --task-description "What it does"
#   just new-agent -- --non-interactive --name ci-agent --host hermes \
#     --program claude-code --working-directory /tmp --task-description "CI helper"
new-agent *ARGS:
    @bash scripts/new-agent.sh {{ARGS}}

# =============================================================================
# Hooks
# =============================================================================

# Install the pre-commit hook into .git/hooks/
install-hooks:
    cp hooks/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    @echo "pre-commit hook installed."
