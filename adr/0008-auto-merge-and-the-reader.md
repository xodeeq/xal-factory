# ADR-0008: Auto-merge: a driven session lands when every gate is obeyed, and the reader reads first

- **Status:** Proposed
- **Date:** 2026-10-05 (originally decided 2026-09-25 and promoted to the scaffold 2026-09-27, re-recorded here on the second lift)
- **Deciders:** Process maintainer

## Context

With a driver and a chain ([ADR-0007](0007-pipeline-driver.md)) a plan continues on its own,
but every session still stopped for a person to merge it. The owner's ruling was that a
driven session may merge with no human push **provided every gate that applies to a PR is
obeyed**, and that speed is never bought by loosening a check.

Three facts constrain how that can be built:

1. **Branch protection may not be available.** On some plans and private repos it is not, so
   there are no required checks, no merge queue and no native auto-merge. Every guarantee
   has to come from the pipeline itself.
2. **CI runs the head's own gate.** A session that weakened its gate would be judged by the
   gate it weakened.
3. **The gate cannot see everything that matters**: a test that proves nothing, a cited
   clause that nothing realises. A merge must not race the reviewer.

## Decision

1. **Merging is its own workflow, `merge.yml`**, separate from the driver and the chain. It
   fires on a successful driver run, or by dispatch as the re-entry path. The chain never
   merges, because a second merge site would ask none of the questions below.
2. **One script says yes, `merge-decision.sh`**, and the first failure is a named refusal:
   1. The head's plan differs from `main`'s only in this session's `status` and `evidence`.
   2. No path in `.xal/protected-paths` (the gate, fixtures, workflows, declared inputs,
      vendored spec, the overlay's tool configuration) changes unless `main`'s plan lists it
      among the session's artifacts.
   3. The session's status on the head is `passed`.
   4. `autonomy_level`, read from `main`, admits the session's `risk_class`, read from
      `main`. `code-only` admits {code-only}. `code-and-tests-pre-deployment` admits
      {code-only, data-migration, secrets}. `unset` and anything else admit nothing. `infra`,
      `billing`, `public-surface` and `delete` are never admitted.
   5. CI's gate on the head is green. No verdict refuses: unjudged is not green.
   6. The reader's commit status on the head is green.
   7. If the head is behind `main`, the answer is `update`: the branch is brought up to date
      and judged again from condition 1. Red is refused before staleness is considered, so
      updating is never a second chance for a red PR.
3. **The merge pins the head commit** and is a merge commit, so the agent's red-to-green
   commits stay on `main` as the evidence that test-first was performed rather than claimed.
   Admin and auto merges are refused by the workflow's shape check.
4. **A refusal is a designed stop, and the run is green.** The PR gets the escalation label,
   a comment with the reason, and an issue. The plan halts because nothing merged, and a
   human merge resumes it through the unchanged trigger.
5. **The reader reads every session PR before it can land.** The `reader` agent, distributed
   in the plugin, gives two verdicts: **Spec** (each cited clause is realised and asserted by
   a test that fails without it) and **Standards** (the repository's laws as they stand on
   `main`). `reader.yml` runs it at a **pinned plugin tag**, and every script it runs comes
   from `main`, so a PR cannot change its own judge. A verdict counts as green only when it
   is a well-formed pass on both axes with no findings. The reader's failing fixture, a diff
   that omits a cited clause, must be reported by id before any reader version is tagged.
6. **The driver refuses `autonomy_level: unset`.** A driver that can merge does not start a
   session under a plan with no autonomy ruling.
7. **One session in flight per repository.** Two service chains are two repositories, two
   plans and two independent ceilings.

## Consequences

- **A person reads only the stops**: out-of-class sessions, reader findings, red or unjudged
  CI, conflicts and plan tampering. For everything else the model and the reader are the only
  controls on what the gate cannot see, which is why the reader is required and pinned.
- **Cost.** Each session PR adds a reader run, and another whenever the branch is updated.
  Reader spend goes into the ledger and counts against both ceilings without counting as an
  attempt.
- **The merge credential is a personal token until a forge app replaces it**, so a merged PR
  reads as the owner's.
- **If branch protection becomes available**, required checks and a merge queue can take over
  conditions 5 to 7 natively. That is a revisit, not a reason to wait.

## Rejected alternatives

- **Merge inside the chain.** One workflow would decide both what runs next and what lands,
  and the failure where it believes its own verdict would have no second check.
- **Serialise merges without re-gating.** Two green sessions can be red once combined.
- **Keep a generic review bot as the reviewer.** It posts comments, not a verdict a script can
  read, so "must not race the reviewer" would reduce to "waited for a bot to finish".
- **Read the reader's definition from the plugin's default branch.** An unreleased edit would
  change the merge gate with nothing having evaluated it.

## Revisit triggers

1. **The ratchet.** A run of consecutive passes in one class, counted by the improvement
   session, is the input to widening `autonomy_level`, and widening is still a ruling.
2. **Branch protection becomes available.** Move conditions 5 to 7 to native checks.
3. **A forge app replaces the personal token.** The merge credential changes, and provenance
   is fixed.
