# Architecture Decision Records — the discipline

Every repo under this process (and the process repo itself) records its significant decisions as
**Architecture Decision Records (ADRs)**. This document defines the discipline; the
shape of a single record is [`adr-template.md`](adr-template.md).

## What an ADR is

A short, durable record of **one significant decision**, structured as
**Context → Decision → Consequences**. ADRs are the most valuable artifact during
future incident post-mortems and onboarding: they explain *why* the system is the way
it is, not just *what* it is.

Record a decision as an ADR when it:
- constrains or shapes the architecture (a boundary, a data store, a protocol, a
  cross-cutting pattern),
- is **costly to reverse** or will be repeatedly questioned later,
- chooses between real alternatives where the rejected options deserve to be on record.

Do **not** spend an ADR on a routine, easily-reversible implementation choice — that
belongs in code, a commit message, or a lesson.

## Numbering & lifecycle

- ADRs live in the repo under `docs/adr/` (consuming repos) or `adr/` (the process repo),
  one file per decision: `NNNN-kebab-title.md`, zero-padded from `0001`.
- **New decisions get the next number.** Numbers are never reused.
- A decision carries a **Status**: `Proposed` → `Accepted`, or `Rejected`. A later
  decision can **supersede** an earlier one.
- **Superseded ADRs are marked, not deleted** — strike the status to
  `Superseded by ADR-NNNN` and leave the record in place. The history is the value.
- A decision that is *fulfilled* (not reversed) gets a dated **status addendum**, not a
  new number — the original ADR still holds, it has simply been carried out.
- An `adr/README.md` index table (`# · Decision · Status`) lists every ADR in order so
  the log is scannable.

## Reusable rubrics

Some ADRs deliberately capture a **reusable selection rubric**, not just a one-off
choice — e.g. a language/runtime ADR whose *criteria* every future repo's stack ADR should
follow. Mark these clearly; they are how a decision made once propagates as guidance, not
as a copied conclusion.

## Process-level vs repo-level ADRs

- **Repo-level** ADRs (the bounded context, the token strategy, the data store, the stack,
  each variation flag) live in that repo and bind only it.
- **Process-level** decisions — ones that bind *every* repo (repo-per-service, shared-asset
  distribution, the conventions contract itself, how a repo is seeded) — are recorded in
  the **process repo's** `adr/`. A repo that needs to reference one cites it; it does not
  copy it.

When a decision discovered while building one repo turns out to bind every repo, that is
the signal to record (or move) it as a process ADR.

## Process

1. Copy [`adr-template.md`](adr-template.md) to `docs/adr/NNNN-title.md` (next number).
2. Fill **Context** (the forces), **Decision** (what + the rejected alternatives), and
   **Consequences** (positive, negative, and what is deferred).
3. Set Status (`Proposed` until accepted). Add the row to the `adr/README.md` index.
4. **Ask before deviating** from any `Accepted` ADR — a deviation is a new decision,
   recorded as its own ADR (possibly superseding the old one), not a quiet edit.
