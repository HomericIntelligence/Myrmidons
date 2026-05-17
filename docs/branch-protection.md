# Branch Protection — Required Status Checks

## Required checks on `main`

The following GitHub Actions jobs must pass before any PR can merge into `main`.
All are defined in `.github/workflows/_required.yml`.

| Job name (exact string in GitHub) | Job key in YAML |
|-----------------------------------|-----------------|
| `lint` | `lint` |
| `unit-tests` | `unit-tests` |
| `build` | `build` |
| `typecheck` | `typecheck` |
| `schema-validation` | `schema-validation` |
| `deps/version-sync` | `deps-version-sync` |
| `security/dependency-scan` | `security-dependency-scan` |
| `security/secrets-scan` | `security-secrets-scan` |

> The string GitHub uses for the required check is the job's `name:` field, not its
> YAML key. These two differ for `deps-version-sync` (`deps/version-sync`) and both
> security jobs.

## Restoring required checks after a protection reset

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
    "typecheck",
    "schema-validation",
    "deps/version-sync",
    "security/dependency-scan",
    "security/secrets-scan"
  ]
}
EOF
```

## Verifying current required checks

```bash
gh api repos/mvillmow/Myrmidons/branches/main/protection/required_status_checks \
  | jq '.contexts'
```

Expected output includes `"security/secrets-scan"` and `"security/dependency-scan"`.

## Design notes

- `strict: false` — stale branches may merge without rebasing; set to `true` to require branches to be up-to-date before merging.
- `security/secrets-scan` must **not** have `continue-on-error: true` on the gitleaks step — the `forbid-continue-on-error` pre-commit hook (pygrep over all workflow files) enforces this repo-wide.
- `security/dependency-scan` uses `|| true` on pip-audit and Trivy intentionally — those tools are informational. Only `security/secrets-scan` is a hard block.
- Path-filtered workflows should not be added as required checks (they skip on unrelated PRs and would block merges incorrectly).
