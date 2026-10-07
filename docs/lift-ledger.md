# Lift ledger

Every file in this repo that was lifted from the private estate the factory was extracted
from has one row here: where it came from, at which commit, and what was changed on the way
in. This is the record of how current the factory is, and the input to the next lift.

Gate 8 (`scripts/check.sh`, the strip-terms gate) exempts this file and only this file
outside the fixtures, because naming each file's source is its job.

## Sources

Each source is read at `origin/main`, never at a local branch.

| Source | Commit | Read on |
|---|---|---|
| xal-platform | 62153f5 | 2026-10-05 |
| xal-company | f5aaed1 | 2026-10-05 |
| xal-org | 7737215 | 2026-10-05 |
| xal-auth | 802fc04 | 2026-10-05 |
| xal-invoicing | f271772 | 2026-10-05 |

The first extraction (2026-09-20, commit e651c57 here) predates this ledger. Its sources
are recorded in [`docs/sessions/01.md`](sessions/01.md).

## Rows

Format: `source:path` → `factory path` · stripped · parameterized.

| Source | Factory path | Stripped | Parameterized |
|---|---|---|---|
| xal-platform:spec/service-conventions.md (3dca6ba, §9) | spec/service-conventions.md §9 | the auth reference citation; "catalogue" | — |
| xal-platform:spec/service-conventions.md (400bef0, §10) | spec/service-conventions.md §10 | the invoicing reference; unit names in examples | `urn:xal:<unit>` → `urn:<org>:<service>` |
| xal-company:docs/ops/system-plan-2026-09-20.md §2 | spec/session-types.md | the person, repo names, the retired lab, state-today column | "the owner", "ops repo", "service repo" |
| xal-company:docs/adr/0008 + 0009 + 0010, specs/README.md | spec/lifecycle.md (new, synthesized) | — | — |
| xal-company:docs/adr/0008-service-plan-format-and-critic.md | adr/0005-plan-format-and-critic.md | roadmap stage names, repo and PR links, the person | condensed |
| xal-platform:adr/0009-problem-document-convention.md | adr/0006-problem-document-convention.md | the per-unit audit table, follow-ups | condensed |
| xal-company:docs/adr/0009-pipeline-driver-v0.md | adr/0007-pipeline-driver.md | run ids and costs, repo names, the PAT name, amendments as history | condensed; decisions renumbered |
| xal-company:docs/adr/0010-pipeline-auto-merge.md | adr/0008-auto-merge-and-the-reader.md | the label name, the plugin name, the token name | `needs-<owner>` → escalation label |

## Deferred

Things the source has that the factory does not take yet, each with the trigger that would
bring it in. Nothing enters without a caller.

| Source | What | Trigger |
|---|---|---|
| xal-platform:adr/0002 (event envelope) | already carried by spec §7 | an adopter asks for the envelope schema as data |
| xal-platform:adr/0003, 0005 (visibility, feed credential) | product-specific | none |
| xal-platform:adr/0006, 0007, 0008 | already re-recorded as adr/0002, 0003, 0004 on 2026-09-20 | none |
| xal-company:docs/adr/0001-0004, 0006, 0007 | product or company specific | none |
