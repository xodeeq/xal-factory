# ADR-0005: The service plan format, and a plan critic split by decidability

- **Status:** Proposed
- **Date:** 2026-10-05 (originally decided 2026-09-16 and amended the same day, re-recorded here on the second lift)
- **Deciders:** Process maintainer

## Context

A factory builds a service by executing a plan: a file in the service repo that breaks an
admitted spec into sessions an agent can run one at a time. The plan is the contract the
driver reads at every session boundary. Whatever the plan fails to say, the driver either
guesses or cannot do.

The first plan format was drafted before the spec-intake layer existed, and it assumed a
world that intake did not build. It cited the spec by a path in the service repo, which by
then held only a pointer. It required a status value on a key that did not exist. And it
read a session budget from a spec field that no admitted spec could carry. A check that
asserts a value against an absent field reads as a check and is none. That was the failure
this decision exists to prevent: a format whose rules look enforced and match nothing.

## Decision

1. **The plan critic is two things, split by decidability.** The mechanical half is a
   script in the ops repo's gate (`scripts/plan-critic-check.sh`): every rule a machine can
   decide from the plan's text alone, one committed failing fixture per rule asserting which
   rule fired, a clean fixture, and fixtures for the cannot-run cases. The judgement half is
   an agent (`plan-critic`) with the `planner` agent as its counterpart. The split is forced:
   a gate runs from a plain CI step, and an agent is not resolvable from one without making
   the agent's distribution a new gate input in every repo.
2. **A plan cites its spec by identity and digest, never by a path.** Four keys:
   `spec_service`, `spec_version`, `spec_sha256`, `spec_admitted_at`. The digest is the one
   the intake ledger records, so the critic can reconcile it.
3. **`spec_max_sessions` is required, and may be the literal `none-declared`.** A cap no
   spec can declare is not invented.
4. **A field whose value is a pending ruling carries `unset` and names its deciding
   session.** Never a number. `autonomy_level` and the spend ceilings are the live cases.
   An omitted key reads as "not applicable"; `unset` is something a machine can refuse on.
   A plan carrying a fabricated ceiling is worse than one carrying none, because the
   fabricated one will be enforced.
5. **The format's home is the gate and its clean fixture.** There is no separate template
   to drift from the rule that checks it.
6. **The plan critic and the ADR critic stay separate agents.** They judge different
   artifacts against different failure lists.
7. **A plan whose `status` is `approved` names its approver and its date** (rule 11). An
   approval is a claim about a person and a day, and a claim with neither is a word. The
   execution half, refusing to run a plan that is not approved, is the driver's
   ([ADR-0007](0007-pipeline-driver.md)).

The mechanical rules, each with its fixture: the spec is cited by a digest the ledger can
recompute; every session has a non-empty gate command and a non-empty `must_not`; artifacts
are paths; both scope boundaries are present; `retry_cap` is an integer and `on_exhaustion`
is `escalate`; `sessions_total` matches the session blocks; every `depends_on` names a
declared session and the graph has no cycle; `risk_class` is in vocabulary, `status` and
`evidence` are present and empty for the driver, the prompt is non-empty and
`human_only_actions_before` is present; an approved plan names approver and date.

## Consequences

- **The cycle rule is fed only edges whose endpoints are both declared sessions.** Without
  that guard a single mistyped dependency trips two rules at once, and a fixture that fires
  two rules proves neither.
- **Two rules were wrong when first written and their fixtures caught both.** The artifact
  rule rejected a real root-level file name as "not a path", and the frontmatter reader did
  not strip inline comments, so one rule failed a valid value while another silently skipped.
  Both were found by running the gate, not by reading it.
- **The approval was first lost between a merge and the file.** The owner merged the first
  plan, and nothing flipped `status` to `approved`, because the sentence that said "merge
  flips the status" named an action with no actor. The lesson is general: for a cited
  artifact ask whether the path resolves, and for a cited action ask who or what performs
  the verb.
- **What rule 11 does not check.** It checks the shape of an approval, not that the named
  approver may approve or that the date is the merge's. Both would need an input the gate
  must not have.
