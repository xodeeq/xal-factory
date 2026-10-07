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
| xal-platform:scaffold/common/.github/workflows/{driver,chain,merge,reader}.yml | scaffold/common/.github/workflows/ | repo, person, run ids, roadmap stage names, the private platform checkout | ops repo, escalation label, models, turn caps, process repo, reader tag via `.xal/factory.conf`; tokens renamed FACTORY_READ_TOKEN and FACTORY_WRITE_TOKEN; reader status `factory/reader`; the `model` input no longer defaults, so chained runs use the configured model |
| xal-platform:scaffold/common/scripts/driver/*.sh | scaffold/common/scripts/driver/ | the same | `fetch-spec.sh` takes `owner/repo:path` or falls back to the ops repo's owner; `merge-decision.sh` protects `docs/process/` (the vendored spec here) instead of `docs/platform/` |
| (new) | scaffold/common/scripts/driver/config.sh | — | reads `.xal/factory.conf`, a default for every key, unknown keys refused |
| xal-platform:scaffold/common/gates/driver.test.sh + _fixtures/ | scaffold/common/gates/ | names, approver | fixture spec digest recomputed after stripping |
| xal-platform:scaffold/lang/go/.github/actions/toolchain, .xal/protected-paths | scaffold/lang/go/ | run history | — |
| xal-platform:scaffold/{seed-service.sh,README.md,common,lang/go} (3-way merge from 27dfe29) | scaffold/ | the private-platform read token, the Mac runner, the board token | `--ops-repo`, `.xal/factory.conf`, `<VERSION>` placeholder |
| xal-platform:scripts/check-seed-set.sh + gates/fixtures/seed | scripts/, gates/fixtures/seed/ | — | rule 5 requires `scripts/driver/config.sh`; `run-session.md` ships in the plugin, not common/ |
| xal-platform:scaffold/common/.claude/commands/run-session.md | plugins/xal-factory/commands/run-session.md | the workspace repo, the person, stage names | adds the dispatch step it lacked |
| xal-company:plugins/xcos-core/agents/reader.md | plugins/xal-factory/agents/reader.md | company frontmatter, requirement id | — |
| xal-company:plugins/xcos-core/commands/{explain,idea}.md | plugins/xal-factory/commands/ | version marker; the company repo | `/idea` finds the ops repo from env, conf, or the current repo |
| xal-company:specs/{README,TEMPLATE}.md, scripts/spec-intake-check.sh, gates/spec-intake.test.sh + fixtures | scaffold/ops/specs/, scripts/, gates/ | the person, the units, the frontmatter-schema history, the slugs file | fixture ledgers recomputed after stripping; deliberate mismatches kept |
| xal-company:scripts/plan-critic-check.sh, gates/plan-critic.test.sh + fixtures | scaffold/ops/scripts/, gates/ | the roadmap, the person, principle numbers | `spec_admitted_at` examples name `factory-ops` |
| xal-company:scripts/status-render.sh, tests/status-render.test.sh + fixtures, .github/workflows/nudge.yml, gates.yml | scaffold/ops/ | locale, history, the claude CLI step | the status template ships with placeholders |
| xal-company:.claude/agents/{planner,plan-critic,adr-critic,idea-triage}.md; workspace .claude/agents/{research,system}.md | scaffold/ops/.claude/agents/ | company frontmatter, pattern codes, principle numbers, the person, product ids | the decision map is the `decision-map` label |
| (new) | scaffold/seed-ops.sh, scaffold/ops/{scripts/check.sh,gates/check.test.sh,CLAUDE.md.template,status/current.md,.xal/gate-inputs} | — | an empty intake tree passes with a printed notice, and only when the ledger is empty too |
| xal-auth:.github/workflows/deploy.yml, fly.toml, scripts/smoke.sh | scaffold/lang/go/.github/workflows/deploy.yml (adapter), scaffold/common/deploy/fly.toml.example, scaffold/common/scripts/smoke.sh | the app name and URL, the .NET listeners, the token lifecycle checks | `deploy.target` and `deploy.url`; the smoke proves health and the §10 problem document, service checks go in `scripts/smoke.d/`; FLY_API_TOKEN gets a gate-inputs row, which the source lacked |
| xal-org:docs/runbook-alerts.md | scaffold/common/docs/runbook-alerts.md | the unit's alerts | a template, "documents, not wiring" |
| xal-company:scripts/reader-eval.sh, gates/reader-eval.test.sh, gates/fixtures/reader, .github/workflows/reader-eval.yml | same paths | plugin name, run id | gate 9 here |

## Deferred

Things the source has that the factory does not take yet, each with the trigger that would
bring it in. Nothing enters without a caller.

| Source | What | Trigger |
|---|---|---|
| xal-platform:adr/0002 (event envelope) | already carried by spec §7 | an adopter asks for the envelope schema as data |
| xal-platform:adr/0003, 0005 (visibility, feed credential) | product-specific | none |
| xal-platform:adr/0006, 0007, 0008 | already re-recorded as adr/0002, 0003, 0004 on 2026-09-20 | none |
| xal-company:docs/adr/0001-0004, 0006, 0007 | product or company specific | none |
| xal-platform:scaffold/common/.github/workflows/board-add.yml | dropped at the first extraction and still dropped | `ops.board = github-projects` gains a caller |
| xal-org:internal/platform/{telemetry,httpx} | about 3,600 lines with OTel and Prometheus dependencies; the seeded binary is a deliberate stub, so this would make the scaffold a framework | a second Go service would copy it, or an adopter asks for a reference implementation |
| xal-auth:infra/observability (pattern B) | an open decision in the factory too | a target with a monitoring stack is chosen |
| xal-company:.claude/agents/{chief-of-staff,process-engineer}.md | no caller yet | the improvement session is built |
| xal-company:scripts/{board.sh,board-hygiene.sh,triage-load.sh,check-replicas.sh,check-unused.sh,frontmatter-check.sh} | no caller yet | `ops.board = github-projects`, a second replica pair, or a document schema |
| xal-company:plugins/xcos-core/commands/wrap-session.md | the factory's own generalized `/wrap-session` (2026-09-20) is kept | a ritual step the factory lacks proves itself |
| xal-org: the three driver scripts that differ from the scaffold | the scaffold copy is canonical; the differences are older copies in that service, pending its re-sync | none |
