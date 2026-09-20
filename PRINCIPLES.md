# The Xal Engineering Process — principles

These are decision rules, not slogans. Each one tells you what to do differently, and each
one was written down after the alternative was tried. The spec under [`spec/`](spec/) is
where they become obligations; this file is where they are stated once, in order.

## 1. The process is a repo

If a rule about how the work runs exists only in a chat thread, a memory or a SaaS UI, that
is a defect. Fix it by opening a PR. Never "just do it manually this once" without also
filing the lesson that says you had to. A convention that is written down is reviewable,
diffable and checkable; one that is remembered is none of those.

## 2. Language is an implementation detail behind a standard contract

The process owns the **spec** — what a conforming repo must do — stated so that no rule
depends on one language's tooling. Each repo owns its language's **implementation** of that
spec. If a rule can only be expressed in one language's terms, it is not a process rule yet;
it belongs in that repo. This repo's own gate refuses a language-specific token in
normative prose outside a labelled citation.

## 3. Verify artifacts, never self-reports

A completion summary is a claim, not evidence. "Done" means an externally checkable artifact
exists: a gate green in CI, a URL that resolves, a file at a path, a PR that is open. Never
mark your own work as having passed a gate. A confident summary of work that was silently
blocked is the single most common failure mode of both people and agents under pressure,
and it is what this rule exists to catch.

## 4. One script is the Definition of Done

Every repo has one gate script. CI invokes that exact script, so green locally is green in
CI byte for byte. To change a gate, change the script; a workflow may only add an input. The
gates run cheapest-first so a failure names the smallest thing that could be wrong. The
script is the list of gates; prose tallies go stale and nothing fails when they do.

## 5. Every gate ships with committed failing fixtures

A gate that has never been seen to fail has not been tested. A rule matching nothing and a
rule finding nothing emit byte-identical green, and `return 0` passes as convincingly as
real logic. So: one fixture per rule proving it fails, asserting *which* rule fired, and a
clean fixture proving the chain can say yes. The harness runs as its own CI step, because a
gate cannot prove itself without recursing.

## 6. Inputs are declared data

A gate script cannot see its own callers, and the author's machine satisfies its inputs
ambiently while CI must supply each one explicitly. So every input is declared in a
manifest, a meta-gate that needs no inputs of its own derives what the script requires and
asserts every caller supplies it, and a credential declares its expiry as a date the gate
checks. Zero callers is a failure, never a pass.

## 7. Nothing enters without a caller

A script nothing invokes, a fixture no harness names, a field no session fills: each is
worse than absent, because every signal a reader checks says the work is done. Before adding
anything, the question is not "is this good?" but "what calls it, today?" If nothing does, it
is not ready to land. The test for a rule that has never fired is not "has it been used?"
but "could it be, by the people and mechanisms that actually exist?"

## 8. Humans gate irreversibility; everything reversible is the agent's

The line is blast radius, not difficulty. Hard-but-reversible — research, drafting,
refactoring, seeding a repo, opening a PR — proceeds without asking. Trivial-but-irreversible
— publishing, sending, spending, deleting, granting access, choosing a stack — stops and
waits for a person, however small. The seeder refuses to default a language for exactly this
reason.

## 9. Park at gates, never bypass them

Work that stalls is parked in a state that names *who* it waits on: a person, or the world.
They are different queues and get different responses. A decision that is a person's goes to
them; a wait on the world is "blocked". Both are healthy states. Forcing a gate green to get
past it is neither.

## 10. One concern per session, and every session opens and closes with a ritual

A session takes one coherent slice. It begins by reading the latest handoff — not the
codebase — and restating the repo's standing laws; it ends only when the gates are green,
temporary rigs are gone or logged, docs are current, open lessons are triaged, a handoff is
written, comprehension checks are actually posed, and the PR is open. State survives
between sessions in files, never in memory.

## 11. Lessons are captured, reviewed and promoted

The moment something bites, it goes in the ledger as `open`. Every wrap walks the open
entries and gives each a permanent home: a script for a mechanical task, a command for a
recurring procedure, a guardrail for an always-true rule, an ADR for a decision with
tradeoffs. Search the ledger by root cause before adding an entry; the same cause is the
same lesson. A workaround never outlives its session without a tracked removal task.

## 12. Decisions are recorded, and a deviation is a new decision

Anything that shapes the architecture, is costly to reverse, or chooses between real
alternatives is an ADR: Context → Decision → Consequences, with the rejected options on
record. Superseded ADRs are marked, not deleted. Ask before deviating from an accepted one;
the deviation is its own ADR, not a quiet edit. Where a decision binds every repo, it is
recorded once, in the process repo, and cited from the others.

## 13. Understanding is a deliverable

A repo maintains a curriculum of concept notes that teach it end-to-end — the problem, the
mechanism from first principles, the tradeoff space, what this repo chose and why — each
citing real code and the relevant ADR. The index is a reading order. A note that could have
been written without the repo open is a failure.

## 14. Spec and implementation are kept apart, and drift is a red gate

The spec lives in one place and is vendored read-only into every repo, pinned to a version.
A local edit cannot be reconciled; it only holds the gate red. A change to the spec bumps
the version, and every consumer's drift gate stays red until it re-syncs and reviews the
diff. Seeded files are the opposite: a starting point a repo owns, adapts and never syncs.
