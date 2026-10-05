# spec/ — the canonical language-agnostic process

This is the **source of truth** for everything a conforming repo carries, independent of its
implementation language. A repo consumes these files by vendoring a read-only copy into its
own `docs/process/` via the sync mechanism
([`sync/SYNC.md`](https://github.com/xodeeq/xal-factory/blob/main/sync/SYNC.md));
it never edits a vendored copy. Edit the spec **here**.

> **The rule:** this repo owns the **SPEC** (these files); each consuming repo owns its
> language's **IMPLEMENTATION**. Nothing here is normatively language-specific.

| File | What it governs |
|---|---|
| [`process-guide.md`](process-guide.md) | The engineering lifecycle: the phases and the Definition of Done a service moves through, with tools per phase. Informative; the other files are normative. |
| [`service-conventions.md`](service-conventions.md) | The §1–9 operational + HTTP **contract** surface: API description, health, telemetry, logging, trace propagation, container interface, event envelope, purity, variation-behind-contract. |
| [`deployment-conventions.md`](deployment-conventions.md) | The **deployment** contract: runtime reproducible from files, migrations as a release step, secrets and fail-fast, health wiring, the smoke gate, CD from `main`. |
| [`gate-discipline.md`](gate-discipline.md) | What makes a gate script's verdict trustworthy: one script, the gate order, declared inputs, committed failing fixtures, exit codes, coverage ratchets, nothing without a caller. |
| [`adr-discipline.md`](adr-discipline.md) | How decisions are recorded (Context → Decision → Consequences), numbered, superseded; process-level vs repo-level ADRs. |
| [`adr-template.md`](adr-template.md) | The single-ADR template to copy. |
| [`concept-note-structure.md`](concept-note-structure.md) | The learning curriculum: the fixed concept-note form and the onboarding-path discipline. |
| [`session-ritual.md`](session-ritual.md) | The begin/wrap work-session ritual, the handoff format, and the ephemeral-briefs lifecycle. |

Changing any file here is a spec change: bump the repo
[`VERSION`](https://github.com/xodeeq/xal-factory/blob/main/VERSION) per the
policy in
[`CLAUDE.md`](https://github.com/xodeeq/xal-factory/blob/main/CLAUDE.md)
(patch = clarification, minor = additive obligation, major = breaking), so consumers see the
drift and re-sync deliberately.

See [`../VERSION`](../VERSION) for the pinned version.
