# Myrmidons

GitOps agent provisioning for the HomericIntelligence mesh.

## What this repo is

Myrmidons is the source of truth for *desired* agent state. Agent definitions live as code (YAML). Scripts reconcile desired state against ai-maestro's REST API.

**ai-maestro remains the source of truth at runtime.** Myrmidons is the source of truth for *desired* state.

## What this repo is NOT

- Do not modify ai-maestro source → Myrmidons drives it via its API only
- Do not modify `~/.aimaestro/agents/registry.json` directly → use the scripts
- Do not add container image definitions here → that's AchaeanFleet

## Quick start (Phase 1 bootstrap)

```bash
# Export current ai-maestro agents to YAML (run once)
./scripts/export.sh hermes

# Check status
./scripts/status.sh

# See what would change (dry-run)
./scripts/plan.sh

# Apply desired state
./scripts/apply.sh
```

## Agent definition format

Every agent is a YAML file in `agents/<host>/<name>.yaml`:

```yaml
apiVersion: myrmidons/v1
kind: Agent
metadata:
  name: my-agent-name     # Must match tmux session / ai-maestro name
  host: hermes
spec:
  label: DisplayName
  program: claude-code    # or: aider, codex, goose, cline, opencode, none
  model: null
  workingDirectory: /home/mvillmow/MyProject
  programArgs: ""
  taskDescription: "What this agent does"
  tags: [myproject, analysis]
  owner: mvillmow
  role: member
  deployment:
    type: local            # "local" or "docker"
  desiredState: active     # "active" or "hibernated"
```

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/export.sh [host]` | Bootstrap: export ai-maestro → YAML |
| `scripts/plan.sh [host]` | Dry-run: show what would change |
| `scripts/apply.sh [host] [--prune]` | Reconcile desired → actual |
| `scripts/status.sh [host]` | Table of desired vs actual + drift |

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AIM_HOST` | `http://localhost:23000` | ai-maestro base URL |

## Adding a new agent

1. Copy a template: `cp agents/_templates/claude-default.yaml agents/hermes/myagent.yaml`
2. Fill in all required fields
3. Run `./scripts/plan.sh` to preview the change
4. Run `./scripts/apply.sh` to create + wake the agent
5. Commit the YAML file

## Installing the pre-commit hook

```bash
cp hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## Dependencies

- `yq` — YAML parser: `curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq`
- `jq` — JSON processor: `apt install jq` or `brew install jq`
- `curl` — HTTP client (usually pre-installed)
- ai-maestro running at `$AIM_HOST`

## CI/CD

- **On PR:** `.github/workflows/validate.yml` validates all YAML schemas
- **On merge to main:** `.github/workflows/apply.yml` auto-applies to target host

Requires GitHub secret: `AIM_HOST` (e.g., `http://hermes.tailnet:23000`)
