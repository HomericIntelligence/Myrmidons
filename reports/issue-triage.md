# Issue Triage Report
Generated: 2026-04-23 22:38:01 UTC
Total open issues: 118

## Summary
- ALREADY-DONE: 3
- DUPLICATE: 3
- EASY: 9
- MEDIUM: 106
- HARD: 2

## Classification Table

| # | Title | Difficulty | Already Done? | Duplicate Of | Files Touched | Notes |
|---|-------|-----------|--------------|-------------|---------------|-------|
| 275 | Pin gitleaks to a verified SHA256 checksum in secrets-scan j... | EASY | No | — | .github/workflows/validate.yml | — |
| 271 | status.sh report_unmanaged still duplicates name-collection ... | EASY | No | — | scripts/status.sh, scripts/lib/reconcile.sh | — |
| 269 | Clear failed-agents.txt when --retry succeeds for a subset | EASY | No | — | scripts/apply.sh | — |
| 261 | Fix jq reserved keyword 'label' in export.sh and plan.sh | EASY | No | — | scripts/export.sh, scripts/plan.sh | — |
| 259 | Fix jq 1.6 reserved-word breakage in plan.sh | EASY | No | 261 | scripts/plan.sh | Both fix jq reserved keyword "label" issue in different scripts |
| 107 | validate-schemas.sh still reads working tree (not staged con... | EASY | No | — | scripts/validate-schemas.sh | — |
| 103 | Add curl to pixi.toml or document it as a system dependency | EASY | No | — | pixi.toml, README.md | — |
| 100 | tests/test-apply-cache.sh requires bash 4+ (mapfile, local -... | EASY | No | — | tests/test-apply-cache.sh | — |
| 30 | [Audit] S15 Compliance: No LICENSE file -- code is not legal... | EASY | YES | — |  | LICENSE file exists |
| 273 | plan.sh shadowing risk: report_unmanaged name collision with... | MEDIUM | No | — | scripts/lib/reconcile.sh, scripts/plan.sh | — |
| 268 | apply.sh --retry does not pass --fail-fast through | MEDIUM | No | — | scripts/apply.sh | — |
| 266 | verify_convergence does not handle agents discovered by --pr... | MEDIUM | No | — | scripts/lib/reconcile.sh | — |
| 265 | Mock curl does not handle --max-time flag without a space | MEDIUM | No | — | tests/test-api-retry.sh | — |
| 263 | Add convergence CI step: run apply-verify on merge to main | MEDIUM | No | — | .github/workflows/, scripts/apply.sh | — |
| 262 | grep -P (PCRE) may not be available on all platforms | MEDIUM | No | — | scripts/export.sh, scripts/plan.sh (+1) | — |
| 252 | Enforce naming convention in scripts/export.sh | MEDIUM | No | — | scripts/export.sh | — |
| 244 | Add doctor check to CI validate workflow | MEDIUM | No | — | .github/workflows/validate.yml, scripts/doctor.sh | — |
| 242 | Add automated tests for scripts/doctor.sh | MEDIUM | No | — | tests/ | — |
| 240 | Add tests for confirmation prompt and --yes flag behavior | MEDIUM | No | — | tests/, scripts/apply.sh | — |
| 235 | Add schema validation for .myrmidons.yaml in validate/pre-co... | MEDIUM | No | — | .github/workflows/, schemas/ (+1) | — |
| 234 | Source config.sh in apply.sh/plan.sh/status.sh for auto-conf... | MEDIUM | No | — | scripts/apply.sh, scripts/plan.sh (+2) | — |
| 233 | get_unmanaged_agents spawns yq once per YAML file — optimize... | MEDIUM | No | — | scripts/lib/reconcile.sh | — |
| 228 | Snapshot files should record the apply context (user, branch... | MEDIUM | No | — | scripts/apply.sh, scripts/lib/report.sh | — |
| 227 | Add integration test for full apply → rollback round-trip | MEDIUM | No | — | tests/, scripts/rollback.sh | — |
| 225 | Rollback should snapshot before restoring (chain safety) | MEDIUM | No | — | scripts/rollback.sh, scripts/lib/report.sh | — |
| 223 | Document AGAMEMNON_API_KEY in validate.yml workflow | MEDIUM | No | — | .github/workflows/apply.yml | — |
| 215 | Add shellcheck to pre-commit hook for instant local feedback | MEDIUM | No | — | .pre-commit-config.yaml, hooks/ | — |
| 211 | Shellcheck: verify all scripts pass before CI enforces it | MEDIUM | No | — | scripts/, .github/workflows/ | — |
| 210 | bats tests skip sleep in retry tests — add timing assertion | MEDIUM | No | — | tests/test-api-retry.sh | — |
| 206 | resolve_fleet: bad ref path gives confusing error mid-loop | MEDIUM | No | — | scripts/lib/reconcile.sh | — |
| 205 | validate-schemas.sh does not validate inline agents in Fleet... | MEDIUM | No | — | scripts/validate-schemas.sh, tests/ | — |
| 202 | workingDirectory check skips Fleet inline agents | MEDIUM | No | — | scripts/validate-schemas.sh | — |
| 201 | Extend Fleet validation with per-member field checks | MEDIUM | No | — | schemas/, scripts/validate-schemas.sh | — |
| 200 | Add name uniqueness check to pre-commit hook | MEDIUM | No | — | hooks/pre-commit | — |
| 199 | Add shell-level tests for diff.sh with a mock Agamemnon serv... | MEDIUM | No | — | tests/, scripts/diff.sh | — |
| 198 | reconcile.sh: compute_drift does not pass tags CSV to compar... | MEDIUM | No | — | scripts/lib/reconcile.sh | — |
| 197 | diff.sh: handle CREATE case with field preview (not just a b... | MEDIUM | No | — | scripts/diff.sh | — |
| 196 | diff.sh: add --agent filter support to justfile recipe | MEDIUM | No | — | justfile, scripts/diff.sh | — |
| 192 | Mock server does not support per-route responses in unit tes... | MEDIUM | No | — | tests/, lib/ | — |
| 191 | Add test coverage for export.sh and status.sh | MEDIUM | No | — | tests/ | — |
| 190 | Add tests for apply.sh and plan.sh script entry points | MEDIUM | No | — | tests/ | — |
| 189 | Pin pre-commit hook revisions to specific SHAs for reproduci... | MEDIUM | No | — | .pre-commit-config.yaml | — |
| 188 | Add CI job to run `pre-commit run --all-files` on PRs | MEDIUM | No | — | .github/workflows/ | — |
| 187 | Fix shellcheck SC2034/SC2086 warnings in existing scripts | MEDIUM | No | — | scripts/, scripts/lib/ | — |
| 183 | Add integration test for --output json end-to-end with mock ... | MEDIUM | No | — | tests/, scripts/export.sh | — |
| 181 | Webhook delivery should report success/failure in the JSON s... | MEDIUM | No | — | scripts/lib/report.sh | — |
| 180 | report_save should rotate/append rather than overwrite | MEDIUM | No | — | scripts/lib/report.sh | — |
| 179 | Add --output json flag to plan.sh for dry-run JSON reports | MEDIUM | No | — | scripts/plan.sh | — |
| 177 | Fleet schema ref pattern is too restrictive for real agent n... | MEDIUM | No | — | schemas/, README.md | — |
| 174 | status.sh table output is not structured-log-aware | MEDIUM | No | — | scripts/status.sh, scripts/lib/log.sh | — |
| 168 | Warn when mTLS key/cert are specified without each other | MEDIUM | No | — | scripts/lib/api.sh | — |
| 167 | Validate TLS file paths at source time in api.sh | MEDIUM | No | — | scripts/lib/api.sh | — |
| 164 | apply.sh retry pass stores agent names, not yaml_file paths | MEDIUM | No | — | scripts/apply.sh | — |
| 160 | Add --fleet support to justfile recipes | MEDIUM | No | — | justfile, scripts/ | — |
| 159 | handle_unmanaged / report_unmanaged scope too broad when --f... | MEDIUM | No | — | scripts/apply.sh, scripts/plan.sh | — |
| 158 | resolve_fleet_files leaks temp files on error exit | MEDIUM | No | — | scripts/lib/reconcile.sh | — |
| 157 | Fleet ref resolution ignores host filter when --fleet and ho... | MEDIUM | No | — | scripts/lib/reconcile.sh | — |
| 154 | Assign existing open issues to Phase 1 or Phase 2 milestones | MEDIUM | No | — | .github/, issues/ | — |
| 153 | Convert issue templates from Markdown to YAML forms | MEDIUM | No | — | .github/ | — |
| 152 | Apply kind/severity labels to existing audit issues | MEDIUM | No | — | .github/ | — |
| 150 | Validate metadata.host in agent YAML files during schema che... | MEDIUM | No | — | schemas/, scripts/ | — |
| 149 | Add host validation to apply.sh and plan.sh parse_args() | MEDIUM | No | — | scripts/apply.sh, scripts/plan.sh | — |
| 147 | Add test coverage for pre-commit hook dangerous-flags integr... | MEDIUM | No | — | tests/, .pre-commit-config.yaml | — |
| 146 | Add `just test` invocation to the pre-commit hook | MEDIUM | No | — | hooks/pre-commit | — |
| 145 | Add pre-commit hook install step to README / Quick start | MEDIUM | No | — | README.md, CONTRIBUTING.md | — |
| 144 | Shellcheck: verify all scripts pass before CI enforces it | MEDIUM | No | 211 | scripts/, .github/workflows/ | Both address same shellcheck CI enforcement goal |
| 143 | Extend check-dangerous-flags.sh to scan .yml extensions too | MEDIUM | No | — | scripts/check-dangerous-flags.sh | — |
| 142 | Fix: git commit on 29-auto-impl reports already-committed SH... | MEDIUM | No | — | scripts/, .github/workflows/ | — |
| 139 | actionlint ignores shellcheck errors in run: steps by defaul... | MEDIUM | No | — | .github/workflows/ | — |
| 136 | Pin shellcheck version in CI for reproducible lint results | MEDIUM | No | — | .github/workflows/, .shellcheckrc | — |
| 135 | Add multi-platform support to pixi.toml (linux-aarch64, osx-... | MEDIUM | No | — | pixi.toml | — |
| 134 | Add pixi to PATH in CI so `just`/`jq` are available to scrip... | MEDIUM | No | — | .github/workflows/ | — |
| 133 | Pin yq version in CI workflows (currently uses latest in app... | MEDIUM | No | — | .github/workflows/apply.yml | — |
| 130 | Handle empty yaml_files array in report_unmanaged gracefully | MEDIUM | No | — | scripts/lib/reconcile.sh | — |
| 129 | Add tests for report_unmanaged in reconcile.sh | MEDIUM | No | — | tests/ | — |
| 127 | Add CHANGELOG.md validation to PR CI workflow | MEDIUM | No | — | .github/workflows/, CHANGELOG.md | — |
| 126 | Automate CHANGELOG.md updates via conventional commits CI | MEDIUM | No | — | CHANGELOG.md | — |
| 124 | pixi.toml: yq unavailable on conda-forge for linux-64 | MEDIUM | No | — | pixi.toml | — |
| 123 | Pre-commit hook should run validate-fleet-refs.sh on fleet c... | MEDIUM | No | — | hooks/pre-commit | — |
| 120 | Integration test: verify apply.sh aborts on malicious AGAMEM... | MEDIUM | No | — | tests/, scripts/apply.sh | — |
| 119 | validate-fleet-refs.sh: support inline agents in fleet specs | MEDIUM | No | — | scripts/validate-fleet-refs.sh, tests/ | — |
| 118 | Validate AGAMEMNON_URL in all entry-point scripts, not just ... | MEDIUM | No | — | scripts/apply.sh, scripts/plan.sh (+2) | — |
| 117 | Add shell-level tests for _agamemnon_curl cleanup guarantees | MEDIUM | No | — | tests/, scripts/lib/api.sh | — |
| 116 | agamemnon_check_connection has no trap and could leave curl ... | MEDIUM | No | — | scripts/lib/api.sh | — |
| 114 | status.sh makes N extra jq calls to look up status of unmana... | MEDIUM | No | — | scripts/status.sh | — |
| 113 | Add bats tests for get_unmanaged_names in reconcile.sh | MEDIUM | No | — | tests/, scripts/lib/reconcile.sh | — |
| 108 | Add shell-based tests for pre-commit hook staged-vs-working-... | MEDIUM | No | — | tests/, hooks/ | — |
| 102 | Switch CI workflows from manual yq install to pixi install | MEDIUM | No | — | .github/workflows/, README.md | — |
| 101 | Add osx-arm64 and osx-64 platforms to pixi.toml | MEDIUM | No | — | pixi.toml | — |
| 99 | Add shell-level tests for apply.sh UPDATE patch body | MEDIUM | No | — | tests/, scripts/apply.sh | — |
| 98 | CREATE error path still increments ERRORS twice | MEDIUM | No | — | scripts/apply.sh, tests/ | — |
| 97 | plan.sh does not show owner/role drift in dry-run output | MEDIUM | No | — | scripts/plan.sh, scripts/lib/reconcile.sh | — |
| 96 | apply.sh has no --dry-run path for the cache optimization co... | MEDIUM | No | — | scripts/apply.sh, tests/ | — |
| 95 | compute_drift() does not check owner or role for drift | MEDIUM | No | — | scripts/lib/reconcile.sh | — |
| 87 | Add integration smoke test for compute_drift new fields | MEDIUM | No | — | tests/, scripts/lib/reconcile.sh | — |
| 86 | status.sh silently drops tags drift detection | MEDIUM | No | — | scripts/status.sh, scripts/lib/reconcile.sh | — |
| 85 | build_create_json() omits model and deployment.type on CREAT... | MEDIUM | No | — | scripts/apply.sh, scripts/lib/reconcile.sh | — |
| 83 | Validate workflow YAML in CI (yq lint step) | MEDIUM | No | — | .github/workflows/, scripts/ | — |
| 81 | Add nomad as valid deployment type when Nomad work begins | MEDIUM | No | — | schemas/, README.md | — |
| 78 | check_deps in reconcile.sh does not check for yq in export.s... | MEDIUM | No | — | scripts/lib/reconcile.sh | — |
| 75 | Add dependency checks to validate.yml as well | MEDIUM | No | — | .github/workflows/ | — |
| 74 | Pin jq version in apply.yml for full reproducibility | MEDIUM | No | — | .github/workflows/apply.yml | — |
| 71 | apply.sh --dry-run --prune silently drops --prune intent | MEDIUM | No | — | scripts/apply.sh, scripts/plan.sh | — |
| 70 | plan.sh silently ignores unknown args instead of erroring | MEDIUM | No | — | scripts/plan.sh | — |
| 69 | apply.sh --dry-run does not pass --prune context to plan.sh | MEDIUM | No | — | scripts/apply.sh, scripts/plan.sh | — |
| 68 | plan.sh should reject unknown flags explicitly | MEDIUM | No | 70 | scripts/plan.sh | Both about plan.sh argument validation and error handling |
| 56 | [Improvement] Add error handling for partial apply failures ... | MEDIUM | No | — | scripts/apply.sh, scripts/lib/ | — |
| 55 | [Improvement] Add agent YAML file naming convention enforcem... | MEDIUM | No | — | scripts/export.sh | — |
| 54 | [Improvement] Add lock file support to prevent concurrent ap... | MEDIUM | No | — | scripts/apply.sh, scripts/lib/ | — |
| 53 | [Improvement] Sanitize YAML-derived values before embedding ... | MEDIUM | No | — | scripts/apply.sh, scripts/lib/ | — |
| 51 | [Improvement] Extract report_unmanaged into reconcile.sh to ... | MEDIUM | YES | — | scripts/lib/reconcile.sh, scripts/plan.sh (+1) | report_unmanaged exported from reconcile.sh |
| 50 | [Improvement] Add health check and connectivity test command... | MEDIUM | YES | — | scripts/doctor.sh, justfile | doctor.sh exists and callable |
| 48 | [Improvement] Add dry-run mode indicator and confirmation pr... | MEDIUM | No | — | scripts/apply.sh | — |
| 41 | [Improvement] Add idempotency guards and convergence verific... | MEDIUM | No | — | scripts/apply.sh, scripts/lib/ | — |
| 36 | Add TLS/HTTPS support for Agamemnon API connections | MEDIUM | No | — | scripts/lib/api.sh | — |
| 8 | Fleet YAML files have no apply/plan support — scripts only p... | MEDIUM | No | — | scripts/apply.sh, scripts/plan.sh (+1) | — |
| 35 | [Audit] Myrmidons -- Overall Grade: D- (62%) | HARD | No | — | .github/, docs/ (+1) | — |
| 29 | [Audit] S13 DX: No .editorconfig, no shellcheck CI, no just ... | HARD | No | — | .editorconfig, .github/workflows/ (+2) | — |

## WATCH Files (touched by 2+ issues)

Files where multiple issues make changes — agents must be serialized on these files to avoid merge conflicts:

- `scripts/apply.sh`: issues #8, #41, #48, #53, #54, #56, #69, #71, #85, #96, #98, #99, #118, #120, #149, #159, #164, #228, #234, #240, #263, #268, #269
- `tests/`: issues #87, #96, #98, #99, #108, #113, #117, #119, #120, #129, #147, #183, #190, #191, #192, #199, #205, #227, #235, #240, #242
- `scripts/lib/reconcile.sh`: issues #51, #78, #85, #86, #87, #95, #97, #113, #130, #157, #158, #198, #206, #233, #266, #271, #273
- `scripts/plan.sh`: issues #8, #51, #68, #69, #70, #71, #97, #118, #149, #159, #179, #234, #259, #261, #262, #273
- `.github/workflows/`: issues #29, #75, #83, #102, #127, #134, #136, #139, #142, #144, #188, #211, #235, #263
- `scripts/status.sh`: issues #51, #86, #114, #118, #174, #234, #262, #271
- `scripts/`: issues #83, #142, #144, #150, #160, #187, #211
- `scripts/export.sh`: issues #55, #118, #183, #252, #261, #262
- `schemas/`: issues #8, #81, #150, #177, #201, #235
- `README.md`: issues #35, #81, #102, #103, #145, #177
- `scripts/lib/`: issues #41, #53, #54, #56, #187
- `scripts/lib/api.sh`: issues #36, #116, #117, #167, #168
- `scripts/lib/report.sh`: issues #180, #181, #225, #228
- `scripts/validate-schemas.sh`: issues #107, #201, #202, #205
- `hooks/pre-commit`: issues #29, #123, #146, #200
- `justfile`: issues #29, #50, #160, #196
- `.github/`: issues #35, #152, #153, #154
- `pixi.toml`: issues #101, #103, #124, #135
- `.github/workflows/apply.yml`: issues #74, #133, #223
- `.pre-commit-config.yaml`: issues #147, #189, #215
- `scripts/diff.sh`: issues #196, #197, #199
- `.github/workflows/validate.yml`: issues #244, #275
- `tests/test-api-retry.sh`: issues #210, #265
- `scripts/doctor.sh`: issues #50, #244
- `scripts/rollback.sh`: issues #225, #227
- `hooks/`: issues #108, #215
- `CHANGELOG.md`: issues #126, #127

## ALREADY-DONE Evidence

For each issue flagged as already-done, here is the evidence:

- **#30**: LICENSE file exists
  - Evidence: `LICENSE`
- **#50**: doctor.sh exists and callable
  - Evidence: `scripts/doctor.sh`
- **#51**: report_unmanaged exported from reconcile.sh
  - Evidence: `scripts/lib/reconcile.sh:337`

## DUPLICATE Mapping

Issues where the same underlying work is referenced across multiple issue numbers:

- **#68** is duplicate of **#70**: Both about plan.sh argument validation and error handling
- **#144** is duplicate of **#211**: Both address same shellcheck CI enforcement goal
- **#259** is duplicate of **#261**: Both fix jq reserved keyword "label" issue in different scripts

## Issue Groupings by Domain

### jq Reserved Keyword Fixes (interdependent)
- #259: Fix jq 1.6 reserved-word breakage in plan.sh
- #261: Fix jq reserved keyword 'label' in export.sh and plan.sh
- Note: #259 and #261 overlap; should consolidate

### report_unmanaged Family (sequential dependency)
- #51: Extract report_unmanaged into reconcile.sh (base work) [ALREADY-DONE]
- #273: Rename to avoid shadowing (follows #51)
- #271: Remove duplication in status.sh (follows #51)
- Note: #273 and #271 depend on #51 being done first

### Drift Detection (related domain)
- #85: build_create_json() omits model and deployment.type on CREATE
- #86: status.sh silently drops tags drift detection
- #95: compute_drift() does not check owner or role for drift
- #97: plan.sh does not show owner/role drift in dry-run output
- Note: These touch scripts/lib/reconcile.sh and scripts/status.sh

### Apply/Plan Dry-Run Issues (related)
- #69: apply.sh --dry-run does not pass --prune context to plan.sh
- #71: apply.sh --dry-run --prune silently drops --prune intent
- #96: apply.sh has no --dry-run path for the cache optimization code
- Note: All touch scripts/apply.sh and scripts/plan.sh

### Pre-commit Hook Improvements (multi-part enhancement)
- #145: Add pre-commit hook install step to README / Quick start
- #146: Add just test invocation to the pre-commit hook
- #147: Add test coverage for pre-commit hook dangerous-flags integration
- #200: Add name uniqueness check to pre-commit hook
- #215: Add shellcheck to pre-commit hook for instant local feedback
- #123: Pre-commit hook should run validate-fleet-refs.sh on fleet changes
- #108: Add shell-based tests for pre-commit hook staged-vs-working-tree behavior
- Note: Serialization needed on hooks/pre-commit

### Shellcheck & Linting (multi-phase)
- #144: Shellcheck: verify all scripts pass before CI enforces it (DUPLICATE of #211)
- #211: Shellcheck: verify all scripts pass before CI enforces it
- #187: Fix shellcheck SC2034/SC2086 warnings in existing scripts (remedial)
- #136: Pin shellcheck version in CI for reproducibility
- Note: #187 is remedial before #144/#211 enforcement

### CI Dependency Pinning (cross-workflow)
- #74: Pin jq version in apply.yml for full reproducibility
- #75: Add dependency checks to validate.yml as well
- #102: Switch CI workflows from manual yq install to pixi install
- #133: Pin yq version in CI workflows (currently uses latest)
- #134: Add pixi to PATH in CI so just/jq are available
- Note: Serialization needed on .github/workflows/

### Audit Tracking (meta-issues)
- #30: LICENSE file exists (ALREADY-DONE)
- #29: .editorconfig, shellcheck CI, just test recipe (HARD, multi-part)
- #35: Overall Grade audit (HARD, meta-issue)
- #152: Apply kind/severity labels to existing audit issues
- #154: Assign existing open issues to Phase 1 or Phase 2 milestones
- Note: #152 and #154 are meta-issues tracking audit follow-up

### TLS/Certificate Support (feature family)
- #36: Add TLS/HTTPS support for Agamemnon API connections (main feature)
- #167: Validate TLS file paths at source time in api.sh (validation detail)
- #168: Warn when mTLS key/cert are specified without each other (validation detail)
- Note: #167 and #168 should be done as part of #36

### Testing Infrastructure
- #240: Add tests for confirmation prompt and --yes flag behavior
- #242: Add automated tests for scripts/doctor.sh
- #190: Add tests for apply.sh and plan.sh script entry points
- #191: Add test coverage for export.sh and status.sh
- #227: Add integration test for full apply → rollback round-trip
- Note: Serialization needed on tests/

## Recommended Execution Strategy

### Phase 1: EASY (Haiku)
Parallel execution — no file conflicts:
- #30: LICENSE (already done, skip)
- #275: Pin gitleaks SHA
- #259: Fix jq in plan.sh
- #261: Fix jq in export.sh (consolidate with #259)
- #103: curl to pixi.toml
- #107: validate-schemas.sh staged-content fix
- #269: Clear failed-agents.txt on retry
- #271: Remove duplication in status.sh
- #100: bash version check for test-apply-cache.sh

### Phase 2: MEDIUM (Sonnet) — SERIALIZED BY FILE
Partition by shared file to avoid conflicts:

**Batch 2a (scripts/apply.sh)**
- #268: apply.sh --retry --fail-fast pass-through
- #263: Add convergence CI step
- #240: Add tests for confirmation prompt
- #234: Source config.sh
- Others touching apply.sh need coordination

**Batch 2b (scripts/lib/reconcile.sh)**
- #51: Extract report_unmanaged (base work) [ALREADY-DONE]
- Then #273, #271 as follow-ups (already in Phase 1)
- #233: Optimize get_unmanaged_agents yq calls
- #206, #198, #130, #113, #78, #87, #86, #85, #95, #97

**Batch 2c (scripts/plan.sh)**
- #262: grep -P PCRE fix
- #261: jq reserved keyword (in Phase 1)
- #259: jq reserved keyword (in Phase 1)
- #179, #70, #68, #69, #71

**Batch 2d (.github/workflows/)**
- #223: Document AGAMEMNON_API_KEY
- #235: Add schema validation for .myrmidons.yaml
- #188: Add pre-commit run to CI
- #133: Pin yq version
- #74: Pin jq version
- #75: Add dependency checks
- #144, #211: Shellcheck enforcement (same issue, consolidate)

**Batch 2e (Pre-commit hook improvements)**
- #145: Add install step to README
- #146: Add just test invocation
- #200: Add name uniqueness check
- #123: validate-fleet-refs.sh on changes
- #215: Add shellcheck
- #147: Add tests
- #108: Add shell tests

**Batch 2f (Tests)**
- #242: doctor.sh tests
- #191: export.sh, status.sh tests
- #190: apply.sh, plan.sh tests
- #210: retry timing assertions
- #129: report_unmanaged tests
- #199: diff.sh tests
- Others

**Other MEDIUM (can be worked in parallel)**
- #8: Fleet YAML support
- #36: TLS/HTTPS support
- #41: Idempotency guards
- #48: Dry-run confirmation
- #50: doctor command (already done)
- #56: Transaction semantics
- #54: Lock file support
- #53: YAML sanitization
- #81: Nomad deployment type
- And many others...

### Phase 3: HARD (Human review + Opus)
- #35: Overall audit (meta)
- #29: Multi-part audit (.editorconfig, CI, justfile)
- #152, #154: Audit tracking

## Notes

1. **Already-done vs. not-started**: 
   - #30 (LICENSE exists)
   - #50 (doctor.sh exists)
   - #51 (report_unmanaged extracted to reconcile.sh)
   All three are complete or substantially complete.

2. **Serialization critical**: 
   - `scripts/apply.sh` touched by 23 issues
   - `scripts/lib/reconcile.sh` touched by 16 issues
   - `scripts/plan.sh` touched by 16 issues
   - `.github/workflows/` touched by 14 issues
   - Agents must be serialized on these files to avoid merge conflicts

3. **Dependency chains**: 
   - #51 (DONE) → #273/271 (both EASY, Phase 1)
   - #36 → #167/#168 (related TLS validation work)
   - #187 (fix issues) → #144/#211 (enforce in CI)

4. **Duplicates to consolidate**: 
   - #259/#261 (jq keyword fix) — choose one, consolidate both scripts in single PR
   - #144/#211 (shellcheck enforcement) — identical goal, consolidate
   - #68/#70 (plan.sh arg validation) — choose one, consolidate

5. **File touch hotspots** (>20 issues per file):
   - scripts/apply.sh: 23 issues — plan serialization strategy
   - tests/: 21 issues — large test suite, should batch by test file
   - scripts/lib/reconcile.sh: 16 issues — critical library, careful review needed
   - scripts/plan.sh: 16 issues — multiple logic improvements needed
