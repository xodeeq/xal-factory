---
type: service-plan
plan_id: fixture-20260917
service: fixture
spec_service: fixture
spec_version: 1.0.0
spec_sha256: e0ca51a1819ff626ec069b2a9eaa829ef6c2a7611f3352b904406c263285ec8a
spec_admitted_at: factory-ops:specs/admitted/fixture/1.0.0.md
spec_max_sessions: none-declared
status: approved
approved_by: owner
approved_on: 2026-09-16
autonomy_level: code-and-tests-pre-deployment   # ruled by the owner 2026-09-16 (R1); not read until PIPELINE S7
spend_ceiling_usd: unset       # no value ruled — pipeline R2 decides it
sessions_total: 3
department: engineering
tags: [service-plan, fixture]
---

# The clean fixture — this IS the format

This is the driver's exemplar plan, and the only complete one committed to this repo. Every
other fixture beside it is this file broken in EXACTLY ONE way, so a suite failure names a
rule rather than a file.

Two things here are deliberate and must not be "tidied":

- **The frontmatter carries inline comments** on `autonomy_level` and `spend_ceiling_usd`,
  exactly as the real plan does. A reader that does not strip from the first ` #` compares
  the whole annotation, fails to match `code-and-tests-pre-deployment`, and refuses a plan
  that is fine — or worse, silently skips the check. plan-critic-check.sh hit that once.
- **S1's prompt contains a line beginning `- `**, indented. Prompt mode must not end there.
  A parser that leaves prompt mode on any `- ` reads prose as fields and misses the real
  ones that follow.

## Session S1: A session with no dependencies

- risk_class: code-only
- status: ungated
- evidence: the run that produced this
- depends_on: []
- scope_in: the smallest thing a session can build
- scope_out: everything else
- artifacts:
  - internal/fixture/a.go
  - coverage-floors
- gate:
  - command: ./scripts/check.sh && ./gates/check.test.sh
  - must_not: no coverage floor lowered; no secret value committed, only names
- retry_cap: 2
- on_exhaustion: escalate
- human_only_actions_before: []
- prompt: |
    Build the thing. Strict TDD: the failing test precedes the code.
    The list below is prose inside the prompt, NOT session fields:
    - this line begins with a dash and is indented
    - so does this one
    The gate is `./scripts/check.sh && ./gates/check.test.sh`.
    Commit artifacts as proof; self-report is not evidence.

## Session S2: A session that depends on S1

- risk_class: code-only
- status:
- evidence:
- depends_on: [S1]
- scope_in: the thing that needs S1 to exist first
- scope_out: everything else
- artifacts:
  - internal/fixture/b.go
- gate:
  - command: ./scripts/check.sh && ./gates/check.test.sh
  - must_not: no coverage floor lowered
- retry_cap: 2
- on_exhaustion: escalate
- human_only_actions_before: []
- prompt: |
    Build the second thing.
    Commit artifacts as proof; self-report is not evidence.

## Session S3: A session a person must unblock first

- risk_class: infra
- status:
- evidence:
- depends_on: []
- scope_in: the thing that cannot start until the owner has acted
- scope_out: everything else
- artifacts:
  - internal/fixture/c.go
- gate:
  - command: ./scripts/check.sh && ./gates/check.test.sh
  - must_not: no deploy
- retry_cap: 1
- on_exhaustion: escalate
- human_only_actions_before: [provision the database]
- prompt: |
    Build the third thing, once the human action above has happened.
    Commit artifacts as proof; self-report is not evidence.
