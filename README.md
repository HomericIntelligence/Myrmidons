# Myrmidons

[![Lint](https://github.com/HomericIntelligence/Myrmidons/actions/workflows/lint.yml/badge.svg)](https://github.com/HomericIntelligence/Myrmidons/actions/workflows/lint.yml)
[![Validate YAML](https://github.com/HomericIntelligence/Myrmidons/actions/workflows/validate.yml/badge.svg)](https://github.com/HomericIntelligence/Myrmidons/actions/workflows/validate.yml)
[![Test](https://github.com/HomericIntelligence/Myrmidons/actions/workflows/test.yml/badge.svg)](https://github.com/HomericIntelligence/Myrmidons/actions/workflows/test.yml)
[![Lock Check](https://github.com/HomericIntelligence/Myrmidons/actions/workflows/lock-check.yml/badge.svg)](https://github.com/HomericIntelligence/Myrmidons/actions/workflows/lock-check.yml)
[![Release](https://github.com/HomericIntelligence/Myrmidons/actions/workflows/release.yml/badge.svg)](https://github.com/HomericIntelligence/Myrmidons/actions/workflows/release.yml)

**The agent dataset for the HomericIntelligence mesh.**

Myrmidons is a GitOps-managed dataset of agent and fleet YAML definitions. It is
the source of truth for *desired* agent state across the mesh. Validators in
this repo ensure every definition conforms to the schema; consumers (notably
[ProjectAgamemnon](https://github.com/HomericIntelligence/ProjectAgamemnon))
read this dataset and reconcile their runtime against it.

This repo intentionally contains **only**:

- **YAML schemas** for agents and fleets (`schemas/`)
- **Agent and fleet descriptions** that conform to those schemas (`agents/`, `fleets/`)
- **Validators** that read the dataset and enforce schema + policy (`scripts/`, `tests/`)
- **Documentation** about the dataset and its schemas (this README, `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `docs/adr/`)
- **CI/CD wrappers** that run the validators on every PR (`.github/workflows/`, `.pre-commit-config.yaml`, `pixi.toml`)

It does NOT contain runtime infrastructure. Specifically:

- The **reconciler** (apply/plan/status/export) that drives Agamemnon's REST API
  lives in
  [ProjectAgamemnon](https://github.com/HomericIntelligence/ProjectAgamemnon) —
  see [PR #405](https://github.com/HomericIntelligence/ProjectAgamemnon/pull/405).
- **Container images** for agents live in [AchaeanFleet](https://github.com/HomericIntelligence/AchaeanFleet).

## Quick start

```bash
# Install validators (pixi-managed env: yq, jq, bats-core, shellcheck, yamllint)
pixi install

# Install pre-commit hooks so every commit runs the validators
just install-hooks

# Validate every agent/fleet YAML in the repo
just validate

# Run the full validator test suite (bats unit + schema + drift checks)
just test

# Run all linters
just lint
```

## Agent definition format

```yaml
# yaml-language-server: $schema=../../schemas/agent-v1.schema.json
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: my-agent           # Unique per host — Agamemnon API identifier
  host: hermes
spec:
  label: My Agent          # Display name in the Agamemnon UI
  program: claude-code     # claude-code | aider | codex | goose | cline | opencode | none
  model: null              # null = consumer default; or e.g. "claude-sonnet-4-6"
  workingDirectory: /home/mvillmow/MyProject
  programArgs: ""
  taskDescription: "What this agent does"
  tags: [myproject, analysis]
  owner: mvillmow
  role: member             # member | admin
  deployment:
    type: local            # local = tmux on host; docker = container
    docker:                # Only used when type: docker
      image: achaean-claude:latest
      cpus: 2
      memory: 4g
  desiredState: active     # active | hibernated
```

### Naming convention

| Field | Example | Purpose |
|-------|---------|---------|
| **Filename** | `aindrea.yaml` | Derived from `spec.label` (lowercased). Used by fleet `ref:` entries. |
| **`metadata.name`** | `odyssey-mainline-analysis` | Consumer-side identifier (e.g., Agamemnon API name / tmux session name). |
| **`spec.label`** | `Aindrea` | Display name shown in the consumer UI. |

Fleet `ref:` entries resolve by **filename stem**, not by `metadata.name`:

- `ref: hermes/aindrea` → `agents/hermes/aindrea.yaml` ✓
- `ref: hermes/odyssey-mainline-analysis` → file not found ✗

See [ADR-008](docs/adr/ADR-008-fleet-ref-filename-stem-resolution.md) for rationale.

## Adding an agent

```bash
cp agents/_templates/claude-default.yaml agents/hermes/my-agent.yaml
# Edit: name, label, workingDirectory, taskDescription, tags
just validate                                         # schema + name uniqueness
git add agents/hermes/my-agent.yaml && git commit -m "feat(agents): add my-agent"
```

Open a PR — CI runs the full validator suite. Consumers (Agamemnon) pick up
the merged state on their next reconciliation cycle.

## Directory structure

```
schemas/                  YAML schemas (JSON Schema) for agents, fleets, config
  agent-v1.schema.json
  fleet-v1.schema.json
  config.schema.json
agents/
  _templates/             Starter templates (not enforced by schema check)
  <host>/                 Agent YAML files for a given host
fleets/                   Fleet definitions (group multiple agents by ref)
scripts/                  Dataset validators (read-only against agents/, fleets/)
  check-dangerous-flags.sh
  check-schema-hints.sh
  lint-agents-md.sh
  lint-names.sh
  lint-shell.sh
hooks/
  pre-commit              Git pre-commit hook (legacy) — validates schema
.pre-commit-config.yaml   pre-commit framework config (preferred)
tests/                    bats unit tests for the validators
docs/adr/                 Architecture Decision Records about the dataset
.github/workflows/        CI: runs validators on every PR
```

## Architecture Decision Records

Architecture decision records are in [`docs/adr/`](docs/adr/README.md). Consult
them before making structural changes to schemas or validators.

## Dependencies

All validator dependencies are pinned in `pixi.toml`. Install via `pixi install`.

- `yq` ≥ 4.0 — YAML parser
- `jq` ≥ 1.6 — JSON processor
- `bats-core` ≥ 1.11 — test runner for validators
- `shellcheck` 0.10.0 — shell-script lint
- `yamllint` ≥ 1.35 — YAML lint
- `pre-commit` ≥ 3.0 — hook framework (`just install-hooks`)

## CI/CD

Every PR runs:

- `pre-commit run --all-files` (formatting + lint + schema)
- Schema validation against `schemas/agent-v1.schema.json` and `schemas/fleet-v1.schema.json`
- Fleet `ref:` referential integrity
- Name uniqueness across all agent YAMLs
- Dangerous-flag policy (`--dangerously-skip-permissions` requires inline suppression)
- Schema-hint policy (`yaml-language-server` comment required on every agent YAML)

Branch protection on `main` enforces the exact seven-context contract in
[`configs/github/merge-queue-policy.json`](configs/github/merge-queue-policy.json).
The required-check workflow handles pull requests, `main` pushes, and
`merge_group/checks_requested` events. The tested fail-safe activation and
rollback procedure is documented in
[`docs/branch-protection.md`](docs/branch-protection.md).

## Security

The dangerous-flag policy and gitleaks allowlist policy are documented in
`CLAUDE.md` under "Security." Both are enforced by pre-commit hooks and in CI.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for branch naming, commit conventions,
and PR review expectations.
