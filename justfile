# Myrmidons justfile — operational task runner
# Usage: just <recipe>
# Requires: just, yq, jq, curl (and a running ai-maestro)

# Default: show help
default:
    @just --list

# =============================================================================
# Variables
# =============================================================================

host := env_var_or_default("HOST", "hermes")
aim_host := env_var_or_default("AIM_HOST", "http://localhost:23000")

# =============================================================================
# Observability
# =============================================================================

# Show desired vs actual state for all agents (or a specific host)
status HOST=host:
    AIM_HOST={{aim_host}} bash scripts/status.sh {{HOST}}

# =============================================================================
# Planning
# =============================================================================

# Dry-run: show what apply would do (no changes made)
plan HOST=host:
    AIM_HOST={{aim_host}} bash scripts/apply.sh {{HOST}} --dry-run

# =============================================================================
# Apply
# =============================================================================

# Reconcile desired state → ai-maestro (creates/updates/wakes/hibernates)
apply HOST=host:
    AIM_HOST={{aim_host}} bash scripts/apply.sh {{HOST}}

# Apply with --prune (removes agents in ai-maestro that are not in YAML)
apply-prune HOST=host:
    AIM_HOST={{aim_host}} bash scripts/apply.sh {{HOST}} --prune

# =============================================================================
# Bootstrap
# =============================================================================

# Export current ai-maestro agents to YAML (Phase 1 bootstrap — run once)
export HOST=host:
    AIM_HOST={{aim_host}} bash scripts/export.sh {{HOST}}

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

# =============================================================================
# Hooks
# =============================================================================

# Install the pre-commit hook into .git/hooks/
install-hooks:
    cp hooks/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    @echo "pre-commit hook installed."
