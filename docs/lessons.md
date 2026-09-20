# Lessons log — the process repo

A running ledger of pitfalls, workarounds, repeated explanations, and consequential
decisions — so none of them evaporate at the end of a session. This is the process repo's
**own** ledger (eating the dog food: `spec/session-ritual.md` requires one per repo, and
`scaffold/common/docs/lessons.md` seeds it for new repos). Repo-specific lessons belong in
that repo's ledger, not here.

**The loop: capture → review → promote.**

1. **Capture** (any time): the moment something bites, a workaround goes in, or you find
   yourself explaining the same thing twice, append a one-line entry here with status `open`.
2. **Review** (every session, via `/wrap-session`): walk the open entries and decide each
   one's permanent **home**.
3. **Promote**: move the lesson into the thing that makes it stick, then flip the entry to
   `promoted→<link>`. A lesson that stays `open` for many sessions is a signal it needs a
   decision, not that it should be forgotten.

**Homes** (where a lesson goes to live permanently):

| Home | Use when the lesson is… | Example |
|---|---|---|
| **script** | a mechanical, repeatable task | the sync round-trip → `sync/process-sync.sh` |
| **skill / command** | a recurring procedure or judgement | end-of-session ritual → `/wrap-session` |
| **guardrail** (CLAUDE.md) | an always-true rule | "no language-specific tokens in `spec/`" |
| **ADR** | an architectural decision with tradeoffs | the repo structure + sync model |

> **Never let a temporary workaround outlive the session that created it** without a tracked
> entry here to remove it.

## Format

One line per entry:

```
date | context | lesson | proposed home (script/skill/guardrail/ADR) | status (open / promoted→link)
```

## Entries

```
2026-09-20 | The first run of this repo's own fixture harness found a bug in gate 1 | Gate 1 documents a paragraph-form citation (`**Reference.**` on its own line) as running "to the next blank line", but its region logic only excused indented continuations and bullets — a wrapped prose line at column 0 ended the region, so a language-specific token on the second line of a citation was reported as a leak. The clean fixture (a two-line citation naming two tools) failed, which is exactly the failure a clean fixture exists to catch: the gate was stricter than its own rule and nothing else would have said so. The eight failing fixtures all passed on the same run. | script (the region logic in `scripts/check.sh` now matches the documented rule: paragraph form runs to the next blank line, bullet form to the end of the indented continuation) | promoted→ fixed in `scripts/check.sh` gate 1 before the first commit; `gates/fixtures/check/clean/` is the regression test
```
