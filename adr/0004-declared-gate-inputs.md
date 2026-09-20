# ADR-0004: Gate inputs are declared data, and a credential declares its expiry

- **Status:** Accepted
- **Date:** 2026-09-20 (originally decided 2026-08-18 and extended 2026-09-17, re-recorded here on extraction)
- **Deciders:** Process maintainer

## Context

Twice in four days, a gate was added to a repo's gate script that needed something not in
the repo, and a workflow invoking that script was not updated to supply it:

- A service's spec-drift gate needed a sibling checkout and an environment variable. `ci.yml`
  got it; `deploy.yml` did not. `deploy.yml` sets `CI=true`, which makes the gate mandatory,
  so its gate job failed and `needs: gate` blocked production deploys for about three and a
  half hours. CI on the same commit was green.
- The process repo's plugin-manifest gate needed the `claude` CLI. `ci.yml` did not install
  it; the gate failed on its first CI run. A guardrail — "grep every caller before pushing" —
  had been written after the first occurrence, and the second happened with it in place.

The shared root cause is not that the setup is duplicated. It is that a gate's input
requirements are **discovered by execution rather than declared as data**, and the author's
machine satisfies them ambiently (the sibling repo happens to be there, the CLI happens to be
on `$PATH`) while CI must satisfy each one by an explicit step. The authoring environment is
structurally incapable of revealing the obligation CI will enforce, and there is no artifact
for a caller to be checked against. A guardrail is a memory aid attached to nothing, which is
why it failed the second time.

A related gap: a credential's expiry date is an input property no other input has, and it
lived in prose or in someone's memory. A ninety-day token was once issued and its expiry had
to be parked in a status document for want of anywhere better.

## Decision

1. **Inputs are declared as data** in `.xal/gate-inputs`, one record per line:

   ```
   id | detect | required-in-ci | caller-pattern | expires | description
   ```

   `detect` says how the gate script discovers the input (`command:<name>`, `env:<VAR>`,
   `none`); `required-in-ci` says whether the gate fails or skips when it is absent;
   `caller-pattern` is a regex every workflow that invokes the gate script must match, `-`
   for a runner-provided input, or `<workflow>:<regex>` for an input one named workflow
   consumes without invoking the gate script.

2. **A meta-gate checks the declaration against reality and against every caller.**
   `.xal/check-gate-inputs.sh` runs as **gate 0**. It derives what the gate script actually
   requires from its `command -v NAME` and `VAR="${VAR:-default}"` idioms and fails on
   anything undeclared; discovers every workflow invoking the gate script and asserts each
   supplies every required input; and asserts a workflow-scoped record's workflow exists
   and matches. **It requires no inputs of its own** — it reads only files already in the
   repo — because a check that catches missing inputs must not itself be able to have one
   missing. **Zero callers is a failure**, never a pass; a renamed gate script would
   otherwise silently empty the check.

3. **A credential declares its expiry.** `expires` is an ISO date, or `-` for an input that
   cannot expire. There is no silent default, because "nobody filled it in" and "it cannot
   expire" must not look alike. A caller-pattern naming `secrets.` is a credential by
   construction, so `-` is refused there. A past date fails; a date within thirty days
   warns, so the build goes yellow before it goes red.

4. **The canonical copy lives in this repo** and is copied into every seeded repo by the
   seeder. It is never edited in a seeded copy.

### Alternatives considered

**A guardrail in the repo's context file.** Tried; failed on the second occurrence. A rule
that depends on the author remembering to run a grep is attached to nothing.

**Deduplicate the workflows** so there is one place to update. Addresses the symptom: the
outage was not caused by duplication but by an obligation that existed only in the gate
script's code. A single workflow that forgets the input fails identically.

**Detect inputs by running the gate script in a clean container.** Catches the class, at the
cost of a container per local run and a second definition of "clean" to keep true. The
manifest is cheaper, runs in milliseconds, and produces an artifact a caller can be checked
against, which the container approach does not.

## Consequences

- **Positive.** Adding an input without wiring a caller fails the gate locally, at authoring
  time, before push. The first occurrence was replayed by deleting the install step from
  `ci.yml`, and it now fails locally. A credential's rotation becomes a scheduled obligation
  instead of a red checkout.
- **Negative / cost.** Derivation is deliberately incomplete: an input invoked directly
  (a gate that calls its toolchain without `command -v`) is real and undetectable, so a
  declaration with no derived match is a warning, not a failure. The caller check is
  textual: a workflow that checks out a repo without the credential it now needs is not
  caught if the pattern still matches.
- **Negative.** The checker has one copy per seeded repo. Drift between copies is detected
  only by whoever compares them.
- **A property discovered in the build, kept deliberately:** the manifest refuses to hold a
  credential whose consumer does not exist yet — a workflow-scoped record naming a missing
  workflow fails, by the same reasoning as "zero callers is never a pass". A declaration
  that asserts nothing is worse than an honest note elsewhere.
