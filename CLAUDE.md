# Myrmidons

The agent dataset for the HomericIntelligence mesh.

> For agent safety boundaries and permitted tool use, see [AGENTS.md](AGENTS.md).
> For contributor workflow (branching, commits, PRs, reviews), see [CONTRIBUTING.md](CONTRIBUTING.md).

## What this repo is

Myrmidons is the source of truth for **desired** agent state, expressed as YAML.
It contains the schema for those definitions, the definitions themselves, and
validators that enforce schema + policy on every PR.

This repo is a **dataset**. Consumers (most notably
[ProjectAgamemnon](https://github.com/HomericIntelligence/ProjectAgamemnon))
read this dataset and reconcile their runtime state against it.

## What this repo is NOT

- **Not the reconciler.** Scripts that drive Agamemnon's REST API (apply, plan,
  status, export, etc.) live in [ProjectAgamemnon](https://github.com/HomericIntelligence/ProjectAgamemnon)
  — see [PR #405](https://github.com/HomericIntelligence/ProjectAgamemnon/pull/405).
- **Not container images.** Per-agent Dockerfiles and base images live in
  [AchaeanFleet](https://github.com/HomericIntelligence/AchaeanFleet).
- **Not a place for runtime infrastructure** — locks, snapshots, TLS plumbing,
  retry/backoff, prune workflows, runner health monitoring. All of that is
  consumer-side.

## Quick start

```bash
# Install validators (pixi-managed env)
pixi install

# Install pre-commit hooks so every commit runs the validators
just install-hooks

# Validate every agent/fleet YAML
just validate

# Run all validator tests (bats + schema + drift)
just test
```

## Agent definition format

Every agent is a YAML file in `agents/<host>/<label>.yaml` where `<label>` is
the lowercased `spec.label`:

```yaml
# yaml-language-server: $schema=../../schemas/agent-v1.schema.json
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: my-agent-name   # Consumer-side identifier — NOT the filename
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
| **`metadata.name`** | `odyssey-mainline-analysis` | Consumer-side identifier (Agamemnon API name / tmux session name). |
| **`spec.label`** | `Aindrea` | Display name shown in the consumer UI. |

**Fleet `ref:` entries resolve by filename stem**, not by `metadata.name`:

- `ref: hermes/aindrea` → `agents/hermes/aindrea.yaml` ✓
- `ref: hermes/odyssey-mainline-analysis` → `agents/hermes/odyssey-mainline-analysis.yaml` ✗ (file does not exist)

See [ADR-008](docs/adr/ADR-008-fleet-ref-filename-stem-resolution.md) for the rationale.

## Schema versioning

The schema is versioned via the `apiVersion` field on every document. Currently
`myrmidons/v1`. See [ADR-010](docs/adr/ADR-010-schema-versioning-strategy.md)
for the strategy.

## Validators

Scripts under `scripts/` validate the dataset on every PR. Each is pure: it
reads `agents/`/`fleets/` and exits non-zero on policy violation. None of them
talk to Agamemnon or any other runtime.

| Script | What it checks |
|--------|----------------|
| `scripts/check-dangerous-flags.sh` | `--dangerously-skip-permissions` requires inline suppression with justification |
| `scripts/check-schema-hints.sh` | Every agent/fleet YAML carries a `yaml-language-server` schema-hint comment |
| `scripts/check-gitleaks-annotations.sh` | Every `.gitleaks.toml` allowlist entry carries a `# gitleaks-allowlist:` justification |
| `scripts/lint-names.sh` | `metadata.name` uniqueness across all agent YAMLs |
| `scripts/lint-agents-md.sh` | `AGENTS.md` has the required sections |
| `scripts/lint-shell.sh` | Shellcheck over every shell file in this repo |
| `tests/validate-fleet-refs.sh` | Every fleet `ref:` resolves to an existing agent file |
| `tests/validate-schemas.sh` | Every YAML conforms to its JSON Schema |
| `tests/detect-doc-drift.sh` | README/CLAUDE.md/AGENTS.md cross-reference consistency |

Adding a validator? Wire it into `.pre-commit-config.yaml` — the single source
of truth. CI runs `pre-commit run --all-files` to stay in parity with local.

## Adding a new agent

1. Choose a label (e.g. `MyAgent`) — the filename will be `agents/hermes/myagent.yaml` (lowercase label).
2. Copy a template: `cp agents/_templates/claude-default.yaml agents/hermes/myagent.yaml`.
3. Fill in all required fields; set `spec.label: MyAgent` and `metadata.name` to the consumer-side identifier you want.
4. Run `just validate` locally to catch errors before pushing.
5. Open a PR — CI runs the full validator suite.

## Dependencies

All validator dependencies are pinned in `pixi.toml`.

- `yq` — YAML parser
- `jq` — JSON processor
- `bats-core` — bats test runner
- `shellcheck` — shell lint
- `yamllint` — YAML lint
- `actionlint` — GitHub Actions workflow linter (system binary; see install notes below)

### Installing actionlint (Go <1.16 systems)

The `actionlint` pre-commit hook is configured to use the system-installed
binary to ensure compatibility with Go 1.15 and earlier. Pre-commit will not
compile it from source.

```bash
# macOS
brew install actionlint

# Linux (pre-built binary)
curl -fsSL https://github.com/rhysd/actionlint/releases/download/v1.7.7/actionlint_linux_amd64.tar.gz | tar xz
sudo mv actionlint /usr/local/bin/

# conda / pixi
conda install -c conda-forge actionlint
```

## CI/CD

- **On PR** — `.github/workflows/validate.yml` (pre-commit parity + schema validation + fleet-ref validation) and `_required.yml` (lint, unit-tests, build, install, package, schema-validation, security scans).
- **On PR / `main` push / `v*` tag** — `.github/workflows/release.yml` packages the
  dataset snapshot (`scripts/package-dataset.sh`, read-only job emitting the
  canonical `release` check-run for the Odysseus ecosystem CI board); on `v*`
  tags a separate tag-gated job publishes a GitHub Release.
- **Branch protection on `main`** — required-check list in [`docs/branch-protection.md`](docs/branch-protection.md).

## Security

### `--dangerously-skip-permissions` policy

The `--dangerously-skip-permissions` flag disables all permission prompts for
Claude Code agents. An agent running with this flag can execute arbitrary file
modifications, network requests, and system commands without user approval.

**Policy:** This flag is **prohibited** in agent/fleet YAML files unless a
suppression annotation is present on the same line documenting the security
justification.

```yaml
programArgs: "--dangerously-skip-permissions" # skip-permissions-lint: <justification>
```

The justification must describe:

- Why the flag is required in this context
- What compensating controls exist (ephemeral container, read-only mount, job timeout, etc.)

**Lint guard:** `scripts/check-dangerous-flags.sh` enforces this policy. Runs:

- As a pre-commit hook (staged files only)
- In CI on every PR (all agent/fleet YAMLs)

### `yaml-language-server` schema hint policy

Every agent and fleet YAML file must begin with a `yaml-language-server` schema
hint comment so editors can provide schema-aware autocompletion and validation:

```yaml
# yaml-language-server: $schema=../../schemas/agent-v1.schema.json
```

**Suppression** is available for legitimate exceptions (generated stubs,
template-of-the-format files):

```yaml
# schema-hint-skip: <justification>
```

Template files in `agents/_templates/` are automatically exempt.

**Lint guard:** `scripts/check-schema-hints.sh`. Runs as pre-commit + CI.

### Gitleaks allowlist

`gitleaks` scans every PR for secrets. False positives (test fixtures,
placeholder tokens) must be suppressed via `.gitleaks.toml` — never by adding
`continue-on-error: true` to a CI step.

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

Every allowlist entry **must** include an inline comment
`# gitleaks-allowlist: <justification>` describing why the match is a false
positive.

**Lint guard:** `scripts/check-gitleaks-annotations.sh` enforces this policy by
scanning every entry inside an `[allowlist]` block of `.gitleaks.toml`. Runs as
a pre-commit hook (`check-gitleaks-annotations`) and in CI via pre-commit
parity.

The CI step in `.github/workflows/_required.yml` always passes
`--config .gitleaks.toml` so allowlist entries are applied automatically.

### CI security scans: hard block vs informational

Two required checks cover security: `security/secrets-scan` and
`security/dependency-scan`. They are configured asymmetrically on purpose.

- **`security/secrets-scan` (gitleaks) — hard block.** Any finding fails the
  PR. Leaked secrets are an immediate, irrecoverable risk. The
  `forbid-continue-on-error` and `forbid-advisory-warnings` pre-commit hooks
  prevent anyone from downgrading this step to advisory mode.
- **`security/dependency-scan` (pip-audit + Trivy) — informational.**
  `pip-audit` runs with an explicit `--ignore-vuln` list and `trivy fs` runs
  with `--exit-code 0`. Myrmidons has zero PyPI dependencies, so findings are
  dominated by baseline `ubuntu-latest` runner-image CVEs we cannot fix from
  this repo. Blocking PRs on transient upstream advisories would halt every
  merge with no remediation path. Findings are tracked via dated allowlists
  in the workflow itself.

Full rationale and the regression-guard hook list:
[`docs/branch-protection.md`](docs/branch-protection.md#ci-security-scans--blocking-rationale).

## Known gotchas

### jq 1.6: `label` is a reserved keyword

jq 1.6 treats `label` as a reserved keyword for its label-break syntax
(`label $out | ...`). Using `--arg label` in a jq invocation silently fails or
errors. Validator scripts use `--arg lbl` (or `--arg agentLabel`) instead.

### CI ↔ pre-commit parity

`.pre-commit-config.yaml` is the **single source of truth** for all linting.
CI's `Pre-commit (parity)` job runs `pre-commit run --all-files` — the exact
same command as local development.

Rules:

- **Adding a linter?** Add it to `.pre-commit-config.yaml`. It automatically runs in CI.
- **Removing or relaxing a lint?** Change it in `.pre-commit-config.yaml`. Bias is toward *more* coverage.
- **Never add CI-only linters** outside `.pre-commit-config.yaml`.

## Architecture Decision Records

ADRs in `docs/adr/` document significant design decisions about the dataset
schema and validators. ADR-007 (Nomad integration) and ADR-009 (compute_drift
parameter interface) moved to ProjectAgamemnon along with the reconciler — see
[ProjectAgamemnon#405](https://github.com/HomericIntelligence/ProjectAgamemnon/pull/405).
