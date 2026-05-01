# AGENTS.md — Agent Safety Boundaries

This document defines behavior boundaries, permitted tools, scope limitations, coordination rules, safety constraints, and escalation paths for AI agents operating this repository.

**Audience:** AI agent runtimes (Claude Code, loop agents, fleet orchestrators).
**Developer context:** See [CLAUDE.md](CLAUDE.md) for naming conventions, YAML format, drift detection, and environment variables.

---

## Scope

This repository manages *desired* agent state as YAML under `agents/`. Agents operating here must stay within that scope:

| In scope | Out of scope |
|----------|--------------|
| Read and write agent YAML files in `agents/` | Modify ProjectAgamemnon source code |
| Read and write fleet YAML files in `fleets/` | Manage container image definitions (→ AchaeanFleet) |
| Run `scripts/plan.sh`, `scripts/status.sh`, `scripts/apply.sh` | Call the Agamemnon REST API directly with `curl` (bypass scripts) |
| Run linters via `pixi run` | Modify `.github/workflows/` without human review |
| Create commits and open pull requests | Force-push or rewrite published history |

---

## Permitted Actions

- Read any file in the repository
- Write YAML agent definitions in `agents/<host>/<label>.yaml`
- Write YAML fleet definitions in `fleets/`
- Run `./scripts/plan.sh` (dry-run, read-only)
- Run `./scripts/status.sh` (read-only)
- Run `./scripts/apply.sh` **without** `--prune` (see Escalation below)
- Run `./scripts/check-dangerous-flags.sh`
- Run linters: `pixi run --environment lint lint-shell`, `pixi run --environment lint lint-yaml`
- Create git commits and push branches
- Open pull requests

---

## Prohibited Actions

- **Direct Agamemnon API calls** — all API interactions must go through the scripts in `scripts/`. Never construct raw `curl` calls to `$AGAMEMNON_URL`.
- **Committing secrets** — never commit `AGAMEMNON_API_KEY`, tokens, certificates, or any credential. Use environment variables or GitHub secrets.
- **`--dangerously-skip-permissions` without annotation** — see policy below.
- **Force-push** — `git push --force` and `git push --force-with-lease` are prohibited. Create a new commit instead.
- **Skipping pre-commit hooks** — never use `--no-verify`. If a hook fails, fix the underlying issue.
- **Modifying CI workflows** — changes to `.github/workflows/` require human review before merging.
- **Modifying `scripts/`** — changes to reconciler scripts require human review.
- **`--prune` flag on `apply.sh`** — deletes agents not present in YAML; requires explicit human confirmation before running.

---

## `--dangerously-skip-permissions` Policy

This flag disables all permission prompts and allows arbitrary file, network, and system operations without approval. It is **prohibited** in agent/fleet YAML `programArgs` unless a suppression annotation is present on the same line:

```yaml
programArgs: "--dangerously-skip-permissions" # skip-permissions-lint: <justification>
```

The justification must state why the flag is required and what compensating controls exist (e.g., ephemeral container, read-only mount, job timeout).

Enforcement: `scripts/check-dangerous-flags.sh` runs as a pre-commit hook and in CI on every PR.

---

## Fleet Coordination

- Agents in a fleet execute independently with no shared mutable state.
- Each agent owns its own working directory (`spec.workingDirectory`).
- Do not write to another agent's working directory.
- Do not create agent YAML files that reference `metadata.name` values already in use without first checking `./scripts/status.sh`.
- Conflicts between concurrent agents must be escalated to the human operator.

---

## Escalation — Human Review Required

Pause and request human confirmation before proceeding with any of the following:

1. Running `./scripts/apply.sh --prune` (irreversible agent deletion)
2. Adding or modifying files in `.github/workflows/`
3. Adding or modifying files in `scripts/`
4. Adding a `# skip-permissions-lint:` suppression annotation
5. Any action that would affect agents outside the current host directory
6. Any ambiguous or conflicting desired-state changes (e.g., two fleet entries targeting the same agent with different states)

---

## Verification Commands

Run these before opening a pull request:

```bash
# Check for dangerous-flags policy violations
./scripts/check-dangerous-flags.sh

# Shell lint
pixi run --environment lint lint-shell

# YAML lint
pixi run --environment lint lint-yaml

# Dry-run reconciliation (requires Agamemnon running)
./scripts/plan.sh
```
