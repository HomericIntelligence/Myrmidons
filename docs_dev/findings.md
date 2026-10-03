# Findings

- `configs/github/merge-queue-policy.json` already records the repository,
  ruleset name, exact seven required contexts, and approved queue parameters.
- `tests/unit/test_merge_queue_contract.bats` currently asserts that
  `_required.yml` does not run for `merge_group`, while a separate
  `merge-queue-smoke.yml` handles only `merge_group/checks_requested`.
- The contract test also treats any in-repository GitHub API mutator as
  prohibited, consistent with AGENTS.md's dataset-only boundary.
- `.github/workflows/_required.yml:3-7` currently handles only
  `pull_request` and `push`; all seven live required contexts are job names in
  that one workflow (`lint`, `unit-tests`, both security scans, `build`,
  `schema-validation`, and `deps/version-sync`).
- `docs/branch-protection.md:24-32`, `README.md:170-176`, and
  `AGENTS.md:291-295` already specify that `_required.yml` handles
  `merge_group/checks_requested` while preserving its pull-request and push
  behavior, so the workflow/test are out of sync with the documented contract.
- `.github/workflows/merge-queue-smoke.yml` is a one-job, five-minute
  queue-only smoke check and is compatible with staged activation; it does not
  emit any of the seven required contexts.
- The existing ruleset fixture pins `main` only, the repository-role bypass
  actor, seven required contexts, `strict_required_status_checks_policy:
  false`, and unrelated rules. The focused Bats test constructs the
  post-activation candidate by appending only the policy's `merge_queue` rule.
- `release.yml` is optional and has a tag-only publisher guarded by
  `if: startsWith(github.ref, 'refs/tags/v')`; `validate.yml` is path-filtered.
  Neither supplies a live required context, so neither should be made a queue
  gate.
- Current GitHub REST documentation confirms `PUT
  /repos/{owner}/{repo}/rulesets/{ruleset_id}` and all seven approved
  `merge_queue` parameters used by the policy. Its GET response exposes
  `bypass_actors` only to authenticated callers with ruleset write access, so
  activation preflight/read-back must use the authorized operator identity.
- Odysseus PR #417 is merged and provides the central fail-closed activation
  path: `tools/github/apply-repo-rulesets.sh --dry-run --repos Myrmidons`
  previews a live-derived payload, and the corresponding `--active` invocation
  persists a snapshot, applies only enforcement/merge-queue state, reads back,
  verifies, and rolls back on ambiguity.
- The exact repository delta is to add
  `merge_group: {types: [checks_requested]}` to `_required.yml` and replace the
  focused Bats test's negative assertion with a supplier-wide positive
  assertion. Existing policy, fixture, smoke workflow, and documentation are
  retained.
