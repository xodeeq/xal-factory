# Process Architecture Decision Records

Decisions that govern the **process repo itself** and bind every repo that follows the
process — as opposed to any single repo. Each captures one decision as
**Context → Decision → Consequences**, following [`../spec/adr-discipline.md`](../spec/adr-discipline.md).

Repo-level decisions (a service's bounded context, data store, stack, …) live in *that
repo's* `docs/adr/`, not here. A decision lands here only when it binds **every** repo or
the process's own machinery.

| # | Decision | Status |
|---|---|---|
| [0001](0001-process-repo-and-sync-model.md) | Process repo structure + the template/sync consumption model: one spec, vendored read-only and pinned, drift surfaced as a red gate and a reviewable diff | Accepted |
| [0002](0002-repo-seeding.md) | Repo seeding: a new repo begins with its gate. `scaffold/` is `common/` + `lang/<language>/` + a seeder; the language has no default; seeded files are owned, not synced | Accepted |
| [0003](0003-claude-config-boundary.md) | The `.claude/` boundary: a plugin-distributed normative core (the ritual, the skills) plus a repo-owned overlay; the sync manifest is not extended to `.claude/` | Accepted |
| [0004](0004-declared-gate-inputs.md) | Gate inputs are declared data: a manifest, a meta-gate that needs no inputs and checks every caller, and a credential that declares its expiry | Accepted |

> **Provenance.** These decisions were made and proven in the author's private repositories
> before this repo existed, and are re-recorded here on 2026-09-20 with the product-specific
> context removed. The original dates are given in each record.
