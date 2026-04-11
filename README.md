# Myrmidons

GitOps agent provisioning for the HomericIntelligence mesh.
Agent YAML files are the source of truth for **desired** state.
Scripts reconcile against [ProjectAgamemnon](https://github.com/HomericIntelligence/ProjectAgamemnon) via its REST API.

Container images are built separately in [AchaeanFleet](../AchaeanFleet).

## Quick start

```bash
# Install dependencies (yq, jq, just, pre-commit)
pixi install   # or: apt install jq && curl -fsSL .../yq_linux_amd64 -o /usr/local/bin/yq

# Install pre-commit hooks (runs automatically on every commit)
just install-hooks   # uses pre-commit framework
# Alternatively, for backward compatibility without pre-commit:
# just install-hooks-legacy

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

# Run all linters (shellcheck, yamllint, schema validation)
just lint
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
| `AGAMEMNON_URL` | `http://localhost:8080` | ProjectAgamemnon base URL (supports `https://`) |
| `AGAMEMNON_CA_CERT` | _(unset)_ | Path to custom CA certificate bundle (PEM) for TLS |
| `AGAMEMNON_CLIENT_CERT` | _(unset)_ | Path to client certificate for mutual TLS (PEM) |
| `AGAMEMNON_CLIENT_KEY` | _(unset)_ | Path to client private key for mutual TLS (PEM) |
| `AGAMEMNON_TLS_VERIFY` | `true` | Set to `false` to disable TLS verification (**insecure — dev only**) |

### TLS configuration examples

```bash
# HTTPS with default system CA store
export AGAMEMNON_URL=https://hermes.tailnet:23000
just plan hermes

# HTTPS with a custom CA bundle (self-signed or internal PKI)
export AGAMEMNON_URL=https://hermes.tailnet:23000
export AGAMEMNON_CA_CERT=/etc/ssl/myca/ca-bundle.pem
just apply hermes

# Mutual TLS (client certificate authentication)
export AGAMEMNON_URL=https://hermes.tailnet:23000
export AGAMEMNON_CA_CERT=/etc/ssl/myca/ca-bundle.pem
export AGAMEMNON_CLIENT_CERT=~/.config/agamemnon/client.crt
export AGAMEMNON_CLIENT_KEY=~/.config/agamemnon/client.key
just apply hermes

# Disable TLS verification — development only, never in production
export AGAMEMNON_URL=https://localhost:23000
export AGAMEMNON_TLS_VERIFY=false
just status hermes
```

For CI/CD, store TLS material as GitHub secrets and expose them as environment variables:

```yaml
env:
  AGAMEMNON_URL: ${{ secrets.AGAMEMNON_URL }}
  AGAMEMNON_CA_CERT_B64: ${{ secrets.AGAMEMNON_CA_CERT_B64 }}
```

Then decode before use (see `.github/workflows/apply.yml` for the full example).

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
