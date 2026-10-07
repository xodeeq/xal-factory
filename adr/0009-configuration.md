# ADR-0009: Every option in one registry, set in a reviewed file, with a default

- **Status:** Proposed
- **Date:** 2026-10-06
- **Deciders:** Process maintainer

## Context

The factory's features (the driver, the chain, auto-merge, the reader, the models, the
budgets, the deploy target, the nudge, the idea inbox) were each switched on a different
surface in the estate it came from: some by enabling a workflow in the forge's settings,
some by a literal in a workflow file, some by a repository variable, some by a field in a
plan. Nobody could list them, a new adopter could not find them, and a setting changed in a
settings page left no trace in review. The owner's rule is that every option ships with a
default and that the person installing it is shown each default and how to change it later.

## Decision

1. **One registry, `factory/options.tsv`.** Every option has a key, a default, its choices,
   its scope (each service repo, or the ops repo), how it takes effect, whether onboarding
   asks it, one line on what it does, and how to change it later. The onboarding, `xal-factory
   config`, the defaults every seeded repo reads and the docs all read this one file.
2. **Values live in `.xal/factory.conf`, in the repo, reviewed like code.** The seeder writes
   `.xal/factory.defaults` from the registry; a repo sets only what differs. `.xal/` is a
   protected path, so a driven session cannot widen its own autonomy. Unknown keys are refused,
   because a misspelt key that falls back to its default reads as configured and is not.
3. **Two exceptions, stated:** `runs-on` and `timeout-minutes` are evaluated before any step
   can read a file, so the runner stays the `XAL_RUNNER` repository variable, recorded in the
   conf as `ci.runner` and applied by the CLI.
4. **A switch is a key that also acts.** An option whose `apply` is `workflow:<file>` is
   enforced by that workflow being enabled or disabled; `xal-factory apply` makes the forge
   match the conf, and `doctor` reports any difference. Disabled workflows stay committed, so
   their fixtures keep proving them.
5. **The ops repo's conf is the factory profile.** Service options set there are the starting
   values for every service `xal-factory seed` creates.
6. **Auto-merge off is a disabled `merge.yml`, not an unset level.** The driver refuses
   `autonomy_level: unset` (ADR-0008), so with `pipeline.auto_merge = off` the planner writes
   `code-only` and the merge workflow is disabled.

## Consequences

- Gate 11 holds the registry whole: every default valid, every key a script reads registered,
  every registered key read by something shipped.
- A repo seeded before an option existed does not know it, which is the seed model: the repo
  owns what it was seeded with, and `xal-factory doctor` names what it lacks.
- A plan's values are copied from the conf at planning time and approved with the plan, so a
  conf change applies to plans emitted afterwards, never to an approved one.
