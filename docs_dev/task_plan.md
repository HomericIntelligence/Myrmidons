# Task Plan

## Goal

Produce a repository-grounded implementation plan for GitHub issue #765 without
changing repository implementation files or posting to GitHub.

## Phases

- [x] Read the applicable planning skill and repository instructions.
- [x] Inspect current workflows, merge-queue policy, fixtures, tests, and docs.
- [x] Determine the exact implementation delta and verification commands.
- [x] Deliver the complete plan in the required markdown structure.

## Key Questions

- Which workflows currently supply the seven required contexts?
- How are special workflow conditions preserved for `merge_group` events?
- What focused offline contract tests and staged activation artifacts belong here?
- Which live activation/evidence steps must remain gated and operator-executed?

## Errors Encountered

| Error | Attempt | Resolution |
|---|---:|---|
| zsh rejected unmatched `.github/workflows/*.yaml` glob | 1 | Use `find`/`rg --files` to enumerate exact workflow paths before reading them. |
