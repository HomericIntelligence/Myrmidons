# Myrmidons

[![Lint and Test](https://github.com/HomericIntelligence/Myrmidons/actions/workflows/lint.yml/badge.svg)](https://github.com/HomericIntelligence/Myrmidons/actions/workflows/lint.yml)
[![Validate YAML](https://github.com/HomericIntelligence/Myrmidons/actions/workflows/validate.yml/badge.svg)](https://github.com/HomericIntelligence/Myrmidons/actions/workflows/validate.yml)
[![Repo Grade: B+](https://img.shields.io/badge/repo%20grade-B%2B-brightgreen)](https://github.com/HomericIntelligence/Myrmidons/issues/35)

GitOps agent provisioning for the HomericIntelligence mesh.
Agent YAML files are the source of truth for **desired** state.
Scripts reconcile against [ProjectAgamemnon](https://github.com/HomericIntelligence/ProjectAgamemnon) via its REST API.

Container images are built separately in [AchaeanFleet](../AchaeanFleet).

## Quick start

```bash
# Install dependencies (yq, jq, just, pre-commit)
pixi install   # or: apt install jq && curl -fsSL .../yq_linux_amd64 -o /usr/local/bin/yq

# Install pre-commit hooks (runs the full pre-commit framework on every commit)
just install-hooks

# If the pre-commit framework is not installed or not desired (e.g., minimal CI,
# glibc-incompatible environments), use the legacy hook instead (dangerous-flags check only):
just install-hooks-legacy

# Bootstrap: export current Agamemnon state to YAML (run once)
just export hermes

# Review what Myrmidons would do
just plan hermes

# Apply desired state
just apply hermes
```

> **Note:** `export.sh` derives YAML filenames from the agent's display label (lowercased),
> not from `metadata.name`. For example, an agent with label `MyAgent` exports to
> `agents/hermes/myagent.yaml`. The `metadata.name` field inside the file retains the
> original Agamemnon API name. See [Naming convention](#naming-convention) for details.

## Common workflows

```bash
# Check desired vs actual state
just status hermes

# Dry-run (no changes)
just plan hermes

# Apply (creates, updates, wakes, hibernates as needed)
just apply hermes

# Apply and remove agents not in YAML
just apply-prune hermes

# Validate all YAML files
just validate

# Run all linters (shellcheck, yamllint, schema validation)
just lint
```

### Fleet operations

```bash
# Plan changes for a named fleet
just plan --fleet dev-mesh

# Apply a named fleet
just apply --fleet dev-mesh

# Show status of a fleet
just status --fleet dev-mesh
```

## Agent definition format

```yaml
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: my-agent           # Unique per host — matches tmux session name
  host: hermes
spec:
  label: My Agent          # Display name in Agamemnon UI
  program: claude-code     # claude-code | aider | codex | goose | cline | opencode | none
  model: null              # null = Agamemnon default; or "claude-sonnet-4-6"
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
| **`metadata.name`** | `odyssey-mainline-analysis` | Agamemnon API identifier / tmux session name. Used by scripts and the REST API. |
| **`spec.label`** | `Aindrea` | Display name shown in the Agamemnon UI. |

Fleet `ref:` entries resolve by filename stem, not by `metadata.name`:
- `ref: hermes/aindrea` → `agents/hermes/aindrea.yaml` ✓
- `ref: hermes/odyssey-mainline-analysis` → file not found ✗

## Adding an agent

```bash
cp agents/_templates/claude-default.yaml agents/hermes/my-agent.yaml
# Edit: name, label, workingDirectory, taskDescription, tags
just plan hermes     # preview
just apply hermes    # create + wake
git add agents/hermes/my-agent.yaml && git commit -m "add my-agent"
```

## Directory structure

```
agents/
  _templates/          Starter templates (not applied by scripts)
  hermes/              Agent YAML files for host "hermes"
    aindrea.yaml
    baird.yaml
    ...
fleets/                Fleet definitions (group multiple agents)
scripts/
  export.sh            Bootstrap: Agamemnon → YAML
  plan.sh              Dry-run reconciliation
  apply.sh             Reconcile desired → actual
  status.sh            Show desired vs actual table
  lib/
    api.sh             Agamemnon REST API client
    reconcile.sh       Drift computation logic
hooks/
  pre-commit           Validates YAML schema before commit (legacy)
.pre-commit-config.yaml  pre-commit framework configuration
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AGAMEMNON_URL` | `http://localhost:8080` | ProjectAgamemnon base URL |

## Configuration

Myrmidons reads configuration from files in this precedence order (highest wins):

1. Environment variables
2. `.myrmidons.local.yaml` (local overrides, git-ignored)
3. `.myrmidons.yaml` (project config, committed)
4. Built-in defaults

### `.myrmidons.yaml` fields

```yaml
agamemnon_url: http://localhost:8080  # same as AGAMEMNON_URL
default_host: hermes                  # default HOST for scripts
log_level: INFO                       # DEBUG | INFO | WARN | ERROR
log_format: text                      # text | json
prune_policy: confirm                 # confirm | auto | never
snapshot_retention: 10                # number of snapshots to keep
```

Create `.myrmidons.local.yaml` for machine-specific overrides (add it to `.gitignore`).

## Architecture Decision Records

Architecture decision records are in `docs/adr/` — consult them before making structural changes to scripts or YAML schemas.

## Deployment scope

Current supported deployment types: `local` (tmux on host) and `docker` (container on host).

**Multi-host scheduling (Nomad)** — Not yet implemented. Myrmidons currently drives a single
host via the ProjectAgamemnon REST API. Nomad-based multi-host scheduling is planned for a
future phase. See [ADR-007](docs/adr/ADR-007-nomad-integration-strategy.md).

## Dependencies

- `yq` ≥ 4.0 — YAML parser
- `jq` ≥ 1.6 — JSON processor
- `curl` — HTTP client
- `just` ≥ 1.13 — task runner
- `pre-commit` ≥ 3.0 — hook management and linting (`just install-hooks`)
