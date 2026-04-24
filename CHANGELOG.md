# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- CHANGELOG.md update validation in PR CI workflow — PRs must update CHANGELOG.md or include `[skip changelog]` to bypass (#126, #127)
- Doctor dependency check (`scripts/doctor.sh --skip-connectivity`) added to validate.yml CI (#244)

### Changed
- validate.yml lint job now uses pixi's shellcheck (via `pixi run --environment lint lint-shell`) instead of a manual curl install (#102)

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
