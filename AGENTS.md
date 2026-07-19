# AGENTS.md — Agent Safety Boundaries

This document is the sole authoritative agent contract for this repository. It
defines behavior boundaries, permitted tools, scope limitations, coordination
rules, safety constraints, and escalation paths for AI agents operating here,
plus the developer context (naming conventions, YAML format, validators,
tooling) previously kept in CLAUDE.md.

**Audience:** AI agent runtimes (Claude Code, loop agents, fleet orchestrators) and human developers.
**Contributor workflow:** See [CONTRIBUTING.md](CONTRIBUTING.md) for branching, commits, PRs, and reviews.

---

## Scope

This repository is a **dataset** of agent and fleet YAML definitions plus the
validators that enforce schema and policy on them. Agents operating here must
stay within that scope:

| In scope | Out of scope |
|----------|--------------|
| Read and write agent YAML files in `agents/` | Modify ProjectAgamemnon source code |
| Read and write fleet YAML files in `fleets/` | Manage container image definitions (→ AchaeanFleet) |
| Edit / extend dataset validators in `scripts/` | Add reconciler code that calls Agamemnon's API |
| Run linters and tests via `just` and `uv run` | Modify `.github/workflows/` without human review |
| Create commits and open pull requests | Force-push or rewrite published history |

---

## Project Overview

### What this repo is

Myrmidons is the source of truth for **desired** agent state, expressed as YAML.
It contains the schema for those definitions, the definitions themselves, and
validators that enforce schema + policy on every PR.

This repo is a **dataset**. Consumers (most notably
[ProjectAgamemnon](https://github.com/HomericIntelligence/ProjectAgamemnon))
read this dataset and reconcile their runtime state against it.

### What this repo is NOT

- **Not the reconciler.** Scripts that drive Agamemnon's REST API (apply, plan,
  status, export, etc.) live in [ProjectAgamemnon](https://github.com/HomericIntelligence/ProjectAgamemnon)
  — see [PR #405](https://github.com/HomericIntelligence/ProjectAgamemnon/pull/405).
- **Not container images.** Per-agent Dockerfiles and base images live in
  [AchaeanFleet](https://github.com/HomericIntelligence/AchaeanFleet).
- **Not a place for runtime infrastructure** — locks, snapshots, TLS plumbing,
  retry/backoff, prune workflows, runner health monitoring. All of that is
  consumer-side.

---

## Design Philosophy

> Heritage: this repository's design descends from ProjectOdyssey — the same
> "declare desired state, let validators enforce it" lineage.

The safety boundaries in this document follow from four principles. When a rule
below seems strict, it is because one of these principles made it so.

1. **Dataset, not reconciler.** Myrmidons declares *desired* agent state as
   YAML and nothing more. Anything that talks to a runtime — applying,
   planning, polling status — lives in the consumer (ProjectAgamemnon). Agents
   here never construct calls to an external API; that is why "Reintroducing the
   reconciler" and "Direct external API calls" are prohibited.
2. **Desired state is data.** Every agent and fleet is a declarative document
   validated against a versioned schema (`myrmidons/v1`). Agents edit data and
   the schemas/validators that guard it — they do not encode runtime behavior.
3. **Policy is enforced, not trusted.** Security-relevant rules (the
   `--dangerously-skip-permissions` annotation, schema hints, gitleaks
   allowlist justifications, name uniqueness) are enforced by pure, offline
   validators that run identically in pre-commit and CI. A rule that cannot be
   mechanically checked is a rule that will drift.
4. **Fail closed, escalate to humans.** When a change touches the dataset
   contract, CI workflows, schemas, or a new validator, the agent stops and
   asks. Ambiguity is resolved by a human operator, never by guessing — see
   [Escalation](#escalation--human-review-required).

---

## Permitted Actions

- Read any file in the repository
- Write YAML agent definitions in `agents/<host>/<label>.yaml`
- Write YAML fleet definitions in `fleets/`
- Edit JSON schemas in `schemas/` and dataset validators in `scripts/` (with human review for non-trivial changes)
- Run `just lint`, `just test`, `just validate`
- Run individual validators directly: `bash scripts/check-dangerous-flags.sh`, etc.
- Create git commits and push branches
- Open pull requests

---

## Prohibited Actions

- **Reintroducing the reconciler** — scripts that drive Agamemnon's REST API (apply, plan, status, export, etc.) belong in ProjectAgamemnon, not here. See [ProjectAgamemnon#405](https://github.com/HomericIntelligence/ProjectAgamemnon/pull/405).
- **Direct external API calls** — this repo does not talk to runtime systems. Never construct `curl` calls to Agamemnon or any other service from inside this repo's scripts or workflows.
- **Committing secrets** — never commit tokens, certificates, or credentials. Use environment variables or GitHub secrets.
- **`--dangerously-skip-permissions` without annotation** — see policy below.
- **Force-push** — `git push --force` and `git push --force-with-lease` are prohibited on shared branches. Create a new commit instead.
- **Skipping pre-commit hooks** — never use `--no-verify`. If a hook fails, fix the underlying issue.
- **Modifying CI workflows** — changes to `.github/workflows/` require human review.

---

## `--dangerously-skip-permissions` Policy

This flag disables all permission prompts and allows arbitrary file, network,
and system operations without approval. An agent running with this flag can
execute arbitrary file modifications, network requests, and system commands
without user approval. It is **prohibited** in agent/fleet YAML `programArgs`
unless a suppression annotation is present on the same line:

```yaml
programArgs: "--dangerously-skip-permissions" # skip-permissions-lint: <justification>
```

The justification must state why the flag is required and what compensating
controls exist (e.g., ephemeral container, read-only mount, job timeout).

Enforcement: `scripts/check-dangerous-flags.sh` runs as a pre-commit hook
(staged files only) and in CI on every PR (all agent/fleet YAMLs).

---

## Fleet Coordination

- Fleet YAMLs in `fleets/` reference agents by filename stem — see
  [Naming convention](#naming-convention).
- Do not create agent YAML files that reference `metadata.name` values already
  in use; the `lint-names.sh` validator will fail the CI build if you do.
- Conflicts between two fleet entries targeting the same agent must be
  escalated to the human operator.

---

## Escalation — Human Review Required

Pause and request human confirmation before proceeding with any of the
following:

1. Adding or modifying files in `.github/workflows/`
2. Adding a new validator in `scripts/`
3. Adding a `# skip-permissions-lint:` suppression annotation
4. Modifying the JSON schemas in `schemas/`
5. Changes that affect the dataset contract (e.g., renaming a required field, bumping `apiVersion`)
6. Any ambiguous or conflicting desired-state changes (e.g., two fleet entries targeting the same agent with different states)

---

## Quick Start

```bash
# Install the Python-based tooling (yamllint, jsonschema, pre-commit, …).
# The CLI validators (just, jq, go-yq, bats, shellcheck) come from apt /
# release binaries — see CONTRIBUTING.md.
uv sync --locked

# Install pre-commit hooks so every commit runs the validators
just install-hooks

# Validate every agent/fleet YAML
just validate

# Run all validator tests (bats + schema + drift)
just test
```

---

## Agent Definition Format

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

---

## Schema Versioning

The schema is versioned via the `apiVersion` field on every document. Currently
`myrmidons/v1`. See [ADR-010](docs/adr/ADR-010-schema-versioning-strategy.md)
for the strategy.

---

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

---

## Adding a New Agent

1. Choose a label (e.g. `MyAgent`) — the filename will be `agents/hermes/myagent.yaml` (lowercase label).
2. Copy a template: `cp agents/_templates/claude-default.yaml agents/hermes/myagent.yaml`.
3. Fill in all required fields; set `spec.label: MyAgent` and `metadata.name` to the consumer-side identifier you want.
4. Run `just validate` locally to catch errors before pushing.
5. Open a PR — CI runs the full validator suite.

---

## Dependencies

The validator toolchain is sourced two ways (per Odysseus ADR-018 — this repo
carries NO Python source, only tool config):

- **CLI tools from apt / release binaries:** `just` (task front door), `yq`
  (the **Go** mikefarah `yq`, not the PyPI one), `jq`, `bats`, `shellcheck`.
- **Python-based tools pinned in `pyproject.toml` / `uv.lock`** and run via
  `uv run`: `yamllint`, `jsonschema` / `check-jsonschema`, `pre-commit`.
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
```

---

## CI/CD

- **On PR** — `.github/workflows/validate.yml` provides pre-commit parity,
  schema validation, and fleet-ref validation.
- **On PR / `main` push / merge-group checks** —
  `.github/workflows/_required.yml` emits every live required context. The
  `merge_group` trigger is restricted to `checks_requested`, preserving the
  existing pull-request and push behavior while queued commits run the same
  gates. The exact seven-context and queue contract is machine-readable in
  `configs/github/merge-queue-policy.json`.
- **On PR / `main` push / `v*` tag** — `.github/workflows/release.yml` packages the
  dataset snapshot (`scripts/package-dataset.sh`, read-only job emitting the
  canonical `release` check-run for the Odysseus ecosystem CI board); on `v*`
  tags a separate tag-gated job publishes a GitHub Release.
- **Branch protection on `main`** — required-check list in [`docs/branch-protection.md`](docs/branch-protection.md).

---

## Security

The `--dangerously-skip-permissions` policy is defined above in
[`--dangerously-skip-permissions` Policy](#--dangerously-skip-permissions-policy).

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
  '''your-placeholder-token''',   # gitleaks-allowlist: doc example in AGENTS.md, not a real credential
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

---

## Known Gotchas

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

---

## Architecture Decision Records

ADRs in `docs/adr/` document significant design decisions about the dataset
schema and validators. ADR-007 (Nomad integration) and ADR-009 (compute_drift
parameter interface) moved to ProjectAgamemnon along with the reconciler — see
[ProjectAgamemnon#405](https://github.com/HomericIntelligence/ProjectAgamemnon/pull/405).

---

## Verification Commands

Run these before opening a pull request:

```bash
# Validate every agent/fleet YAML against the schema
just validate

# Run the full validator test suite
just test

# Run every linter (shellcheck, yamllint, schema-hint check, etc.)
just lint

# Check for dangerous-flags policy violations explicitly
bash scripts/check-dangerous-flags.sh

# Validate required H2 sections in AGENTS.md (run before editing this file)
just lint-agents-md
```
