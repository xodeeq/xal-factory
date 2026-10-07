# CLAUDE.md — the Xal Software Factory repo (living source of truth)

This file is the durable context for working **in the process repo itself**. For a
*consuming* repo's context, see that repo's own `CLAUDE.md`, seeded from
`scaffold/common/CLAUDE.md.template`.

## What this repo is

The canonical home of a **language-agnostic** software factory: the spec repos vendor, the
lifecycle from a one-line idea to a monitored service, the scaffolds that seed a service repo
(with its gate and its pipeline) and the factory's ops repo, the sync mechanism, and the
plugin that carries the session ritual and the reader to Claude Code. The governing rule
([ADR-0001](adr/0001-process-repo-and-sync-model.md)): **this repo owns the SPEC; each
consuming repo owns its language's IMPLEMENTATION.** See [README.md](README.md) and
[PRINCIPLES.md](PRINCIPLES.md).

## Start here (every session)

1. Read the latest handoff in `docs/sessions/` (highest number) and any brief in
   `docs/briefs/`. The `/begin-session` command runs this ritual.
2. Restate the laws below. Run `scripts/check.sh` before you push.
3. One concern per session; wrap with `/wrap-session`.

## The prime directive when editing `spec/`

**No language-specific token may become a normative statement.** Every rule in `spec/` must
be stated language-agnostically. A concrete example is allowed *only* inside a labelled
citation: a `**Reference:**` / `**Reference.**` region, a paragraph carrying
`<!-- reference -->`, or a whole file marked `<!-- informative` in its first ten lines (the
lifecycle guide, which names tools by design). The leak pattern lives in one place,
`LEAK_RE` in `scripts/check.sh`; gate 1 applies it. If a rule can only be expressed in one
language's terms, it is not a process rule yet — it belongs in that repo.

## What is canonical here vs what is a copy

| Asset | Canonical home | Notes |
|---|---|---|
| the spec: lifecycle guide, service and deployment conventions, gate discipline, ADR + concept + session discipline | **`spec/`** | the forward source of truth; vendored read-only into consumers' `docs/process/` |
| the gate-input checker | **`.xal/check-gate-inputs.sh`** | copied into every seeded repo by the seeder; change it here and re-copy, never edit a seeded copy |
| a seeded repo's gate script, CI, fixtures | **that repo** | a starting point it owns ([ADR-0002](adr/0002-repo-seeding.md)); not synced |
| the session ritual commands, skills and the reader agent | **`plugins/xal-factory/`** | distributed as a plugin ([ADR-0003](adr/0003-claude-config-boundary.md)); a repo's `.claude/` holds only what is true of that repo. The reader is pinned by release tag `xal-factory--v<VERSION>`, cut only after `reader-eval.yml` is green |
| the pipeline: driver, chain, merge, reader workflows and `scripts/driver/` | **`scaffold/common/`** | seeded into every service ([ADR-0007](adr/0007-pipeline-driver.md), [ADR-0008](adr/0008-auto-merge-and-the-reader.md)); proven here by seeding a repo and running `gates/driver.test.sh` |
| every option, its default, and how to change it | **`factory/options.tsv`** | read by `bin/xal-factory`, the seeders (which write each repo's `.xal/factory.defaults`), the docs, and gate 11 ([ADR-0009](adr/0009-configuration.md)); a repo sets only what differs, in `.xal/factory.conf`, read by `scaffold/common/scripts/driver/config.sh` |
| the documentation site | **`site/`** | most pages are generated from `spec/`, `adr/`, `PRINCIPLES.md` and `docs/adopting.md` by `site/scripts/sync-content.mjs` (gitignored copies), the options page by `site/scripts/options-page.sh` (gate 14); built and link-checked by `.github/workflows/site.yml`, which deploys `main` to factory.getxal.com. Edit the source file, never the generated page |
| the installer and the CLI | **`install.sh`, `bin/xal-factory`** | bash 3.2 and later, no other runtime; gate 12 runs them end to end, gate 13 shellchecks them |
| the ops repo: spec intake, the plan critic, status, the nudge, the agents | **`scaffold/ops/`** | seeded once per factory by `scaffold/seed-ops.sh`; gate 10 seeds one and runs its gate on every build |
| what was lifted from the source estate, and when | **`docs/lift-ledger.md`** | one row per lifted file; the input to the next lift |

## Versioning the spec

`VERSION` (semver) is what consumers pin to. Bump it whenever a `spec/` change should
propagate, and tag the commit `v<VERSION>`:

- **patch** — clarifications and typos, no new obligation on consumers;
- **minor** — a new convention or an additive requirement;
- **major** — a breaking change to an existing convention (consumers must act).

The sync mechanism (`sync/`) compares a consumer's pinned version against this file to
detect drift. A `spec/` change breaks every consumer's drift gate until it re-syncs; bump
deliberately. Changes to `scaffold/`, `plugins/`, `scripts/` or `adr/` do not bump it.

## How we work here

- **This repo is docs/tooling/process** — there is no application and no TDD gate. Its
  quality bar is `scripts/check.sh`, which CI runs verbatim. **The script is the list of
  gates**; read the names off it, never off a prose tally, which goes stale the moment a
  gate is added and nothing fails when it does.
- **Every gate has a fixture.** `gates/check.test.sh` overlays one committed fixture per
  gate onto a throwaway copy of the repo and asserts the gate fails naming itself; the seed
  gates have their own harness in `gates/seed.test.sh`. A change to a gate changes its
  fixture in the same PR. See `spec/gate-discipline.md` §5.
- **Gate inputs are declared.** `.xal/gate-inputs` declares every input `check.sh` needs;
  gate 0 asserts `ci.yml` supplies each one. Adding a tool to a gate without a row there
  fails locally before push.
- **The session ritual applies here too.** Sessions wrap with a handoff in
  `docs/sessions/NN.md`; lessons go in `docs/lessons.md`. Eat the dog food.
- **ADRs govern this repo.** A structural decision about the process (the sync model, the
  scaffold shape, the versioning policy, a new gate rule) is recorded in `adr/`, following
  `spec/adr-discipline.md`. Ask before creating or changing one.
- **Nothing enters without a caller.** A script, fixture or convention that nothing
  invokes is not ready to land (`spec/gate-discipline.md` §8).
- **Conventional Commits; small logical commits.** Decisions explained in commit bodies or
  ADRs.

## Lifting from the source estate

The factory is lifted by hand from a private estate where each rule was proven first. A lift
is a PR that adds a row per file to `docs/lift-ledger.md` (source, commit, what was stripped,
what was parameterized), reads the source at its `origin/main`, never a local branch, and
keeps the strip gate (gate 8, `.xal/strip-terms`) green. A term the gate does not know yet
and should is added to `.xal/strip-terms` in the same PR. Something the source has that the
factory does not take goes in the ledger's Deferred table with its trigger.

## Adding a language overlay

One PR adding `scaffold/lang/<name>/` with the full artifact set that
`scripts/check-seed-set.sh` enumerates: the gate script in the process's gate order, the
`.xal/gate-inputs` manifest, `ci.yml` invoking the gate and its harness, `deploy.yml`
dispatch-only, and `gates/check.test.sh` with a cheap failing fixture, a failing fixture for
the one gate whose arithmetic is hand-written (coverage), and a clean one. Model it on
`lang/go/`. When the second overlay lands, look hard at the `common/` / `lang/` split:
`ci.yml` is mostly boilerplate and may belong on the other side (ADR-0002 revisit trigger 1).

## Open design decisions

- **A second language overlay.** Go is the only one; the split between `common/` and
  `lang/` has been exercised once, by the language it was designed against.
- **The pipeline has not run live from this repo.** It is proven by fixtures here and by 145
  driver fixtures in a seeded repo, and it ran live for weeks in the source estate. The live
  proof from a factory-seeded repo (one in-class session merges, one out-of-class session
  stops) is owed, and recorded in the next session handoff when done.
- **Telemetry reference implementation.** The Go overlay ships a stub binary, not the
  source's telemetry and HTTP packages (lift ledger, Deferred).
- **Observability IaC modules in the scaffold.** `deployment-conventions.md` Pattern B
  describes reusable modules; none ship yet. Trigger: a seeded service needs deployable
  observability.
