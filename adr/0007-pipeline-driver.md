# ADR-0007: The pipeline driver and chain: one session, headless, in the service repo

- **Status:** Proposed
- **Date:** 2026-10-05 (originally decided 2026-09-17, revised for the chain 2026-09-22 and promoted to the scaffold 2026-09-27, re-recorded here on the second lift)
- **Deciders:** Process maintainer

## Context

An approved plan ([ADR-0005](0005-plan-format-and-critic.md)) is a list of sessions an
agent can build one at a time. Something has to run a session headless, judge it by the
repo's own gate rather than by the agent's account, write the result back where every later
decision reads it, and decide whether the plan continues. That something must not be able to
mark its own failure as passed, start itself without bound, or spend without a ceiling.

## Decision

1. **The driver is a CI workflow in the service repo** (`driver.yml`) plus repo-local
   `scripts/driver/`. The plan, the gate, the branch and the PR are all in the service repo,
   so the driver needs no credential into anything else to do its core job.
2. **Small scripts, each with one job and its own fixtures**, so no part of the driver is
   testable only by running the whole thing: read the plan (`plan-read`), decide whether a
   session may run (`preflight`), compose the brief verbatim from the approved plan
   (`session-prompt`), write `status` and `evidence` back (`plan-write`), fetch the spec by
   digest (`fetch-spec`), do the spend arithmetic (`spend`), pick the next session
   (`select-next`), and check the workflows' own shape (`chain-check`, `merge-check`,
   `step-order`, `workflow-context`, `branch-check`).
3. **Dispatch-bounded.** The driver starts only by dispatch, for one session id. Every bound
   is stated with what it does not stop: a job timeout stops a hung run but not spend already
   incurred; a turn cap stops a loop but not one expensive turn; a concurrency group stops two
   runs racing one branch; the job's permissions stop every capability except contents and
   PRs, including merging.
4. **The workflow runs the gate after the agent, and its exit code is the status.** An
   agent's summary is a claim. The gate step runs the repo's gate script and fixture harness
   with `CI=true` and every declared input supplied.
5. **Status and evidence are written on the session branch, never on `main`.** A driver able
   to write `main`'s plan is a driver able to mark its own failure passed on the artifact every
   later decision is taken from. On the branch, the state change lands in the PR diff beside
   the work that earned it, in its own commit by a named driver identity.
6. **Refusal is fail-closed, named and distinguishable from a crash.** `preflight` exits 3
   with `REFUSED: <reason>`. It refuses when the plan is not approved, when the approver or
   date is empty, when `autonomy_level` is out of vocabulary or unset, when the session does
   not exist, when `human_only_actions_before` is non-empty, when a dependency has not
   passed, and when the session already carries a terminal status. The workflow adds two
   more only it can see: the ref is not the default branch, and the session branch cannot be
   created.
7. **The agent holds no credential.** The spec is fetched by digest in a step before the
   agent runs, and the push credential is restored only after it ends. The agent's tool
   allowlist cannot push, open PRs, dispatch workflows, call the forge's API or browse.
8. **A red gate is written, retried within the cap, then escalated.** A red gate writes
   `status: failed` with evidence and leaves the PR open. The chain counts attempts from the
   spend ledger (one record per run, so the count cannot disagree with a second field),
   re-dispatches while the count is within `retry_cap`, and on exhaustion writes
   `status: escalated`, opens an escalation PR, files an issue and halts.
9. **The chain is a separate workflow** (`chain.yml`). The driver runs one session and
   stops. A driver that chained itself would be both the worker and the judge of whether to
   continue, and the failure where it keeps dispatching because it believes its own verdict
   would have no second opinion.
10. **Selection is the lowest-numbered eligible session.** Eligible means every dependency
    has passed and the session's own status invites a run. Chosen over critical-path-first,
    which needs a graph computation and its own tie-break and cannot be pinned by one fixture.
11. **The chain refuses to build on a red or unjudged `main`.** A run still in progress is
    not green.
12. **The spend ledger lives in the ops repo, and every run appends to it, failed runs
    included.** A failed run still spent the money, and a ledger that recorded only
    successes would leave the ceiling defending a number computed from the runs that least
    needed bounding. Telemetry appends to `main` without review because it is a record of
    what happened, and the only way it can be wrong is by being incomplete, which a PR
    cannot catch. Code never does.
13. **The ceilings promise `ceiling + one session`, never `ceiling`.** Both are checked
    before the agent step, in the driver as well as the chain, so a hand dispatch is bounded
    too. A check before a session cannot know what that session will cost. The ceiling makes
    a runaway terminate rather than compound. It is not a promise about any one session.
14. **The driver lives in the scaffold's common tree**, with its fixtures, so a seeded repo
    arrives with it and the scaffold's seed-set check fails when a piece is missing.
    Language-specific setup sits behind one toolchain action the overlay provides, shared by
    the driver and CI so the two judge a commit with the same tools.

## Consequences

- **The first live runs bought driver defects, not features.** One made `retry_cap`
  unreachable on every session, because preflight refused any non-empty status. Another
  showed CI and the driver disagreeing on the same commit because they resolved different
  toolchains, which is why decision 14 shares one toolchain step.
- **A PR opened with the workflow's own token does not trigger CI.** The driver therefore
  opens the PR with a declared credential, recorded in `.xal/gate-inputs` with its expiry.
- **The push credential is broader than its use.** It appends to one ledger file and nothing
  structurally limits it to that. A forge app with narrower scope is the fix, and until then
  it is an accepted risk with an expiry date.
- **Two parsers read the plan format**, the critic and `plan-read`, and nothing diffs them.

## Rejected alternatives

- **The driver in the ops repo, reaching into service repos.** It would need a write
  credential into every service, the thing the per-repo driver avoids.
- **Retry on the merge trigger.** A failed session leaves a PR nobody merges, so the merge
  trigger never fires for it and the plan stalls silently.
