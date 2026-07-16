# Branch Protection — Required Status Checks

## Required checks on `main`

The following GitHub Actions jobs must pass before any PR can merge into `main`.
All are defined in `.github/workflows/_required.yml`.

| Job name (exact string in GitHub) | Job key in YAML |
|-----------------------------------|-----------------|
| `lint` | `lint` |
| `unit-tests` | `unit-tests` |
| `build` | `build` |
| `package` | `package` |
| `typecheck` | `typecheck` |
| `schema-validation` | `schema-validation` |
| `deps/version-sync` | `deps-version-sync` |
| `install` | `install` |
| `security/dependency-scan` | `security-dependency-scan` |
| `security/secrets-scan` | `security-secrets-scan` |

> The string GitHub uses for the required check is the job's `name:` field, not its
> YAML key. These two differ for `deps-version-sync` (`deps/version-sync`) and both
> security jobs.

## Restoring required checks after a protection reset

> **Tip:** If only adding new required checks (not restoring after a wipe), use the incremental snippet below instead — it preserves any extras already configured.

If branch protection is wiped (e.g. after a repo transfer or settings reset), run:

```bash
# Fetch current required contexts first to avoid overwriting any extras
gh api repos/mvillmow/Myrmidons/branches/main/protection/required_status_checks

# Replace with the full desired list (PATCH replaces, not appends)
gh api --method PATCH \
  repos/mvillmow/Myrmidons/branches/main/protection/required_status_checks \
  --input - <<'EOF'
{
  "strict": false,
  "contexts": [
    "lint",
    "unit-tests",
    "integration-tests",
    "build",
    "package",
    "typecheck",
    "schema-validation",
    "deps/version-sync",
    "install",
    "security/dependency-scan",
    "security/secrets-scan"
  ]
}
EOF
```

### Incrementally adding a required check

When you only need to add one or more new contexts (e.g. registering
`security/secrets-scan` and `security/dependency-scan` without disturbing
anything else already configured), use `jq` to merge the new entries into the
current list rather than rewriting it:

```bash
# Add security jobs without overwriting existing required checks
gh api repos/mvillmow/Myrmidons/branches/main/protection/required_status_checks \
  | jq '.contexts += ["security/secrets-scan", "security/dependency-scan"] | .contexts |= unique' \
  | gh api --method PATCH \
    repos/mvillmow/Myrmidons/branches/main/protection/required_status_checks \
    --input -
```

The `| .contexts |= unique` step makes the command idempotent — re-running it
will not produce duplicate entries.

```bash
# Register the package job without overwriting existing required checks
gh api repos/mvillmow/Myrmidons/branches/main/protection/required_status_checks \
  | jq '.contexts += ["package"] | .contexts |= unique' \
  | gh api --method PATCH \
    repos/mvillmow/Myrmidons/branches/main/protection/required_status_checks \
    --input -
```

## Verifying current required checks

```bash
gh api repos/mvillmow/Myrmidons/branches/main/protection/required_status_checks \
  | jq '.contexts'
```

Expected output includes `"security/secrets-scan"` and `"security/dependency-scan"`.

## Design notes

- `strict: false` — stale branches may merge without rebasing; set to `true` to require branches to be up-to-date before merging.
- Path-filtered workflows should not be added as required checks (they skip on unrelated PRs and would block merges incorrectly).
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
|-----|-----------|--------|
| `security/secrets-scan` | Hard block. Any gitleaks hit fails the PR. | Leaked secrets are irrecoverable; rotation is not a substitute for prevention. |
| `security/dependency-scan` | Informational. `pip-audit --ignore-vuln`, `trivy --exit-code 0`. | Findings are dominated by runner-image baseline CVEs outside our control. Tracked via dated allowlists. |
