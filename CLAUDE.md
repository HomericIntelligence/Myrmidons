# Myrmidons

GitOps agent provisioning for the HomericIntelligence mesh.

## What this repo is

Myrmidons is the source of truth for *desired* agent state. Agent definitions live as code (YAML). Scripts reconcile desired state against ProjectAgamemnon's REST API.

**ProjectAgamemnon is the source of truth at runtime.** Myrmidons is the source of truth for *desired* state.

## What this repo is NOT

- Do not modify ProjectAgamemnon source → Myrmidons drives it via its API only
- Do not modify agent state directly → use the scripts
- Do not add container image definitions here → that's AchaeanFleet

## Quick start

```bash
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

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/export.sh` | Bootstrap: export Agamemnon → YAML |
| `scripts/plan.sh` | Dry-run: show what would change |
| `scripts/apply.sh [--prune]` | Reconcile desired → actual |
| `scripts/status.sh` | Table of desired vs actual + drift |

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AGAMEMNON_URL` | `http://localhost:8080` | ProjectAgamemnon base URL |
| `AGAMEMNON_API_KEY` | _(unset)_ | Bearer token / API key for authenticating requests |

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
- ProjectAgamemnon running at `$AGAMEMNON_URL`

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
