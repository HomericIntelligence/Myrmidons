# Main Protection and Merge Queue

## Required checks on `main`

The active repository ruleset is `homeric-main-baseline` (ID `15556489`). Its
Myrmidons contract requires exactly seven GitHub Actions contexts:

| Job name (exact GitHub context) | Job key in YAML |
| --- | --- |
| `lint` | `lint` |
| `unit-tests` | `unit-tests` |
| `security/dependency-scan` | `security-dependency-scan` |
| `security/secrets-scan` | `security-secrets-scan` |
| `build` | `build` |
| `schema-validation` | `schema-validation` |
| `deps/version-sync` | `deps-version-sync` |

The machine-readable source of truth is
[`configs/github/merge-queue-policy.json`](../configs/github/merge-queue-policy.json).
The workflow also emits `forbid-suppressions`, `package`, `typecheck`, and
`install`, but those contexts are not part of the live seven-context contract.
The separate `release` workflow is also not required.

The required workflow runs for all relevant event paths:

- `pull_request` targeting `main`;
- `push` to `main`;
- `merge_group` with action `checks_requested`.

The merge-group trigger makes the same required contexts available on the
synthetic commit GitHub builds for the queue. It does not alter pull-request or
push behavior.

## Approved staged queue policy

Workflow support and the declarative activation contract land and receive
independent human review before any live ruleset changes. Live activation and
one representative queued pull-request smoke test happen only after merge.

| Setting | Required value |
| --- | --- |
| Target branch | `main` |
| Merge method | `SQUASH` |
| Grouping strategy | `ALLGREEN` |
| Maximum queue builds | `10` |
| Maximum entries merged per group | `5` |
| Minimum entries per group | `1` |
| Minimum wait | `5` minutes |
| Required-check timeout | `60` minutes |

Issue #765 remains open until the post-merge activation and queue smoke
evidence are recorded.

## Central Odysseus activation contract

[Odysseus issue #386](https://github.com/HomericIntelligence/Odysseus/issues/386)
is the umbrella tracker for the merge queue rollout. The current implementation
and activation authority is
[Odysseus PR #417](https://github.com/HomericIntelligence/Odysseus/pull/417).
Live activation remains deferred, and this Myrmidons work has not mutated live
GitHub ruleset state. Odysseus is the sole activation authority; this dataset
repository intentionally contains no administrator-level mutator and must not
duplicate one. The central authority must consume Myrmidons's repository-owned
policy while preserving the full fail-safe preservation, read-back, and
rollback contract below.

The Odysseus activation implementation must:

1. Consume
   [`configs/github/merge-queue-policy.json`](../configs/github/merge-queue-policy.json)
   as the repository-owned source for the Myrmidons queue settings and seven
   required contexts. It must not copy those values into an Odysseus-specific
   fixed Myrmidons payload.
2. Require the target include list to equal only `refs/heads/main` and require
   the exclusion list to be empty before mutation.
3. Patch the current live `homeric-main-baseline` GET response by appending only
   the approved `merge_queue` rule. It must preserve the exact seven contexts,
   the repository-role bypass actor, conditions, enforcement, pull-request
   policy, and every other unrelated rule without reconstruction.
4. Save a durable pre-change snapshot, read the ruleset back after mutation,
   and verify the complete intended state. An ambiguous write, failed read-back,
   or preservation mismatch must fail closed and restore the snapshot.
5. Retain the snapshot whenever restoration or its verification is incomplete,
   and require operator inspection before any retry.

The offline fixtures and tests in this repository validate the input and
preservation contract without performing GitHub API writes. The mutation,
read-back, rollback, and live smoke evidence belong only to Odysseus.

## Verification after activation

After the central Odysseus activation reports verified success:

```bash
gh api repos/HomericIntelligence/Myrmidons/rulesets/15556489 \
  --jq '.rules[]
        | select(.type == "merge_queue"
          or .type == "required_status_checks")'
```

Then queue one representative pull request. Record the
`merge_group/checks_requested` run, all seven successful check contexts, and
the queued squash merge on issue #765. Do not treat this repository-only PR as
live activation evidence.

## Design notes

- The live ruleset keeps `strict_required_status_checks_policy: false`; the
  queue tests the synthetic commit that will actually merge.
- Path-filtered workflows must not become required checks because they can
  skip unrelated changes and leave a required context pending forever.
- `release` (`.github/workflows/release.yml`) remains intentionally optional.
  It emits the ecosystem CI-board signal and publishes only on tags.

## CI security scans — blocking rationale

The two security required-checks behave very differently on purpose. The
asymmetry is deliberate, not an oversight.

### `security/secrets-scan` (gitleaks) — **hard block**

- **What it does:** runs `gitleaks detect --source . --config .gitleaks.toml --no-git -v` over the full tree on every PR.
- **Why it blocks:** a leaked secret in source is an immediate, irrecoverable
  security incident — once a credential is pushed to a public-history branch it
  must be treated as compromised even if the commit is later removed. There is
  no acceptable "merge now, rotate later" workflow for this class of finding.
- **No `continue-on-error` allowed.** The gitleaks step intentionally has no
  `continue-on-error: true` and no `|| true`. Two regression guards enforce
  this repo-wide:
  - `forbid-continue-on-error` (pre-commit + CI) — a pygrep hook in
    `.pre-commit-config.yaml` that blocks `continue-on-error: true` anywhere
    under `.github/workflows/`.
  - `forbid-advisory-warnings` (pre-commit + CI) — blocks `|| true` patterns in
    workflow `run:` blocks so an author cannot silently downgrade gitleaks to
    advisory mode.
- **False positives** are handled exclusively via `.gitleaks.toml` allowlist
  entries with `# gitleaks-allowlist: <justification>` comments. See the
  Gitleaks allowlist section of [AGENTS.md](../AGENTS.md).

### `security/dependency-scan` (pip-audit + Trivy) — **informational**

The job is required-to-run (so the signal is visible on every PR) but the two
scanners inside are configured to surface vulnerability findings as
information, not as a merge block:

- **`pip-audit`** runs with an explicit `--ignore-vuln <ID>` list against the
  baseline `ubuntu-latest` runner image (issue #713). Myrmidons declares zero
  PyPI dependencies, so every advisory pip-audit raises is in the runner image
  itself — outside our control until `actions/runner-images` ships a refresh.
  Blocking PRs on transient upstream runner CVEs would halt all merges with no
  remediation available to the contributor.
- **`Trivy filesystem scan`** runs with `--exit-code 0` (vulnerability findings
  non-fatal). Install/extraction failures still fail the step — we want to
  know when the scanner stops working, just not when it reports a HIGH against
  an upstream package.
- **Why we don't hard-block:** (a) baseline CVEs in the runner image are out
  of our control, and (b) blocking on transient upstream advisories would
  block every PR for reasons unrelated to the change under review.
- **How findings are tracked:** dated allowlists in the workflow itself
  (`--ignore-vuln` IDs with a review date — see the comment block above the
  `pip-audit` step in `.github/workflows/_required.yml`). Each allowlisted CVE
  carries a `review YYYY-MM-DD` marker so the list can be pruned after the
  next runner-image refresh.

### Quick reference

| Job                        | Behaviour                                                        | Reason                                                                                                  |
| -------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `security/secrets-scan`    | Hard block. Any gitleaks hit fails the PR.                       | Leaked secrets are irrecoverable; rotation is not a substitute for prevention.                          |
| `security/dependency-scan` | Informational. `pip-audit --ignore-vuln`, `trivy --exit-code 0`. | Findings are dominated by runner-image baseline CVEs outside our control. Tracked via dated allowlists. |
