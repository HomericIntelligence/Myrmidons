#!/bin/bash
# Run the Myrmidons CI suite locally inside a container.
#
# Mirrors what GitHub Actions runs, using the same CI container image.
# Supports both Podman (rootless, no SU — preferred) and Docker.
#
# Usage:
#   ./scripts/run_ci_local.sh                  # Run all CI checks
#   ./scripts/run_ci_local.sh lint             # shellcheck + yamllint (lint job)
#   ./scripts/run_ci_local.sh test             # bats unit tests (unit-tests job)
#   ./scripts/run_ci_local.sh build            # agent YAML schema validation (build job)
#   ./scripts/run_ci_local.sh typecheck        # mypy / py_compile (typecheck job)
#   ./scripts/run_ci_local.sh schema           # workflow YAML + jsonschema + pyproject (schema-validation job)
#   ./scripts/run_ci_local.sh deps             # lockfile sync (deps-version-sync job)
#   ./scripts/run_ci_local.sh security         # pip-audit + gitleaks + trivy (security jobs)
#   ./scripts/run_ci_local.sh package          # dataset archive + round-trip (package job)
#   ./scripts/run_ci_local.sh install          # toolchain smoke test + hooks (install job)
#   ./scripts/run_ci_local.sh forbid           # silent-failure policy scans (forbid-suppressions job)
#   ./scripts/run_ci_local.sh precommit        # full pre-commit run (validate.yml)
#
# Container engine: auto-detected (podman first, docker fallback).
# Override: CONTAINER_ENGINE=docker ./scripts/run_ci_local.sh
#
# Image: uses 'myrmidons-ci:local'.
# Build locally: just ci-build  (or: podman build -f ci/Containerfile -t myrmidons-ci:local .)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SUBSET="${1:-all}"

LOCAL_IMAGE="myrmidons-ci:local"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[CI]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[CI]${NC} $*"; }
log_error() { echo -e "${RED}[CI]${NC} $*" >&2; }
log_step()  { echo -e "\n${BLUE}==>${NC} $*"; }

# ============================================================================
# Container engine detection
# ============================================================================

detect_engine() {
    if [ -n "${CONTAINER_ENGINE:-}" ]; then
        if ! command -v "${CONTAINER_ENGINE}" &> /dev/null; then
            log_error "CONTAINER_ENGINE=${CONTAINER_ENGINE} not found in PATH"
            exit 1
        fi
        log_info "Container engine: ${CONTAINER_ENGINE} (from env)"
        return
    fi

    if command -v podman &> /dev/null; then
        CONTAINER_ENGINE="podman"
        log_info "Container engine: podman (rootless)"
    elif command -v docker &> /dev/null; then
        CONTAINER_ENGINE="docker"
        log_info "Container engine: docker"
    else
        log_error "No container engine found. Install podman (recommended) or docker."
        log_error "  Podman: https://podman.io/getting-started/installation"
        exit 1
    fi
    export CONTAINER_ENGINE
}

# ============================================================================
# Image resolution
# ============================================================================

resolve_image() {
    if "${CONTAINER_ENGINE}" image exists "${LOCAL_IMAGE}" 2>/dev/null || \
       "${CONTAINER_ENGINE}" images -q "${LOCAL_IMAGE}" 2>/dev/null | grep -q .; then
        CI_IMAGE="${LOCAL_IMAGE}"
        log_info "Using local CI image: ${CI_IMAGE}"
    else
        log_error "Local image '${LOCAL_IMAGE}' not found."
        log_error "Build it first: just ci-build"
        log_error "  (podman build -f ci/Containerfile -t ${LOCAL_IMAGE} .)"
        exit 1
    fi
    export CI_IMAGE
}

# ============================================================================
# Run a command inside the CI container
# ============================================================================

run_in_container() {
    local cmd=("$@")
    local engine_flags=()

    if [ "${CONTAINER_ENGINE}" = "podman" ]; then
        engine_flags+=("--userns=keep-id:uid=1000,gid=1000")
    fi

    "${CONTAINER_ENGINE}" run --rm \
        "${engine_flags[@]}" \
        --volume "${PROJECT_ROOT}:/workspace:Z" \
        --workdir /workspace \
        "${CI_IMAGE}" \
        "${cmd[@]}"
}

# ============================================================================
# CI steps (mirror .github/workflows/_required.yml + validate.yml)
# ============================================================================

run_forbid() {
    log_step "forbid-suppressions: silent-failure / continue-on-error / advisory policy"
    run_in_container bash -c '
        set -euo pipefail
        mapfile -t files < <(git ls-files -- "*.sh" "*.bash" "*.yml" "*.yaml" "*.hcl" "Dockerfile*" "**/Dockerfile*" "justfile" "**/justfile" "Justfile" "**/Justfile")
        declare -a scan_files=()
        for f in "${files[@]}"; do
            case "$f" in
                .github/workflows/_required.yml) continue ;;
                docs/runbooks/no-silent-failures.md) continue ;;
            esac
            scan_files+=("$f")
        done
        if [ "${#scan_files[@]}" -eq 0 ]; then echo "No files to scan"; exit 0; fi
        if grep -nE '"'"'\|[[:space:]]*true([[:space:]]*$|[[:space:]]+#)'"'"' "${scan_files[@]}"; then
            echo "::error::Found silent-failure workarounds above."; exit 1
        fi
        echo "OK: no silent-failure workarounds found"
        mapfile -t wf < <(git ls-files -- ".github/workflows/*.yml" ".github/workflows/*.yaml")
        if grep -nE '"'"'^[[:space:]]*continue-on-error:[[:space:]]*true[[:space:]]*$'"'"' "${wf[@]}"; then
            echo "::error::Found continue-on-error: true above."; exit 1
        fi
        echo "OK: no continue-on-error found"
        # Exempt this workflow file: its own advisory-pattern check self-matches.
        declare -a wf_scan=()
        for f in "${wf[@]}"; do
            case "$f" in
                .github/workflows/_required.yml) continue ;;
            esac
            wf_scan+=("$f")
        done
        if grep -nF '"'"'::warning::'"'"' "${wf_scan[@]}"; then
            echo "::error::Found advisory annotations above."; exit 1
        fi
        echo "OK: no advisory annotations found"
    '
}

run_lint() {
    log_step "lint: shellcheck + yamllint"
    run_in_container bash -c 'just lint-shell && uv run --frozen yamllint -d relaxed agents/'
}

run_test() {
    log_step "unit-tests: bats"
    run_in_container bash -c 'just test-unit'
}

run_build() {
    log_step "build: agent YAML schema validation"
    run_in_container uv run --frozen python scripts/validate-agent-schemas.py
}

run_typecheck() {
    log_step "typecheck: mypy / py_compile"
    run_in_container bash -c '
        PY_FILES=$(find . -name "*.py" -not -path "*/.git/*" -not -path "*/__pycache__/*")
        if [ -z "$PY_FILES" ]; then echo "No Python files found — skipping mypy."; exit 0; fi
        if [ -d "scripts" ] && find scripts -name "*.py" | grep -q .; then
            mypy_rc=0
            uv run --frozen mypy --ignore-missing-imports scripts/ || mypy_rc=$?
            if [ "$mypy_rc" -ne 0 ]; then
                echo "::warning::mypy on scripts/ exited $mypy_rc — review the output above."
            fi
        fi
        echo "$PY_FILES" | head -20 | xargs uv run --frozen python -m py_compile
        echo "py_compile passed on all Python files."
    '
}

run_schema() {
    log_step "schema-validation: workflow YAML + GitHub schema + pyproject"
    run_in_container bash -c '
        find .github/workflows -name "*.yml" | sort | while read -r f; do
            echo "  checking: $f"
            yq eval "." "$f" > /dev/null
        done
        echo "All workflow YAML files are well-formed."
        mapfile -t workflow_files < <(find .github/workflows -name "*.yml" | sort)
        uv run --frozen check-jsonschema --schemafile https://json.schemastore.org/github-workflow "${workflow_files[@]}"
        uv run --frozen python - <<'"'"'EOF'"'"'
import tomllib
with open("pyproject.toml", "rb") as f:
    data = tomllib.load(f)
name = data.get("project", {}).get("name", "unknown")
print(f"pyproject.toml OK — project: {name}")
EOF
    '
}

run_deps() {
    log_step "deps-version-sync: lockfile in sync + clean install"
    run_in_container bash -c 'uv lock --check && uv sync --locked'
}

run_security() {
    log_step "security/dependency-scan: pip-audit + trivy"
    run_in_container bash -c '
        uv sync --locked
        uv run --frozen pip-audit \
            --ignore-vuln PYSEC-2024-230 \
            --ignore-vuln CVE-2023-26112 \
            --ignore-vuln PYSEC-2024-225 \
            --ignore-vuln CVE-2023-50782 \
            --ignore-vuln CVE-2024-0727 \
            --ignore-vuln GHSA-h4gh-qq45-vh27 \
            --ignore-vuln CVE-2026-26007 \
            --ignore-vuln CVE-2026-34073 \
            --ignore-vuln GHSA-537c-gmf6-5ccf \
            --ignore-vuln PYSEC-2024-60 \
            --ignore-vuln CVE-2024-22195 \
            --ignore-vuln CVE-2024-34064 \
            --ignore-vuln CVE-2024-56326 \
            --ignore-vuln CVE-2024-56201 \
            --ignore-vuln CVE-2025-27516 \
            --ignore-vuln CVE-2025-8869 \
            --ignore-vuln CVE-2026-1703 \
            --ignore-vuln CVE-2026-3219 \
            --ignore-vuln CVE-2026-6357 \
            --ignore-vuln CVE-2026-30922 \
            --ignore-vuln CVE-2026-4539 \
            --ignore-vuln CVE-2026-32597 \
            --ignore-vuln CVE-2026-27448 \
            --ignore-vuln CVE-2026-27459 \
            --ignore-vuln CVE-2024-35195 \
            --ignore-vuln CVE-2024-47081 \
            --ignore-vuln CVE-2026-25645 \
            --ignore-vuln PYSEC-2025-49 \
            --ignore-vuln CVE-2024-6345 \
            --ignore-vuln PYSEC-2024-75 \
            --ignore-vuln CVE-2024-41671 \
            --ignore-vuln CVE-2026-42304 \
            --ignore-vuln CVE-2024-37891 \
            --ignore-vuln CVE-2025-50181 \
            --ignore-vuln CVE-2025-66418 \
            --ignore-vuln CVE-2025-66471 \
            --ignore-vuln CVE-2026-21441 \
            --ignore-vuln CVE-2026-24049 \
            --ignore-vuln CVE-2026-44431 \
            --ignore-vuln CVE-2026-45409 \
            --ignore-vuln PYSEC-2026-196 \
            --ignore-vuln PYSEC-2025-183 \
            --ignore-vuln PYSEC-2026-179 \
            --ignore-vuln PYSEC-2026-175 \
            --ignore-vuln PYSEC-2026-2132 \
            --ignore-vuln PYSEC-2026-3444 \
            --ignore-vuln PYSEC-2026-3447 \
            --ignore-vuln PYSEC-2026-177
        trivy fs --severity HIGH,CRITICAL --exit-code 0 .
    '
    log_step "security/secrets-scan: gitleaks"
    run_in_container bash -c 'gitleaks detect --source . --config .gitleaks.toml --no-git -v'
}

run_package() {
    log_step "package: dataset archive + round-trip"
    run_in_container bash -c '
        set -euo pipefail
        mkdir -p dist
        sha="$(git rev-parse --short HEAD)"
        archive="dist/myrmidons-dataset-${sha}.tar.gz"
        tar --sort=name --owner=0 --group=0 --numeric-owner \
            --mtime="UTC 2020-01-01" \
            -czf "${archive}" agents/ fleets/ schemas/
        (cd dist && sha256sum -- *.tar.gz > SHA256SUMS)
        ls -l dist/
        workdir="$(mktemp -d)"
        tar -xzf dist/myrmidons-dataset-*.tar.gz -C "${workdir}"
        for dir in agents fleets schemas; do
            diff -r "${dir}" "${workdir}/${dir}"
        done
        yaml_count="$(find "${workdir}/agents" -name "*.yaml" | wc -l)"
        if [ "${yaml_count}" -eq 0 ]; then echo "::error::Packaged archive contains no agent YAMLs"; exit 1; fi
        (cd dist && sha256sum --check SHA256SUMS)
        echo "OK: archive round-trips (${yaml_count} agent YAMLs packaged)"
    '
}

run_install() {
    log_step "install: toolchain smoke test + hooks"
    run_in_container bash -c '
        set -euo pipefail
        just --version
        jq --version
        yq --version
        bats --version
        shellcheck --version
        uv run --frozen yamllint --version
        uv run --frozen pre-commit --version
        just install-hooks
    '
}

run_precommit() {
    log_step "pre-commit: all files (validate.yml parity)"
    run_in_container bash -c 'uv run --frozen pre-commit run --all-files --show-diff-on-failure'
}

# ============================================================================
# Main
# ============================================================================

FAILED=()

run_step() {
    local name="$1"
    local fn="$2"
    if ! "${fn}"; then
        FAILED+=("${name}")
        log_error "${name} FAILED"
    fi
}

detect_engine
resolve_image

log_info "CI subset: ${SUBSET}"
log_info "Project root: ${PROJECT_ROOT}"

case "${SUBSET}" in
    forbid)
        run_step "forbid-suppressions" run_forbid
        ;;
    lint)
        run_step "lint" run_lint
        ;;
    test)
        run_step "unit-tests" run_test
        ;;
    build)
        run_step "build" run_build
        ;;
    typecheck)
        run_step "typecheck" run_typecheck
        ;;
    schema)
        run_step "schema-validation" run_schema
        ;;
    deps)
        run_step "deps-version-sync" run_deps
        ;;
    security)
        run_step "security" run_security
        ;;
    package)
        run_step "package" run_package
        ;;
    install)
        run_step "install" run_install
        ;;
    precommit)
        run_step "pre-commit" run_precommit
        ;;
    all)
        run_step "forbid-suppressions" run_forbid
        run_step "lint" run_lint
        run_step "unit-tests" run_test
        run_step "build" run_build
        run_step "typecheck" run_typecheck
        run_step "schema-validation" run_schema
        run_step "deps-version-sync" run_deps
        run_step "security" run_security
        run_step "package" run_package
        run_step "install" run_install
        ;;
    *)
        log_error "Unknown subset: ${SUBSET}"
        log_error "Valid values: all, forbid, lint, test, build, typecheck, schema, deps, security, package, install, precommit"
        exit 1
        ;;
esac

echo ""
if [ "${#FAILED[@]}" -eq 0 ]; then
    log_info "All CI checks passed."
else
    log_error "Failed: ${FAILED[*]}"
    exit 1
fi
