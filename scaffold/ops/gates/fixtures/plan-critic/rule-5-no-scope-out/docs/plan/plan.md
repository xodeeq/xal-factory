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
sessions_total: 3
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

## Session S1: foundation

- risk_class: code-only
- status:
- evidence:
- depends_on: []
- scope_in: the module manifest and one package with one exported function and its test
- scope_out: anything requiring a database, a secret, a network call or a deploy
- artifacts:
  - go.mod
  - internal/demo/demo.go
  - internal/demo/demo_test.go
- gate:
  - command: ./scripts/check.sh
  - must_not: no new gate input undeclared in .xal/gate-inputs; no coverage floor lowered; no file changed outside internal/demo/ and go.mod
- retry_cap: 2
- on_exhaustion: escalate
- human_only_actions_before: []
- prompt: |
    Create the module and one package, test first. The gate is ./scripts/check.sh and its
    exit code decides pass. Commit artifacts as proof; self-report is not evidence.

## Session S2: the feature that needs the foundation

- risk_class: code-only
- status:
- evidence:
- depends_on: [S1]
- scope_in: a second exported function in the same package, with its property test
- artifacts:
  - internal/demo/feature.go
  - internal/demo/feature_test.go
- gate:
  - command: ./scripts/check.sh && ./gates/check.test.sh
  - must_not: no test deleted or skipped; no change to S1's artifacts beyond additive ones
- retry_cap: 2
- on_exhaustion: escalate
- human_only_actions_before: []
- prompt: |
    Add the feature, test first, on top of S1. The gate is ./scripts/check.sh and
    ./gates/check.test.sh. Commit artifacts as proof; self-report is not evidence.

## Session S3: wrap

- risk_class: code-only
- status:
- evidence:
- depends_on: [S1, S2]
- scope_in: the README and the coverage floors raised to the measured figures
- scope_out: any production code change; any credential; any deploy
- artifacts:
  - README.md
  - coverage-floors
- gate:
  - command: ./scripts/check.sh && ./gates/check.test.sh
  - must_not: no coverage floor set above its measured value; no production code edited in a documentation session
- retry_cap: 1
- on_exhaustion: escalate
- human_only_actions_before: []
- prompt: |
    Raise each floor to the measured percentage of the green build and write the README.
    The gate is ./scripts/check.sh and ./gates/check.test.sh. Commit artifacts as proof;
    self-report is not evidence.
