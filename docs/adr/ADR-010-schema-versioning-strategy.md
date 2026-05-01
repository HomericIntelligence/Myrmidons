# ADR-010: Schema Versioning Strategy (myrmidons/v1)

**Status:** Proposed
**Date:** 2026-04-28
**Author:** mvillmow

---

## Context

Myrmidons defines two YAML document kinds:

- **Agent** — a single agent definition (`agents/<host>/<stem>.yaml`)
- **Fleet** — a group of agents with a shared lifecycle (`fleets/<name>.yaml`)

Both kinds are validated by JSON Schema files in `schemas/`. As the project
evolves, schema changes (new required fields, changed semantics, removed fields)
could silently break existing YAML documents if the tooling cannot distinguish
documents written for different schema generations.

Two design choices must be made:

1. **What versioning field to use** — a freeform string, an integer, or a
   structured `apiVersion` field?
2. **How to scope versions** — one shared version across all kinds, or
   independent versions per kind?

---

## Decision

Both `Agent` and `Fleet` documents share a single `apiVersion: myrmidons/v1`
string, enforced as a JSON Schema `const` in:

- `schemas/agent-v1.schema.json` — `"apiVersion": { "const": "myrmidons/v1" }`
- `schemas/fleet-v1.schema.json` — `"apiVersion": { "const": "myrmidons/v1" }`

Runtime enforcement is applied in `scripts/doctor.sh:215-221`: any YAML document
whose `apiVersion` field is absent or does not equal `myrmidons/v1` is rejected
with an explicit error. No version negotiation or migration logic is performed;
a version mismatch is a hard failure.

When a future breaking schema change requires a new version, the schema files
will be renamed (e.g. `agent-v2.schema.json`) and the `const` updated. Existing
`v1` documents must be migrated explicitly; the tooling will reject them with a
clear message referencing the expected version.

---

## Consequences

### Positive

- Version mismatches are caught immediately at validation time, not silently
  at apply time when a missing or renamed field would produce an incorrect API
  call.
- The `apiVersion`/`kind` pattern follows Kubernetes conventions, which most
  infrastructure engineers recognize. The learning curve for new contributors
  is reduced.
- A single shared version is unambiguous: there is no question of whether
  `agent/v2` and `fleet/v1` are compatible.

### Negative / Trade-offs

- If `Agent` and `Fleet` schemas evolve at different rates, a breaking change to
  one kind forces a version bump for both (under the shared-version model), or
  requires moving to per-kind versioning. This is a future migration decision,
  not a current problem.
- The `const` constraint in JSON Schema is strict: any document with
  `apiVersion: myrmidons/v2` will fail validation against the v1 schema even if
  no fields have changed. Migration tooling will be required for any version
  increment.

### Neutral

- Schema filenames (`agent-v1.schema.json`, `fleet-v1.schema.json`) embed the
  version, so adding a v2 schema does not require renaming or removing the v1
  file. Both can coexist during a migration window.

---

## Alternatives Considered

### A. Per-kind versioning (`agent/v1`, `fleet/v1`)

**Rejected.** There is no current need for `Agent` and `Fleet` schemas to
version independently. Maintaining two version constants (and two validation
code paths) adds complexity with no current benefit. If independent versioning
becomes necessary in the future, it can be introduced at that point with a
concrete motivation.

### B. Integer version field (`version: 1`)

**Rejected.** An integer field is less portable and less recognizable. The
`apiVersion`/`kind` pattern is a well-established convention in the Kubernetes
ecosystem and in tools like Argo, Flux, and Helm. Using a recognized pattern
reduces the documentation burden for contributors who have worked with those
tools. An integer `version` field also lacks the namespace component
(`myrmidons/`) that disambiguates this schema from other YAML formats that might
be present in the same repository.

### C. No versioning field

**Rejected.** Without a version field, the tooling cannot distinguish a v1
document from a hypothetical v2 document. Any future schema change that adds
required fields or changes semantics would either silently accept malformed v1
documents (if the new field has a default) or produce confusing errors (if it
does not). Explicit versioning makes schema evolution possible without breaking
backward compatibility silently.

---

## Implementation Scope (this ADR)

| File | Role |
|------|------|
| `schemas/agent-v1.schema.json` | JSON Schema for Agent kind; enforces `apiVersion: myrmidons/v1` via `const` |
| `schemas/fleet-v1.schema.json` | JSON Schema for Fleet kind; enforces `apiVersion: myrmidons/v1` via `const` |
| `scripts/doctor.sh:215-221` | Runtime enforcement: rejects documents with wrong or missing `apiVersion` |
| `scripts/lib/reconcile.sh` | Reads YAML fields after schema validation passes |
