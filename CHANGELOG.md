# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- CHANGELOG.md update validation in PR CI workflow — PRs must update CHANGELOG.md or include `[skip changelog]` to bypass (#126, #127)
- Doctor dependency check (`scripts/doctor.sh --skip-connectivity`) added to validate.yml CI (#244)
- `compute_drift` now accepts `owner`, `role`, and `deploy_type` parameters for deeper configuration drift detection (#330)
- pre-commit hook: dangerous-flags lint guard calls `check-dangerous-flags.sh` on staged agent/fleet YAMLs (#147)
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

[Unreleased]: https://github.com/HomericIntelligence/Myrmidons/compare/HEAD...HEAD
[0.3.0]: https://github.com/HomericIntelligence/Myrmidons/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/HomericIntelligence/Myrmidons/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/HomericIntelligence/Myrmidons/releases/tag/v0.1.0
