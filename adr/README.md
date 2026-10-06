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
| [0005](0005-plan-format-and-critic.md) | The service plan format, cited to its spec by digest, and a plan critic split into a mechanical gate and a judging agent | Proposed |
| [0006](0006-problem-document-convention.md) | One problem-document convention: a URN `type`, snake_case codes, a shared vocabulary, `validation_failed` for every 400 | Accepted |
| [0007](0007-pipeline-driver.md) | The pipeline driver and chain: one session headless in the service repo, judged by the gate the workflow runs, retried within a cap, bounded by two ceilings | Proposed |
| [0008](0008-auto-merge-and-the-reader.md) | Auto-merge: one decision script, autonomy granted by risk class, and the reader reads every session before it can land | Proposed |
| [0009](0009-configuration.md) | Every option in one registry, set in a reviewed `.xal/factory.conf`, with a default; switches act on the forge through the CLI | Proposed |

> **Provenance.** These decisions were made and proven in the author's private repositories
> before this repo existed, and are re-recorded here with the product-specific context
> removed: 0001 to 0004 on 2026-09-20, 0005 to 0008 on 2026-10-05. The original dates are
> given in each record, and each lifted file is listed in
> [`../docs/lift-ledger.md`](../docs/lift-ledger.md). A record that is Proposed at its source
> arrives Proposed here.
