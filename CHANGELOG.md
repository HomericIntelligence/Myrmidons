# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- AGENTS.md: agent safety boundary document defining permitted tool use and authorization requirements (#385)
- ADR-008, ADR-009, ADR-010: architecture decision records for fleet-ref resolution, `compute_drift`, and schema versioning (#437)
- Agent manifests and fleet configs for Myrmidon swarm multi-agent reconciliation (#69, #22)
- README repo grade badge (B+) (#35)
- `plan.sh`: `--output json` flag emits machine-readable JSON summary to `reports/last-reconciliation.json` (#85a94a7)
- C++ hello-world example wired into build system (#445)
- CI: markdownlint, pixi, justfile, and symlink lint jobs (#364)
- CLAUDE.md: `--dangerously-skip-permissions` policy — prohibited by default, suppression annotation with justification required (#147)
- `pygrep` pre-commit hook `changelog-unreleased-url` catches broken `[Unreleased]` compare links in `CHANGELOG.md`, enforcing `compare/vX.Y.Z...HEAD` format and preventing the regression where both sides resolve to HEAD (#453)
- CI ↔ pre-commit parity architecture: `.pre-commit-config.yaml` is now the single source of truth for all linting; CI runs `pre-commit run --all-files` to eliminate drift
- actionlint pre-commit hook added (v1.7.7) so GitHub Actions workflow lint failures are caught locally before push
- gitleaks pre-commit hook added (v8.24.3, unlicensed binary mode) so secret scanning matches CI
- shellcheck pre-commit hook explicitly covers `*.bats` files (via `files:` pattern) to match `lint-shell.sh` scope
- yamllint scope broadened from `agents/+fleets/` to all `*.yaml` files across the repo
- `myrmidons-test-schema` local pre-commit hook validates YAML schemas locally (matches `validate` CI job)
- CLAUDE.md: new "CI ↔ pre-commit parity" Known Gotcha documents the invariant and rules

### Changed
- `validate.yml`: standalone `lint`, `pre-commit`, and `security` jobs collapsed into single `Pre-commit (parity)` job; `validate` and `doctor` jobs now depend on `pre-commit` instead of `lint`
- `_required.yml` `lint` job: replaced shellcheck+yamllint steps with `pre-commit run --all-files`
- `_required.yml` `security/secrets-scan`: replaced `gitleaks/gitleaks-action@v2` (requires paid license) with unlicensed gitleaks binary, matching `validate.yml` approach
- `_required.yml` `deps-version-sync`: replaced manual `actions/cache` block with `./.github/actions/setup-pixi` composite — fixes `pixi: command not found` error
- `lock-check.yml`: replaced manual `actions/cache` block with `./.github/actions/setup-pixi` composite — fixes `pixi: command not found` error
- `apply.yml`: apply job now skips (no-op) when `AGAMEMNON_URL` secret is not set, preventing permanent red CI on repos without a reachable Agamemnon endpoint
- `scripts/lint-shell.sh` and `pixi.toml` `lint-shell` task: extended `find` pattern to also match `*.bats` files, matching the pre-commit shellcheck hook
- Agent and fleet YAML `taskDescription`/`description` fields with lines >80 chars rewritten using YAML folded scalars (`>-`) to satisfy yamllint relaxed line-length rule

### Fixed
- `scripts/doctor.sh`: added `--skip-hooks` flag; CI doctor job now passes `--skip-connectivity --skip-hooks` since git hooks are not installed on fresh CI checkouts
- `_required.yml` trivy binary install: corrected version from non-existent `0.61.0` to `0.70.0`
- `pixi.lock` updated via `pixi update` to resolve CVEs in transitive dependencies (ncurses, pathspec, virtualenv, just)
- `_required.yml` SC2015 (shellcheck): `pip install --quiet pip-audit && pip-audit || true` split into separate `run:` lines to eliminate `A && B || C` anti-pattern
- `tests/unit/test_apply_yes.bats`: removed unused `SCRIPT_DIR` variable (SC2034)
- `tests/unit/test_doctor.bats`: added `# shellcheck disable=SC2120` to `_run_doctor` which forwards optional extra args no current caller passes

- CHANGELOG.md update validation in PR CI workflow — PRs must update CHANGELOG.md or include `[skip changelog]` to bypass (#126, #127)
- Doctor dependency check (`scripts/doctor.sh --skip-connectivity`) added to validate.yml CI (#244)
- `compute_drift` now accepts `owner`, `role`, and `deploy_type` parameters for deeper configuration drift detection (#330)
- `scripts/check-dangerous-flags.sh`: dangerous-flags lint guard scans agent/fleet YAMLs for unsuppressed `--dangerously-skip-permissions`; integrated as a pre-commit hook on staged files and run in CI on all agent/fleet YAMLs on every PR (#147, #382)
- `apply.sh`: lock file support via `AIM_LOCK_FILE` / `AIM_LOCK_TIMEOUT` prevents concurrent reconcile runs (#54)
- `apply.sh`: interactive confirmation prompt for destructive operations; `--yes`/`-y` skips it in CI (#48)
- `apply.sh`: `verify_convergence` re-checks all modified agents after apply to detect drift (#41)
- `apply.sh`: `--fail-fast` flag aborts on first agent error; `--retry-file` allows custom retry file path (#268)
- `apply.sh`: `--retry` now clears successfully retried entries from `failed-agents.txt` (#269)
- `export.sh`: `check_jq()` now also validates `yq` is present, matching `reconcile.sh` dependency checks (#78)
- Multi-platform pixi support: `osx-64`, `linux-aarch64` added to `pixi.toml` platforms (#320)
- `just install-hooks` added to CLAUDE.md Quick Start section (#145)
- bats tests for `--yes` confirmation flag (`test_apply_yes.bats`) and doctor command (`test_doctor.bats`) (#240, #242)

### Changed
- validate.yml lint job now uses pixi's shellcheck (via `pixi run --environment lint lint-shell`) instead of a manual curl install (#102)
- `apply.sh --dry-run`: forwards `--prune` to `plan.sh` so prune intent is visible in dry-run output (#69, #71)
- gitleaks secret scanning: migrated from `gitleaks-action@v2` (paid license) to free CLI install (#263)
- pixi bumped to 0.67.2; bats-core made platform-specific to fix linux-aarch64 solve failure

### Security
- gitleaks secret scan is now blocking: removed `continue-on-error: true` from validate.yml security job so secret detection failures fail the PR; dropped `--no-git` so git history is also scanned; added `--config .gitleaks.toml` to use the existing allowlist for known false positives (#375)

### Fixed
- pre-commit hook: `REPO_ROOT` now uses `git rev-parse --show-toplevel` so the hook resolves the correct repo root when installed as `.git/hooks/pre-commit` (#330)
- pre-commit hook: `NAME_LIST` pipeline guarded with `|| true` to prevent `set -o pipefail` from aborting the hook when `yq` returns non-zero on an unstaged file (#330)
- Unit test ShellCheck violations resolved: SC2314, SC2315, SC2034, SC2088, SC2155, SC2164, SC2188 (#330)
- `test_export_status.bats`: UNCHANGED drift test now passes correct `owner`/`role` in mock response to match YAML values (#330)
- `apply.sh`: CREATE error count no longer double-incremented on failure; yaml paths stored in retry file (#98)
- `reconcile.sh`: `build_create_json` now includes `model` and `deployment.type` fields in CREATE body
- `reconcile.sh`: fleet ref error message restored to include `not found` for test compatibility (#332)
- `export.sh` / `apply.sh`: all `jq --arg label` renamed to `--arg lbl` to avoid jq 1.6 reserved-word breakage (#53)
- `scripts/apply.sh` marked executable in git index (was stored as `100644`, causing CI test failures)
- ShellCheck: all scripts pass `shellcheck 0.10.0` cleanly; pinned in `pixi.toml` (#187, #211)

## [0.3.0] - 2026-04-05

### Added
- Multi-repo Myrmidon agents and fleet config (issue #8)

## [0.2.0] - 2026-04-03

### Added
- LICENSE (Apache 2.0)
- CONTRIBUTING.md with coding standards and PR process
- SECURITY.md with vulnerability disclosure policy
- CODE_OF_CONDUCT.md
- C++20 hello-world pull consumer worker
- Hello-world Myrmidon pull-based worker
- Hephaestus@ProjectHephaestus plugin

### Changed
- CI apply workflow switched from self-hosted to ubuntu-latest

### Removed
- Python hello-world files (replaced by C++ implementation)
- `aim_*` backward-compatibility alias functions

### Fixed
- stdout unbuffering for container logging

## [0.1.0] - 2026-03-28

### Added
- Migrated from ai-maestro to ProjectAgamemnon (ADR-006)
- Initial repo scaffolding: justfile, pixi.toml, README, scripts
- `.gitignore` covering ProjectMnemosyne/ and build/

[Unreleased]: https://github.com/HomericIntelligence/Myrmidons/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/HomericIntelligence/Myrmidons/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/HomericIntelligence/Myrmidons/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/HomericIntelligence/Myrmidons/releases/tag/v0.1.0
