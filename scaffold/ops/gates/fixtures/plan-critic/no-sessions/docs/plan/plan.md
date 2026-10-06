---
type: service-plan
plan_id: xal-demo-20260916
service: xal-demo
spec_service: xal-demo
spec_version: 1.0.0
spec_sha256: 3a7bd3e2360a3d29eea436fcfb7e44c735d117c42d1c1835420b6b9942dd4f1b
spec_admitted_at: factory-ops:specs/admitted/xal-demo/1.0.0.md
spec_max_sessions: none-declared
status: proposed
approved_by:
approved_on:
autonomy_level: unset          # ruled by R1, due before S5 of the pipeline roadmap
spend_ceiling_usd: unset       # ruled by R2, due before S6 of the pipeline roadmap
sessions_total: 0
department: engineering
tags: [service-plan, fixture]
---

# xal-demo — build plan (FIXTURE)

This is the CLEAN fixture for `scripts/plan-critic-check.sh`. It is a real plan in shape and
a fake one in content: it names a service that does not exist, so nobody can mistake it for
work that is owed. It exists to prove the gate can say **yes** — a gate that flags every
plan is deleted within a week, and one that has only ever been seen to fail has not been
seen to discriminate.

Every rule fixture beside it is this file, broken in exactly one way. The suite asserts that,
by diffing.

## Plan summary

Three sessions in a chain: a foundation, a feature that needs it, and a wrap that needs both.
Enough shape to exercise ordering, the dependency graph and the driver's state fields; small
enough that a reader can hold all of it.

## Session list

The frontmatter is well formed and there is not a single `## Session S<N>:` block. The gate
must exit **2**, not 0: an empty plan is not a plan that says nothing is needed, it is a file
the gate did not understand. `docs/plan/README.md` in a seeded service repo says the same
thing in prose — "an empty plan.md is worse than none: it reads as a plan that says nothing
is needed" — and this fixture is that sentence made enforceable.
