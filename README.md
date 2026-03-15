# Myrmidons

GitOps agent provisioning for the HomericIntelligence mesh.
Agent YAML files are the source of truth for **desired** state.
Scripts reconcile against [ai-maestro](https://github.com/HomericIntelligence/ai-maestro) via its REST API.

Container images are built separately in [AchaeanFleet](../AchaeanFleet).

## Quick start

```bash
# Install dependencies (yq, jq, just)
pixi install   # or: apt install jq && curl -fsSL .../yq_linux_amd64 -o /usr/local/bin/yq

# Install pre-commit hook
just install-hooks

# Phase 1: export current ai-maestro state to YAML (run once)
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
  name: my-agent           # Unique per host — matches tmux session name
  host: hermes
spec:
  label: My Agent          # Display name in ai-maestro UI
  program: claude-code     # claude-code | aider | codex | goose | cline | opencode | none
  model: null              # null = ai-maestro default; or "claude-sonnet-4-6"
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
  export.sh            Bootstrap: ai-maestro → YAML
  plan.sh              Dry-run reconciliation
  apply.sh             Reconcile desired → actual
  status.sh            Show desired vs actual table
  lib/
    api.sh             ai-maestro REST API client
    reconcile.sh       Drift computation logic
hooks/
  pre-commit           Validates YAML schema before commit
```

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AIM_HOST` | `http://localhost:23000` | ai-maestro base URL |

## Dependencies

- `yq` ≥ 4.0 — YAML parser
- `jq` ≥ 1.6 — JSON processor
- `curl` — HTTP client
- `just` ≥ 1.13 — task runner
