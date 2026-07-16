# Main Protection and Merge Queue

## Live required checks on `main`

The active repository ruleset is `homeric-main-baseline` (ID `15556489`). As
verified on 2026-07-16, it requires the following GitHub Actions jobs before a
pull request can merge into `main`. All are defined in
`.github/workflows/_required.yml`.

| Job name (exact string in GitHub) | Job key in YAML |
| --- | --- |
| `lint` | `lint` |
| `unit-tests` | `unit-tests` |
| `build` | `build` |
| `schema-validation` | `schema-validation` |
| `deps/version-sync` | `deps-version-sync` |
| `security/dependency-scan` | `security-dependency-scan` |
| `security/secrets-scan` | `security-secrets-scan` |

> The string GitHub uses for the required check is the job's `name:` field, not its
> YAML key. These two differ for `deps-version-sync` (`deps/version-sync`) and both
> security jobs.

The workflow also emits `forbid-suppressions`, `package`, `typecheck`, and
`install`; these are visible CI signals but are not required by the live
ruleset. The separate `release` workflow is also not required.

The required workflow runs for all three relevant event paths:

- `pull_request` targeting `main`;
- `push` to `main`;
- `merge_group` with action `checks_requested`.

This keeps every required context available when GitHub synthesizes a merge
group commit without changing existing pull-request or push behavior.

## Verifying the live ruleset

```bash
repo=HomericIntelligence/Myrmidons
ruleset_id=15556489

gh api "repos/${repo}/rulesets/${ruleset_id}" \
  --jq '.rules[]
        | select(.type == "required_status_checks")
        | .parameters.required_status_checks[].context'
```

Compare the result byte-for-byte with the seven entries in the table above.
Do not add, remove, or rename a required context as part of merge-queue
activation.

## Merge-queue policy

Myrmidons has no canonical repository-owned ruleset automation or ruleset JSON.
Queue activation is therefore an explicit post-merge administrative step. Land
and strictly review workflow support first, then activate the live rule and run
one representative queued pull request before closing issue #765.

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

### Post-merge activation

The rulesets API replaces the full ruleset. Snapshot first, append only the
`merge_queue` rule, preserve every existing protection field and required
context, then read the rule back. Run this only after the readiness PR merges:

```bash
set -euo pipefail

repo=HomericIntelligence/Myrmidons
ruleset_name=homeric-main-baseline
ruleset_id="$(gh api "repos/${repo}/rulesets" \
  --jq ".[] | select(.name == \"${ruleset_name}\") | .id")"
snapshot="$(mktemp)"
payload="$(mktemp)"
restore="$(mktemp)"
trap 'rm -f "${snapshot}" "${payload}" "${restore}"' EXIT

gh api "repos/${repo}/rulesets/${ruleset_id}" > "${snapshot}"
jq '
  if any(.rules[]; .type == "merge_queue") then
    error("merge_queue already exists; inspect live state instead of replacing it")
  else
    {
      name,
      target,
      enforcement,
      conditions,
      bypass_actors,
      rules: (.rules + [{
        type: "merge_queue",
        parameters: {
          merge_method: "SQUASH",
          grouping_strategy: "ALLGREEN",
          max_entries_to_build: 10,
          max_entries_to_merge: 5,
          min_entries_to_merge: 1,
          min_entries_to_merge_wait_minutes: 5,
          check_response_timeout_minutes: 60
        }
      }])
    }
  end
' "${snapshot}" > "${payload}"

gh api --method PUT "repos/${repo}/rulesets/${ruleset_id}" \
  --input "${payload}"
gh api "repos/${repo}/rulesets/${ruleset_id}" \
  --jq '.rules[] | select(.type == "merge_queue") | .parameters'
```

The read-back must report all seven policy values from the table. Also re-read
the `required_status_checks` rule and confirm the seven original contexts are
unchanged. If either assertion fails, immediately restore the pre-change
snapshot:

```bash
jq '{name, target, enforcement, conditions, bypass_actors, rules}' \
  "${snapshot}" > "${restore}"
gh api --method PUT "repos/${repo}/rulesets/${ruleset_id}" \
  --input "${restore}"
```

## Design notes

- The live ruleset keeps `strict_required_status_checks_policy: false`; the
  merge queue tests the synthesized commit that will actually merge.
- Path-filtered workflows should not be added as required checks. They skip on
  unrelated changes and leave the required context pending.
- `release` (`.github/workflows/release.yml`) is intentionally **not** a required
  check: it exists to emit the canonical `release` check-run on `main` for the
  Odysseus ecosystem CI board and to publish dataset snapshots. Publishing is a
  post-merge concern; the PR-triggered run is a packaging dry-run only, and only
  the tag-gated `publish-release` job holds `contents: write`.

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
  Gitleaks allowlist section of [CLAUDE.md](../CLAUDE.md).

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

| Job | Behaviour | Reason |
| --- | --- | --- |
| `security/secrets-scan` | Hard block. Any gitleaks hit fails the PR. | Leaked secrets are irrecoverable; rotation is not a substitute for prevention. |
| `security/dependency-scan` | Informational. `pip-audit --ignore-vuln`, `trivy --exit-code 0`. | Findings are dominated by runner-image baseline CVEs outside our control. Tracked via dated allowlists. |
