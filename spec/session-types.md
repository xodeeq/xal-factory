# Session types

Every unit of work in a factory is a **session**, and every session has a **type**. A type
is a contract: it states the session's **trigger**, its **inputs**, its **outputs**, its
**gate**, its **tool scope**, **who is in the loop** and its **home** (where its artifacts
land). The prompt and the model behind a type may be rewritten freely. The contract table is
the stable surface, the same rule that puts a service behind a stable contract with a
swappable implementation.

A session names its type in its first line. A task that fits no type is a **system**
session and says so. Typed sessions are what make two sessions at once safe rather than
merely allowed: a research session has no write into a service repo, and an implementation
session is a driver dispatch, not an interactive edit, so the two never share a working
tree.

The **owner** is the person at the gates: the one who rules on decisions, merges what the
pipeline does not, and reads escalations. A factory names its owner's escalation label in
its configuration. The **ops repo** holds the factory's specs, status, cost ledger and idea
inbox. The **service repo** is one deployable unit.

## The types

| Type | Trigger | Inputs | Outputs | Gate | In the loop | Home |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **system** | The owner brings a change to how the factory works: a review, a rule, a redesign | Reviews, lessons, retros, the idea inbox, the status file | PRs to the ops repo and the process repo (agents, gates, ADR drafts), decisions recorded, status updated | The ops repo's gate green; every decision has a numbered home; nothing exists only in the conversation | The owner, heavily and by design | Ops repo |
| **research** | A problem, a service candidate, a stack question, an ADR needing evidence | Sources, the sibling repos read live | Research briefs, a decision map and tickets, a spec into intake, ADR drafts | A source ledger is present; spec intake is green; every ruling carries who decided and when; no write to a service repo | The owner for rulings, otherwise unattended | Ops repo (`docs/research/`, `specs/`, issues) |
| **planning** | An admitted spec and a seeded repo with no plan | The admitted spec by digest, the repo's laws | `docs/plan/plan.md` as a PR | The mechanical plan critic and the judging plan critic are both clean | The owner merges | Service repo |
| **implementation** | An approved plan with an eligible session | The plan, the spec fetched by digest, the repo | Machine-authored commits, a PR, `status` and `evidence` in the plan | The gate run by the workflow, never reported by the agent; CI on the head commit | Nobody until escalation, and the owner at the auto-merge exclusions | Service repo |
| **review** | A driven session's PR is open | The diff, the admitted spec, the repo's standards | Two verdicts (Standards, Spec), never a merge; findings as lessons | A committed fixture the reader must catch | The owner only on findings | The reader agent, posting a commit status |
| **operations** | The weekday nudge; the weekly review | The status file, the board, gate 0's expiry warnings, the cost ledger | The rendered nudge; decisions drained; the idea inbox triaged; credential check-ins | The status-render gate; board hygiene clean | The owner, weekly | Ops repo |
| **idea-intake** | Any moment an idea occurs | One line | An entry in the inbox, later a board item, a ticket, a lesson or a recorded discard | Every line accounted for | The owner at the weekly triage | Ops repo inbox issue |
| **publication** | A weekly schedule | Lessons, handoffs, merged PRs, ADRs | An article as one PR, with a judge report | The judge's threshold met; the owner's approval; the live URL resolves | The owner, for every public act | Defined, not built |
| **improvement** | A weekly schedule | Every repo's lessons, gate failures, the cost ledger, stuck items, review findings | One PR: prompt diffs, gate tightenings, lesson promotions | Every change cites its evidence | The owner reviews the PR | Defined, not built |
| **currency** | A monthly schedule per technology | Pinned versions read from the repos; primary release notes | A currency file updated by PR; a board item when a release matters | Every claim links a primary source; no code change by the scout | The weekly review reads the item | Defined, not built |

A type marked **defined, not built** has a contract and no implementation. It is listed so
that the first person to build it builds to the contract rather than inventing one.

## How a session knows its type

- **Explicitly.** An agent definition per type, started with the harness's agent flag, runs
  the whole session under that type's tool allowlist. The fence is in the allowlist, not in
  prose. This is the preferred form for research and system sessions.
- **By a router.** A workspace that holds several repos side by side carries a short
  router file at its root: a table from task shape to type, and the rule that a session
  names its type first. A router that holds rules is itself versioned, in a thin workspace
  repository that ignores the sibling repos rather than nesting them.
- **By dispatch.** An implementation session is never typed by a person at a prompt. It is
  started by the driver for one plan session, and its type is implied by how it began.

## Rules that hold across types

- **One active build track, at most one research lane.** Only the build track ships code,
  infrastructure or repo changes. Research reads, evaluates and writes up. Research pauses
  if the build track stalls.
- **Park at gates, never bypass them.** A decision that is the owner's goes to a decision
  queue. A wait on the outside world is recorded as blocked. Both are healthy states.
- **Verify artifacts, never self-reports.** A session that cannot show a path, a PR or a
  URL has not done the thing.
- Every session follows the begin and wrap ritual in
  [`session-ritual.md`](session-ritual.md), and the whole lifecycle these types serve is in
  [`lifecycle.md`](lifecycle.md).
