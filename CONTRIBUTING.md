# Contributing to Myrmidons

Thank you for your interest in contributing to Myrmidons! This is the GitOps agent
provisioning repository for the
[HomericIntelligence](https://github.com/HomericIntelligence) distributed agent mesh —
agent definitions as code, reconciled against the ProjectAgamemnon API.

For an overview of the full ecosystem, see the
[Odysseus](https://github.com/HomericIntelligence/Odysseus) meta-repo.

## Quick Links

- [Development Setup](#development-setup)
- [What You Can Contribute](#what-you-can-contribute)
- [Development Workflow](#development-workflow)
- [Validation and Testing](#validation-and-testing)
- [Pull Request Process](#pull-request-process)
- [Code Review](#code-review)

## Development Setup

### Prerequisites

- [Git](https://git-scm.com/)
- [GitHub CLI](https://cli.github.com/) (`gh`)
- [Pixi](https://pixi.sh/) for environment management (installs `just`, `yq`, `jq`)
- [Just](https://just.systems/) as the command runner

### Environment Setup

```bash
# Clone the repository
git clone https://github.com/HomericIntelligence/Myrmidons.git
cd Myrmidons

# Activate the Pixi environment
pixi shell

# Install all git hooks (dangerous-flags hook + pre-commit framework)
just install-hooks

# List available recipes
just --list
```

### Verify Your Setup

```bash
# Validate all manifest schemas
just validate

# Check agent status (requires a running Agamemnon instance)
just status
```

## What You Can Contribute

- **Agent manifests** — New YAML agent definitions in the appropriate host directory
- **Manifest schema updates** — Validation rules and schema extensions
- **Validation scripts** — Improvements to `tests/validate-schemas.sh`
- **Justfile recipes** — New provisioning or management commands
- **Pre-commit hooks** — Git hook improvements in `hooks/`
- **Documentation** — README updates, manifest format guides

### YAML Manifest Format

Agent manifests are YAML files that describe desired agent state. Reference existing manifests
as examples for the expected schema. Key fields typically include agent type, resource limits,
NATS subject subscriptions, and container image references.

## Development Workflow

### 1. Find or Create an Issue

Before starting work:

- Browse [existing issues](https://github.com/HomericIntelligence/Myrmidons/issues)
- Comment on an issue to claim it before starting work
- Create a new issue if one doesn't exist for your contribution

### 2. Branch Naming Convention

Create a feature branch from `main`:

```bash
git checkout main
git pull origin main
git checkout -b <issue-number>-<short-description>

# Examples:
git checkout -b 20-add-research-agent-manifest
git checkout -b 15-update-worker-resource-limits
```

**Branch naming rules:**

- Start with the issue number
- Use lowercase letters and hyphens
- Keep descriptions short but descriptive

### 3. Commit Message Format

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```text
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**

| Type       | Description                |
|------------|----------------------------|
| `feat`     | New feature                |
| `fix`      | Bug fix                    |
| `docs`     | Documentation only         |
| `style`    | Formatting, no code change |
| `refactor` | Code restructuring         |
| `test`     | Adding/updating tests      |
| `chore`    | Maintenance tasks          |

**Example:**

```bash
git commit -m "feat(agents): add research-worker agent manifest

Defines a new research worker agent with pull-based NATS
subscription on hi.research.> and MaxAckPending=1.

Closes #20"
```

## Validation and Testing

```bash
# Validate all manifest schemas
just validate

# Preview what would be applied (dry run)
just plan

# Apply manifests to a specific host (requires Agamemnon)
just apply <HOST>
```

## Drift detection

The reconciler compares these fields between desired YAML state and actual Agamemnon state:

| Field | Checked for drift |
|-------|------------------|
| `spec.label` | ✓ |
| `spec.program` | ✓ |
| `spec.workingDirectory` | ✓ |
| `spec.programArgs` | ✓ |
| `spec.taskDescription` | ✓ |
| `spec.tags` | ✓ (order-insensitive) |
| `spec.owner` | ✓ |
| `spec.role` | ✓ |
| `spec.desiredState` | ✓ (drives WAKE/HIBERNATE) |
| `spec.deployment.type` | ✓ |

Fields NOT currently tracked (no drift detection): `spec.model`, `spec.deployment.docker.*`

## Pull Request Process

### Before You Start

1. Ensure an issue exists for your work
2. Create a branch from `main` using the naming convention
3. Implement your changes
4. Run `just validate` to verify manifest schemas

### Creating Your Pull Request

```bash
git push -u origin <branch-name>
gh pr create --title "[Type] Brief description" --body "Closes #<issue-number>"
```

**PR Requirements:**

- PR must be linked to a GitHub issue
- PR title should be clear and descriptive
- `just validate` must pass

### Never Push Directly to Main

The `main` branch is protected. All changes must go through pull requests.

## Code Review

### What Reviewers Look For

- **Valid YAML schema** — Does `just validate` pass?
- **No hardcoded secrets** — Are credentials referenced via environment variables?
- **Agent types** — Are agent type names consistent with existing conventions?
- **Privilege levels** — Is the agent requesting minimum necessary privileges?
- **Resource limits** — Are CPU/memory limits reasonable?

### Responding to Review Comments

- Keep responses short (1 line preferred)
- Start with "Fixed -" to indicate resolution

## Markdown Standards

All documentation files must follow these standards:

- Code blocks must have a language tag (`yaml`, `bash`, `text`, etc.)
- Code blocks must be surrounded by blank lines
- Lists must be surrounded by blank lines
- Headings must be surrounded by blank lines

## Reporting Issues

### Bug Reports

Include: clear title, steps to reproduce, expected vs actual behavior, relevant manifest snippets.

### Security Issues

**Do not open public issues for security vulnerabilities.**
See [SECURITY.md](SECURITY.md) for the responsible disclosure process.

## Code of Conduct

Please review our [Code of Conduct](CODE_OF_CONDUCT.md) before contributing.

---

Thank you for contributing to Myrmidons!
