---
title: Autonomy and risk classes
description: What may merge with no person present, and how that is granted.
---

An agent in the factory builds plan sessions. Whether its work merges without you is never
assumed: it is granted, by **risk class**, in a level you choose.

## The levels

| `pipeline.auto_merge` | The plan's `autonomy_level` | Merges unattended |
|---|---|---|
| `off` (default) | `code-only`, with `merge.yml` disabled | nothing |
| `code-only` | `code-only` | `code-only` sessions |
| `code-and-tests-pre-deployment` | the same | `code-only`, `data-migration`, `secrets` |

`infra`, `billing`, `public-surface` and `delete` are **never** admitted by any level.
Widening into them is a new decision, not a setting.

Each session in a plan carries its `risk_class`, written by the planner and approved by you
with the plan. The level is read from the plan on `main`, so a session cannot raise its own.

## What a merge has to pass

One script says yes, and the first failure stops it with a named reason:

1. The session changed only its own `status` and `evidence` in the plan.
2. No gate or pipeline path changed unless the plan lists it.
3. The driver's gate passed the session.
4. The level admits the session's risk class.
5. CI is green on the head commit. No verdict at all is not green.
6. The reader found nothing on Spec or Standards.
7. The head is current with `main`, or it is updated and judged again.

A stop is a designed outcome: the pull request gets your escalation label, a comment with the
reason and an issue, and the plan waits for you. The full decision is
[ADR-0008](/adr/0008-auto-merge-and-the-reader/).

## Widening it

Read a few driven sessions yourself first. A run of clean passes in a class is the evidence
for widening, and widening is still your ruling:

```bash
xal-factory config set pipeline.auto_merge code-only
xal-factory enable chain
```

Plans emitted afterwards carry the new level. An approved plan keeps its own until you
approve an amendment.

## Switching things off

```bash
xal-factory disable chain     # every session is dispatched by a person
xal-factory disable driver    # sessions are built by hand
```

Disabled workflows stay committed, so their fixtures keep proving them, and turning them on
again is one command.
