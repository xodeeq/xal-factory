# The lifecycle: idea to monitoring

This is the whole path a piece of work takes through a factory, from a one-line idea to a
service running in production and watched. Each stage names its **artifact** (what exists
when the stage is done), its **gate** (what must be green, decided by a script or a named
person, never by an agent's report) and **who decides**. The session type that runs each
stage is defined in [`session-types.md`](session-types.md).

The **owner** is the person at the gates. The **ops repo** holds specs, status, the cost
ledger and the idea inbox. A **service repo** is one deployable unit, seeded from the
scaffold with its gate and its pipeline already in place.

## The stages

| # | Stage | Artifact | Gate | Who decides |
| ---: | :--- | :--- | :--- | :--- |
| 0 | Idea | One line in the inbox issue | Every line is accounted for at the weekly triage | The owner, at triage |
| 1 | Research | A brief with a source ledger; a decision map; ADR drafts | Every claim has a source; every ruling records who decided and when | The owner rules, the session never rules for them |
| 2 | Spec and intake | `specs/admitted/<service>/<version>.md`, copied verbatim, plus a ledger row with its digest | The spec-intake gate (ten rules, below) | The owner approves the spec; the gate admits it |
| 3 | Stack and seeding | A new service repo whose first ADR records its stack | The seeded repo's own gate is green on its first commit | The owner rules the stack; the seeder never defaults one |
| 4 | Plan | `docs/plan/plan.md` as a PR | The mechanical plan critic, then the judging plan critic | The owner merges the plan, which is the approval |
| 5 | Implementation | Machine-authored commits on `plan/<plan>/s<n>`, a PR, `status` and `evidence` in the plan | The repo's gate, run by the workflow; CI on the head commit | Nobody, inside the plan's ceilings |
| 6 | Review | Two verdicts, Spec and Standards, as a commit status | The reader must catch its committed fixture before any reader version is used | The reader; the owner reads only findings |
| 7 | Merge | A merge commit on `main` | The merge decision (seven conditions, below) | The script, inside the plan's autonomy level; the owner for everything outside it |
| 8 | Continuation | The next session dispatched, a retry, or an escalation | `main` is green; the ceilings allow it; the retry cap is not spent | The chain; the owner on escalation |
| 9 | Deploy | A release running the merged commit | The gate again, migrations as a release step, then the smoke gate against the live URL | The pipeline once deploy-on-merge is switched on, which is a human-only act |
| 10 | Monitoring | Health, metrics, structured logs, traces; alert runbooks; the nudge; the cost ledger | Readiness is honest; credential expiry warns before it fails; ceilings stop spend | The owner, at the weekly review |
| 11 | Learning | Lessons captured, reviewed and promoted into gates, rules or prompts | Every promotion cites its evidence | The owner merges the improvement PR |

## Stage notes

**0. Idea.** Capture costs one line, from any session or a phone. Nothing is decided at
capture. The weekly triage turns each line into a board item, a ticket, a lesson or a
recorded discard, and the gate is that none is left unaccounted for.

**2. Spec and intake.** A spec has four frontmatter keys (`service`, `spec_version`,
`date`, `status`) and ten numbered sections in order: purpose and boundary; decomposition
and rationale; functional requirements; data ownership and schema sketch; synchronous
interfaces; events; non-functional requirements; human-only actions; open decisions;
source ledger. Every variation flag sits in a table with a default, or `required` with a
reason ([`service-conventions.md`](service-conventions.md) §9). Admission copies the file
byte for byte and records its digest, so an edit after admission is a red build. A source
that does not fit the format is flagged in the admission PR and goes in as it is, or not
at all. It is never quietly reshaped.

**3. Stack and seeding.** Choosing a stack is a decision, recorded as the service's first
ADR, never a default buried in a script. A factory may name a fallback language that the
seeder pre-selects, but the ADR is still required. The seeder prints the human-only steps
(installing the agent's app on the repo, setting secrets with their expiry dates, choosing
the runner) rather than performing them.

**4. Plan.** The plan is the contract the driver executes. Its frontmatter carries the
admitted spec's digest, the approval (who and when), the **autonomy level** and two spend
ceilings (per plan, per session). Each session carries its `risk_class`, `depends_on`,
what is in and out of scope, its artifacts as paths, a gate command with what it must not
do, a `retry_cap`, `on_exhaustion: escalate`, any `human_only_actions_before`, and the
prompt. `status` and `evidence` are left empty for the driver. The plan critic has two
halves: a script that decides what a machine can (every field present, dependencies
acyclic, gate commands real), and an agent that judges what it cannot.

**5. Implementation.** The driver refuses before it spends. It will not start a session
whose plan is unapproved, whose autonomy level is unset, whose dependencies have not
passed, whose human-only actions are outstanding, or which is already running or done. It
fetches the spec by digest so the agent never holds the credential, runs the agent with a
tool allowlist that cannot push, open PRs or call the forge's API, then commits, runs the
gate itself, opens the PR and writes `status` and `evidence`. A session that changes
nothing fails. Every run appends its cost to the ledger.

**6. Review.** The reader agent reads every session PR before it can land and gives two
verdicts: **Spec** (each cited clause is realised and asserted by a test that fails without
it) and **Standards** (the repository's laws as they stand on `main`). It runs at a pinned
version, and every script its workflow runs comes from `main`, so a PR cannot change the
judge that judges it.

**7. Merge.** One script says yes, and the first failure is a named refusal:

1. The head's plan differs from `main`'s only in this session's `status` and `evidence`.
2. No gate or pipeline path changes unless the plan lists it among the session's artifacts.
3. The session's status on the head is `passed`.
4. The autonomy level, read from `main`, admits the session's risk class, read from `main`.
5. CI's gate on the head is green. No verdict at all refuses, because unjudged is not green.
6. The reader's status on the head is green.
7. If the head is behind `main`, it is updated and judged again from condition 1.

A refusal is a designed stop: the PR gets the escalation label, a comment with the reason
and an issue for the owner. The merge pins the head commit, so nothing can land between the
verdict and the merge.

**8. Continuation.** After a merge, the chain waits for `main` to be green, picks the
lowest-numbered eligible session, checks the ceilings and dispatches it. After a failure it
retries up to the session's `retry_cap`, then marks the session escalated, opens an
escalation PR and files an issue. A red `main` halts everything.

**9. Deploy.** The deployment contract is in
[`deployment-conventions.md`](deployment-conventions.md): the runtime is reproducible from
files, migrations run as a release step, secrets fail fast at boot, health is wired to the
platform, and a smoke gate runs against the live URL after every deploy. A new repo's
deploy workflow is dispatch-only and refuses until a target is provisioned. Turning on
deploy from `main` is the owner's act.

**10. Monitoring.** A service exposes liveness, honest readiness, metrics, structured logs
and trace propagation ([`service-conventions.md`](service-conventions.md) §2 to §5). Alert
rules are written down beside the service before they are wired. The factory watches
itself as well: a weekday nudge renders the status file, gate 0 warns 30 days before a
declared credential expires and fails once it has, and the cost ledger is checked against
both ceilings before every session.

## Autonomy is granted, never assumed

The **autonomy level** in a plan says which risk classes may merge without a person:

| Autonomy level | Merges unattended |
| :--- | :--- |
| `unset` | Nothing. The driver also refuses to start. |
| `code-only` | `code-only` sessions |
| `code-and-tests-pre-deployment` | `code-only`, `data-migration`, `secrets` |

`infra`, `billing`, `public-surface` and `delete` are never admitted by any level. Widening
into them is a new ruling, not a configuration change. A run of passes in one class, counted
by the improvement session, is the evidence for widening a level, and the widening is still
the owner's ruling.
