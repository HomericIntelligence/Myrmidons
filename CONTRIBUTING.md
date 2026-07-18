# Contributing to Myrmidons

Thank you for your interest in contributing to Myrmidons! This repository is
the source-of-truth **dataset** for the
[HomericIntelligence](https://github.com/HomericIntelligence) distributed agent
mesh — agent and fleet definitions as YAML, plus the schemas and validators
that keep them consistent. Consumers (notably
[ProjectAgamemnon](https://github.com/HomericIntelligence/ProjectAgamemnon))
read this dataset and reconcile their runtime against it.

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
- [Just](https://just.systems/) as the command runner (the task front door)
- [uv](https://docs.astral.sh/uv/) for the Python-based tooling
  (`yamllint`, `jsonschema`, `pre-commit`, …)
- The validator CLI tools, sourced from your OS package manager or release
  binaries:
  - `jq` — `sudo apt-get install jq` (or `brew install jq`)
  - `yq` — the **Go** `yq` (mikefarah): `sudo apt-get install yq`, `brew install yq`,
    or the [release binary](https://github.com/mikefarah/yq/releases)
    (NOT the PyPI `yq`)
  - `bats` — `sudo apt-get install bats` (or `brew install bats-core`)
  - `shellcheck` — `sudo apt-get install shellcheck` (or `brew install shellcheck`)

### Environment Setup

```bash
# Clone the repository
git clone https://github.com/HomericIntelligence/Myrmidons.git
cd Myrmidons

# Install the Python-based tooling (yamllint, pre-commit, jsonschema, …)
uv sync --locked

# Install all git hooks (pre-commit framework including dangerous-flags lint guard;
# see CLAUDE.md § Security for the single canonical policy description)
just install-hooks

# List available recipes
just --list
```

### Verify Your Setup

```bash
# Validate every agent/fleet YAML against the schema
just validate

# Run the full validator test suite
just test
```

## What You Can Contribute

- **Agent manifests** — New YAML agent definitions in the appropriate host directory
- **Manifest schema updates** — Validation rules and schema extensions
- **Validation scripts** — Improvements to `tests/validate-schemas.sh`
- **Justfile recipes** — New provisioning or management commands
- **Pre-commit hooks** — Git hook improvements in `hooks/`
- **Documentation** — README updates, manifest format guides

### CLAUDE.md vs AGENTS.md

This repository ships two context files with distinct audiences:

- **`CLAUDE.md`** — targets human developers and the Claude Code CLI. It documents naming
  conventions, YAML format, drift detection, environment variables, and the quick-start
  workflow. Update this file when you change anything a developer needs to know to work
  with the repository day-to-day.

- **`AGENTS.md`** — targets AI agent runtimes (Claude Code loop agents, fleet
  orchestrators). It defines safety boundaries: permitted actions, prohibited actions,
  escalation rules, and the `--dangerously-skip-permissions` policy. Update this file
  when you add a new operation that agents should or should not perform, or when
  escalation thresholds change.

When adding a new script or policy, ask: does this change what a developer needs to
know? Update `CLAUDE.md`. Does it change what an agent is allowed to do? Update
`AGENTS.md`. Many changes require updating both.

### YAML Manifest Format

Agent manifests are YAML files that describe desired agent state. Reference existing manifests
as examples for the expected schema. Key fields typically include agent type, resource limits,
NATS subject subscriptions, and container image references.

### ADR Lifecycle

ADRs in `docs/adr/` follow this lifecycle:

- **Proposed** — The decision is under active discussion. The ADR file has been
  written but the team has not yet reached consensus.
- **Accepted** — The team has reviewed and agreed to the decision. Update
  `**Status:**` from `Proposed` to `Accepted` and add an `**Accepted:**` date
  line immediately after the existing `**Date:**` line. Also update the status
  column in `docs/adr/README.md`.
- **Deprecated** — The decision is no longer in effect but was not replaced by
  another ADR. Update status to `Deprecated`.
- **Superseded** — The decision has been replaced. Update status to `Superseded`
  and add a `**Superseded by:**` line referencing the new ADR.

To accept an ADR: open a PR that changes the status field, adds the accepted
date, and updates the index table. No special approval process is required
beyond the normal PR review.

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

### Test Antipatterns to Avoid

#### `run ... || true` in BATS files

Never append `|| true` to a BATS `run` line:

```bash
# BAD — $status is meaningless, any subsequent assertion is silently neutered
run some-command --foo bar || true
[ "$status" -eq 0 ]

# GOOD — `run` already captures the exit code into $status
run some-command --foo bar
[ "$status" -eq 0 ]
```

BATS's `run` builtin already captures the command's exit code into `$status`,
so the command can never fail the test. Wrapping it in `|| true` puts it in an
always-zero subshell, so `$status` is permanently 0 and any
`[ "$status" -eq N ]` check silently passes. This antipattern shipped
undetected in Tests 1, 2, and 3 before #398. The general `forbid-or-true`
pre-commit hook blocks the antipattern repo-wide.

Legitimate `|| true` uses in `.bats` files remain allowed for cleanup hooks
(`kill ... || true`) and command substitutions (`x=$(grep -c ... || true)`)
because those do not interact with `run`'s `$status` capture.

## Validation and Testing

```bash
# Validate every agent/fleet YAML against the schema + name uniqueness
just validate

# Run the full validator test suite (bats unit + schema + drift)
just test

# Run every linter (shellcheck, yamllint, schema-hint, dangerous-flags, ...)
just lint
```

Drift detection (what changes consumers should apply on the runtime side) is
defined by the consumer of this dataset — see
[ProjectAgamemnon](https://github.com/HomericIntelligence/ProjectAgamemnon).
This repo's job is to make sure the YAML is well-formed, schema-conformant, and
policy-compliant. What a consumer does with it is the consumer's contract.

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
- **AGENTS.md** — Does this change affect agent permissions or safety boundaries? Update `AGENTS.md` if so.

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
