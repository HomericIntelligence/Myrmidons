# AGENTS.md — Agent Safety Boundaries

This document defines behavior boundaries, permitted tools, scope limitations,
coordination rules, safety constraints, and escalation paths for AI agents
operating in this repository.

**Audience:** AI agent runtimes (Claude Code, loop agents, fleet orchestrators).
**Developer context:** See [CLAUDE.md](CLAUDE.md) for naming conventions, YAML format, and validators.
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
| Run linters and tests via `pixi run` and `just` | Modify `.github/workflows/` without human review |
| Create commits and open pull requests | Force-push or rewrite published history |

---

## Permitted Actions

- Read any file in the repository
- Write YAML agent definitions in `agents/<host>/<label>.yaml`
- Write YAML fleet definitions in `fleets/`
- Edit JSON schemas in `schemas/` and dataset validators in `scripts/` (with human review for non-trivial changes)
- Run `pixi run lint`, `pixi run test`, `just validate`, `just test`
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
and system operations without approval. It is **prohibited** in agent/fleet
YAML `programArgs` unless a suppression annotation is present on the same line:

```yaml
programArgs: "--dangerously-skip-permissions" # skip-permissions-lint: <justification>
```

The justification must state why the flag is required and what compensating
controls exist (e.g., ephemeral container, read-only mount, job timeout).

Enforcement: `scripts/check-dangerous-flags.sh` runs as a pre-commit hook and
in CI on every PR.

---

## Fleet Coordination

- Fleet YAMLs in `fleets/` reference agents by filename stem.
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

## Verification Commands

Run these before opening a pull request:

```bash
# Validate every agent/fleet YAML against the schema
just validate

# Run the full validator test suite
just test

# Run every linter (shellcheck, yamllint, schema-hint check, etc.)
pixi run lint

# Check for dangerous-flags policy violations explicitly
bash scripts/check-dangerous-flags.sh

# Validate required H2 sections in AGENTS.md (run before editing this file)
pixi run --environment lint lint-agents-md
```
