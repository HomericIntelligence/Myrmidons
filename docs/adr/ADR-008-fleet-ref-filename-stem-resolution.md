# ADR-008: Fleet ref Resolution by Filename Stem

**Status:** Accepted
**Date:** 2026-04-28
**Accepted:** 2026-05-03
**Author:** mvillmow

> **Historical note (2026-05-17):** This ADR was written while the reconciler
> lived in Myrmidons. Concrete references below to `scripts/export.sh` and
> `scripts/lib/reconcile.sh` are now in
> [ProjectAgamemnon](https://github.com/HomericIntelligence/ProjectAgamemnon)
> under `tools/reconciler/scripts/`. The contract (fleet `ref:` resolves by
> filename stem) is unchanged and remains the dataset's responsibility —
> `tests/validate-fleet-refs.sh` here enforces it.

---

## Context

Fleet YAML documents list agents via `spec.agents[].ref` entries such as
`ref: hermes/aindrea`. The reconciler must resolve this reference to an agent
YAML file on disk. Each agent YAML has two candidate identifiers that could
serve as the resolution key:

- **`spec.label`** — the human-readable display name (e.g. `Aindrea`). The
  export script derives the filename from this field via `label_to_stem()`
  (`scripts/export.sh:80-83`): lowercase, spaces replaced with hyphens.
- **`metadata.name`** — the ProjectAgamemnon API identifier / tmux session name
  (e.g. `odyssey-mainline-analysis`). This is used by the REST API and scripts
  to identify and operate on agents at runtime.

The reconciler (`scripts/lib/reconcile.sh:210-224`) resolves `ref: hermes/foo`
to `agents/hermes/foo.yaml`. The question is: what does `foo` represent —
the label stem or `metadata.name`?

---

## Decision

Fleet `ref:` entries resolve by **filename stem**, where the filename is derived
from `spec.label` (lowercased, spaces→hyphens) via `label_to_stem()`.

- `ref: hermes/aindrea` → `agents/hermes/aindrea.yaml` (label `Aindrea` → stem
  `aindrea`) ✓
- `ref: hermes/odyssey-mainline-analysis` → `agents/hermes/odyssey-mainline-analysis.yaml`
  would only work if a file with that exact name exists; it is **not** resolved
  by `metadata.name` ✗

This means the filename is the canonical lookup key, and filenames are always
label-derived.

---

## Consequences

### Positive

- Fleet refs are short, human-readable, and stable. Labels like `Aindrea` yield
  stems like `aindrea` — compact and easy to type in fleet YAML.
- Filesystem layout reflects how users think about agents (by label/role), not
  how Agamemnon identifies them internally.
- Renaming an agent in Agamemnon (changing `metadata.name`) does not break
  existing fleet refs as long as the label is unchanged.

### Negative / Trade-offs

- A reader who knows only `metadata.name` cannot construct the correct `ref:`
  without also knowing the label. The mapping is documented in `CLAUDE.md` but
  not enforced by tooling.
- If `spec.label` changes, the filename must be renamed and all fleet `ref:`
  entries updated. The tooling does not auto-detect this rename.

### Neutral

- The `label_to_stem()` function in `scripts/export.sh` is the single source of
  truth for the label→stem conversion. Any future change to that function
  requires auditing all existing filenames.

---

## Alternatives Considered

### A. Resolve by `metadata.name`

**Rejected.** `metadata.name` values are Agamemnon API identifiers optimized
for backend uniqueness, not human readability. They are often long compound
strings (e.g. `odyssey-mainline-analysis`) that reflect Agamemnon's internal
naming conventions, not the agent's purpose. Coupling filesystem paths to API
identifiers makes renaming agents in Agamemnon a breaking change in the
repository layout. It also contradicts the export convention, which already
derives filenames from labels.

### B. Introduce an explicit `ref` field in each agent YAML

**Rejected.** Adding a third identifier (beyond `metadata.name` and
`spec.label`) would create a new sync-drift risk: three values must be kept
consistent. The label-derived filename is deterministic and requires no
additional field. A dedicated `ref` field would also make the schema more
complex with no corresponding benefit.

---

## Implementation Scope (this ADR)

| File | Role |
|------|------|
| `scripts/lib/reconcile.sh:210-224` | Ref resolution: `ref: host/name` → `agents/<host>/<name>.yaml` |
| `scripts/export.sh:80-83` | `label_to_stem()` — defines the label→filename mapping |
| `tests/validate-fleet-refs.sh` | Standalone validation script — checks all fleet `ref:` entries resolve to existing files and validates inline agent required fields |
| `tests/validate-schemas.sh` | Calls `validate-fleet-refs.sh` as part of the schema test suite |
| `tests/unit/test_validate_fleet_refs.bats` | BATS unit tests for `validate-fleet-refs.sh` (pass/fail paths, inline agent validation, empty fleet, non-Fleet kind skipping) |
| `.pre-commit-config.yaml` | `myrmidons-validate-fleet-refs` hook runs `validate-fleet-refs.sh` directly on `agents/`/`fleets/` changes; `myrmidons-test-schema` hook calls it indirectly via `just test-schema` |
| `.github/workflows/validate.yml` | Standalone `Fleet ref validation` CI step runs `validate-fleet-refs.sh` directly (in addition to the `just test-schema` step that calls it indirectly) |
| `CLAUDE.md` | Documents the naming convention and the ref resolution rule |
