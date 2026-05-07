# Myrmidons

GitOps agent provisioning for the HomericIntelligence mesh.

> For agent safety boundaries and permitted tool use, see [AGENTS.md](AGENTS.md).

## What this repo is

Myrmidons is the source of truth for *desired* agent state. Agent definitions live as code (YAML). Scripts reconcile desired state against ProjectAgamemnon's REST API.

**ProjectAgamemnon is the source of truth at runtime.** Myrmidons is the source of truth for *desired* state.

## What this repo is NOT

- Do not modify ProjectAgamemnon source → Myrmidons drives it via its API only
- Do not modify agent state directly → use the scripts
- Do not add container image definitions here → that's AchaeanFleet

## Quick start

```bash
# Install pre-commit hooks (runs the dangerous-flags policy check on every commit)
just install-hooks

# Export current Agamemnon agents to YAML (run once)
./scripts/export.sh

# Check status
./scripts/status.sh

# See what would change (dry-run)
./scripts/plan.sh

# Apply desired state
./scripts/apply.sh
```

## Agent definition format

Every agent is a YAML file in `agents/<host>/<label>.yaml` where `<label>` is the lowercased `spec.label`:

```yaml
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: my-agent-name   # Agamemnon API name / tmux session name — NOT the filename
  host: hermes
spec:
  label: DisplayName    # Human-readable name; filename = lowercase(label) + ".yaml"
  program: claude-code
  model: null
  workingDirectory: /home/mvillmow/MyProject
  programArgs: ""
  taskDescription: "What this agent does"
  tags: [myproject, analysis]
  owner: mvillmow
  role: member
  deployment:
    type: local
  desiredState: active
```

### Naming convention

| Field | Example | Purpose |
|-------|---------|---------|
| **Filename** | `aindrea.yaml` | Derived from `spec.label` (lowercased). Used by fleet `ref:` entries. |
| **`metadata.name`** | `odyssey-mainline-analysis` | Agamemnon API identifier / tmux session name. Used by scripts and the REST API. |
| **`spec.label`** | `Aindrea` | Display name shown in the Agamemnon UI. |

**Fleet `ref:` entries resolve by filename stem**, not by `metadata.name`:
- `ref: hermes/aindrea` → `agents/hermes/aindrea.yaml` ✓
- `ref: hermes/odyssey-mainline-analysis` → `agents/hermes/odyssey-mainline-analysis.yaml` ✗ (file does not exist)

This design is intentional: filenames are label-derived for human readability; `metadata.name` carries the Agamemnon backend identity.

### Drift detection

The reconciler detects changes to these fields and applies them automatically on `apply`.
The `compute_drift` function in `scripts/lib/reconcile.sh` compares desired state (YAML)
against actual state (Agamemnon API). See [ADR-009: compute_drift Positional Parameter Interface](docs/adr/ADR-009-compute-drift-positional-parameters.md) for extension guidance.

| Field | Drift action |
|-------|-------------|
| `spec.desiredState: active` vs actual offline | WAKE |
| `spec.desiredState: hibernated` vs actual active/online | HIBERNATE |
| `spec.label` | UPDATE |
| `spec.program` | UPDATE |
| `spec.workingDirectory` | UPDATE |
| `spec.programArgs` | UPDATE |
| `spec.taskDescription` | UPDATE |
| `spec.tags` | UPDATE (order-insensitive) |
| `spec.owner` | UPDATE |
| `spec.role` | UPDATE |

Fields not currently tracked for drift — changes to these fields are **silently
ignored** by the reconciler and will NOT be applied to the running agent:

| Field | Why not tracked |
|-------|----------------|
| `spec.model` | Agamemnon manages model selection at runtime; no drift endpoint exists |
| `spec.deployment.type` | Type changes require agent recreation, not an update — manual step required |

> **AI agent note:** If you modify `spec.model` or `spec.deployment.type` in a YAML
> file, `apply.sh` will not detect drift for those fields. The running agent will keep
> its current values until manually recreated.

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/export.sh` | Bootstrap: export Agamemnon → YAML |
| `scripts/plan.sh` | Dry-run: show what would change |
| `scripts/apply.sh [--prune]` | Reconcile desired → actual |
| `scripts/status.sh` | Table of desired vs actual + drift |

### Observability flags

Both `apply.sh` and `status.sh` accept:
- `--output json` — emit a machine-readable JSON summary to `reports/last-reconciliation.json`
- `--webhook <url>` — POST the JSON summary to a webhook endpoint after reconciliation

Example: `./scripts/apply.sh hermes --output json | jq .summary`

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AGAMEMNON_URL` | `http://localhost:8080` | ProjectAgamemnon base URL |
| `AGAMEMNON_API_KEY` | _(unset)_ | Bearer token / API key for authenticating requests |
| `AGAMEMNON_TIMEOUT` | `10` | HTTP request timeout in seconds for all API calls |
| `LOG_LEVEL` | `INFO` | Log verbosity: DEBUG, INFO, WARN, ERROR |
| `LOG_FORMAT` | `text` | Log output format: text or json |
| `AIM_LOCK_FILE` | `.myrmidons.lock` | Path to the apply lock file (use workspace-scoped path in parallel CI) |
| `HIBERNATE_SETTLE_SECONDS` | `2` | Seconds to wait after hibernating an agent before continuing (set to `0` in CI to skip the settle delay) |
| `MYRMIDONS_DEFAULT_OWNER` | `$(whoami)` | Fallback owner written to exported agent YAMLs when the Agamemnon API returns no owner |
| `MYRMIDONS_YES` | _(unset)_ | Set to `true` to skip all interactive confirmation prompts (equivalent to `--yes`); useful in CI pipelines where stdin is not a TTY |

## Authentication

When `AGAMEMNON_API_KEY` is set, all API calls include:

```
Authorization: Bearer <token>
X-API-Key: <token>
```

When unset, requests are unauthenticated (backward compatible).

**Never** put the token value in scripts or commit it to the repository. Use environment variables or GitHub secrets:

```bash
# Local usage
export AGAMEMNON_API_KEY=your-token-here
./scripts/status.sh
```

In CI, add `AGAMEMNON_API_KEY` as a GitHub Actions secret (see `.github/workflows/apply.yml`).

### AGAMEMNON_URL security

`AGAMEMNON_URL` should point to a trusted Agamemnon instance only. The scripts
pass this URL directly to `curl` — a malicious URL could redirect API calls to
an attacker-controlled server. In CI, always source this from a GitHub secret,
never hard-code it in workflow files.

## TLS / HTTPS

To connect to Agamemnon over HTTPS, set these environment variables:

| Variable | Description |
|----------|-------------|
| `AGAMEMNON_CA_CERT` | Path to a PEM CA certificate file for server verification |
| `AGAMEMNON_CLIENT_CERT` | Path to a PEM client certificate file (mTLS) |
| `AGAMEMNON_CLIENT_KEY` | Path to a PEM client key file (mTLS) |
| `AGAMEMNON_TLS_VERIFY` | Set to `false` to skip TLS verification (not recommended) |

### Generating and storing TLS secrets for CI

1. Base64-encode PEM files for GitHub secrets:
   ```bash
   base64 -w0 ca.pem   # → AGAMEMNON_CA_CERT_B64
   base64 -w0 client.pem  # → AGAMEMNON_CLIENT_CERT_B64
   base64 -w0 client.key  # → AGAMEMNON_CLIENT_KEY_B64
   ```
2. Add each as a repository secret via GitHub UI or:
   ```bash
   gh secret set AGAMEMNON_CA_CERT_B64 < <(base64 -w0 ca.pem)
   ```
3. The apply workflow decodes them to temp files before running scripts.

## Adding a new agent

1. Choose a label (e.g. `MyAgent`) — the filename will be `agents/hermes/myagent.yaml` (lowercase label)
2. Copy a template: `cp agents/_templates/claude-default.yaml agents/hermes/myagent.yaml`
3. Fill in all required fields; set `spec.label: MyAgent` and `metadata.name` to the Agamemnon agent name
4. Run `./scripts/plan.sh` to preview the change
5. Run `./scripts/apply.sh` to create + start the agent
6. Commit the YAML file

## Dependencies

- `yq` — YAML parser
- `jq` — JSON processor
- `curl` — HTTP client
- `actionlint` — GitHub Actions workflow linter (required for pre-commit; must be installed as a system binary to support Go <1.16 hosts)
- ProjectAgamemnon running at `$AGAMEMNON_URL`

### Installing actionlint (Go <1.16 systems)

The `actionlint` pre-commit hook is configured to use the system-installed binary to ensure compatibility with Go 1.15 and earlier. Pre-commit will not compile it from source.

**Installation options:**

```bash
# macOS (via Homebrew)
brew install actionlint

# Linux (via pre-built binary)
curl -fsSL https://github.com/rhysd/actionlint/releases/download/v1.7.7/actionlint_linux_amd64.tar.gz | tar xz
# Move the binary to your PATH, e.g. /usr/local/bin/

# Or via conda (if using conda/pixi environments)
conda install -c conda-forge actionlint
```

If `actionlint` is not installed when you run `pre-commit`, it will fail with an error like `Executable 'actionlint' not found`. Install it using one of the methods above.

## CI/CD

- **On PR:** `.github/workflows/validate.yml` validates all YAML schemas and checks for dangerous flags
- **On merge to main:** `.github/workflows/apply.yml` auto-applies to target host

Requires GitHub secret: `AGAMEMNON_URL`

## Security

### `--dangerously-skip-permissions` policy

The `--dangerously-skip-permissions` flag disables all permission prompts for Claude Code agents. An agent running with this flag can execute arbitrary file modifications, network requests, and system commands without user approval.

**Policy:** This flag is **prohibited** in agent/fleet YAML files unless a suppression annotation is present on the same line documenting the security justification.

**Suppression format:**
```yaml
programArgs: "--dangerously-skip-permissions" # skip-permissions-lint: <justification>
```

The justification must describe:
- Why the flag is required in this context
- What compensating controls exist (e.g., ephemeral container, read-only mount, job timeout)

**Lint guard:** `scripts/check-dangerous-flags.sh` enforces this policy. It runs:
- As a pre-commit hook (staged files only)
- In CI on every PR (all agent/fleet YAMLs)

To run manually: `./scripts/check-dangerous-flags.sh`

### Gitleaks allowlist

`gitleaks` scans every PR for secrets. False positives (e.g. test fixtures, documentation
examples, placeholder tokens) must be suppressed via `.gitleaks.toml` — **not** by adding
`continue-on-error: true` to the CI step.

**Correct approach — add an entry to `.gitleaks.toml`:**

```toml
[allowlist]
description = "Test fixtures and documentation examples"
regexes = [
  '''your-placeholder-token''',   # gitleaks-allowlist: doc example in CLAUDE.md, not a real credential
]
paths = [
  '''tests/.*''',                 # gitleaks-allowlist: test fixtures contain intentional fake secrets
]
```

Every new allowlist entry **must** include an inline comment `# gitleaks-allowlist: <justification>`
that describes:
- Why the match is a false positive
- Where the value appears (file, section, or purpose)

**Wrong approach:** setting `continue-on-error: true` on the scan step silently swallows
real leaks. Never do this — if you encounter it in the workflow, fix the allowlist instead.

The CI step in `.github/workflows/_required.yml` always passes `--config .gitleaks.toml`
so allowlist entries are applied automatically. To verify locally before pushing:

```bash
gitleaks detect --source . --config .gitleaks.toml --no-git -v
```

### Gitleaks version pinning

The gitleaks binary version is pinned in `.github/workflows/_required.yml` via the `GITLEAKS_VERSION` environment variable.
This pin ensures all CI runs use the same gitleaks ruleset, preventing drift in secret detection between PR checks and merges.

**How rev is chosen:** New versions are adopted after manual testing confirms no new false positives on the current allowlist.
The pinned version in `_required.yml` is the source of truth; `.gitleaks.toml` comments document this relationship.

## Known Gotchas

### jq 1.6: `label` is a reserved keyword

jq 1.6 treats `label` as a reserved keyword for its label-break syntax (`label $out | ...`).
Using `--arg label` in a jq invocation silently fails or errors. All scripts use `--arg lbl`
(or `--arg agentLabel`) instead. Do not rename these back to `--arg label`.

### Shellcheck directives

Scripts use inline shellcheck directives where needed:

- `# shellcheck source=scripts/lib/api.sh` — instructs shellcheck to follow relative sourced files by path, suppressing SC1091 (can't follow dynamic source paths like `source "${SCRIPT_DIR}/lib/api.sh"`)
- `# shellcheck disable=SC2034` — suppresses "unused variable" warnings for variables exported for subprocesses
- `# shellcheck disable=SC2086` — suppresses unquoted variable warnings where intentional word-splitting is used
- `# shellcheck disable=SC2154` — suppresses "variable referenced but not assigned" warnings for variables sourced from a library file. Use this pattern when sourcing a lib file:
  ```bash
  # shellcheck source=scripts/lib/mylib.sh
  source "${SCRIPT_DIR}/lib/mylib.sh"
  # Now $MY_VAR (defined in mylib.sh) can be used without SC2154 warnings
  ```

Run shellcheck locally: `pixi run --environment lint lint-shell`

### CI ↔ pre-commit parity

`.pre-commit-config.yaml` is the **single source of truth** for all linting.
CI's `Pre-commit (parity)` job runs `pre-commit run --all-files` — the exact same
command as local development. This keeps coverage identical with zero drift.

Rules:
- **Adding a linter?** Add it to `.pre-commit-config.yaml`. It automatically runs in CI.
- **Removing or relaxing a lint?** Change it in `.pre-commit-config.yaml`. Bias is toward *more* coverage.
- **Never add CI-only linters** outside of `.pre-commit-config.yaml`.

The `lint-shell` task in `pixi.toml` / `scripts/lint-shell.sh` covers `*.sh`, `*.bats`,
and `hooks/pre-commit`. Keep it in sync with the pre-commit shellcheck hook's `files:`
pattern.

### The `|| true` antipattern in test helpers

Test helpers (e.g. `tests/test-*.sh`) use `command || true` to suppress exit codes when testing
error paths or verifying retry behavior. This is intentional and **not** a bug. Example:

```bash
# Test case: verify retry behavior even when all attempts fail
output="$(_agamemnon_curl_retry 'http://...')" || true
# ^ suppress exit code so the test assertion can run (we want to test failure behavior)
```

Suppress SC2015 warnings on these lines with:
```bash
command || true  # shellcheck disable=SC2015 — intentional exit-code suppression for test scenario
```

### Piped input to `--prune` is rejected (non-TTY default-deny)

`apply.sh` detects non-TTY stdin and **default-denies** the prune confirmation.
This means `echo y | ./scripts/apply.sh --prune` will always abort — the piped
`y` is never read.

**Why:** Introduced in #378 as a CI safety guard. A pipe is indistinguishable
from an unattended job that should never silently hibernate or delete agents.

**What to do instead:**

```bash
# Explicit opt-in flag
./scripts/apply.sh --prune --yes

# Or via environment variable
MYRMIDONS_YES=true ./scripts/apply.sh --prune
```
