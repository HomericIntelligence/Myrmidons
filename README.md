# Myrmidons

GitOps agent provisioning for the HomericIntelligence mesh.
Agent YAML files are the source of truth for **desired** state.
Scripts reconcile against [ProjectAgamemnon](https://github.com/HomericIntelligence/ProjectAgamemnon) via its REST API.

Container images are built separately in [AchaeanFleet](../AchaeanFleet).

## Quick start

```bash
# Install dependencies (yq, jq, just)
pixi install   # or: apt install jq && curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq

# Install pre-commit hook
just install-hooks

# Bootstrap: export current Agamemnon state to YAML (run once)
just export hermes

# Review what Myrmidons would do
just plan hermes

# Apply desired state
just apply hermes
```

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
```

## Agent definition format

```yaml
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: my-agent           # Agamemnon API name / tmux session name — NOT the filename
  host: hermes
spec:
  label: My Agent          # Display name; filename = lowercase(label) + ".yaml"
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

**Fleet `ref:` entries resolve by filename stem**, not by `metadata.name`:
```
ref: hermes/aindrea   →   agents/hermes/aindrea.yaml   ✓
```

## Adding an agent

```bash
# Filename = lowercase(spec.label); e.g. label "MyAgent" → my-agent.yaml
cp agents/_templates/claude-default.yaml agents/hermes/my-agent.yaml
# Edit: metadata.name (Agamemnon name), spec.label, workingDirectory, taskDescription, tags
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
  pre-commit           Validates YAML schema before commit
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AGAMEMNON_URL` | `http://localhost:8080` | ProjectAgamemnon base URL |

## Dependencies

- `yq` ≥ 4.0 — YAML parser
- `jq` ≥ 1.6 — JSON processor
- `curl` — HTTP client
- `just` ≥ 1.13 — task runner
