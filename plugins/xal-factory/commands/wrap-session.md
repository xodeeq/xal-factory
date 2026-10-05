---
description: End-of-session ritual — gates, rig sweep, docs currency, lessons promotion, handoff, comprehension checks, an optional forward brief, the board, then push + PR.
argument-hint: "(no args)"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# /wrap-session

Close the session deliberately so the next one — human or agent — can pick it up cold. Run
the steps **in order**; if a step cannot complete, stop and say why. This is the only
sanctioned way to end a session.

> **The canonical procedure is `docs/process/session-ritual.md`** (the vendored process
> spec) → "Wrap a session", and the handoff format is defined there. This command is the
> launcher.

This is the **generic** ritual, shared by every repo that follows the process. It names no
gate command, no language and no test framework: those differ per repo and live in that
repo's own `CLAUDE.md`. If you find yourself wanting to hardcode a script path or a file
glob here, it belongs in the consuming repo, not in the shared copy.

## Steps (in order)

1. **Gates must be green.** Run this repo's gate command — `CLAUDE.md` names it. If it
   fails, **stop**: report the failing gate and do nothing else. Editing source to force it
   green is session work, not wrap-up. If the repo has no gate script yet, say so plainly
   and verify by hand whatever checkable facts it does have; "no gate script" must never
   quietly become "no verification".
2. **Temporary-rig sweep.** Grep for rigs that must not silently outlive the session:
   disabled CI steps, skipped or ignored tests, newly added not-implemented seams,
   `TODO`-for-later. The exact patterns are language-specific; take them from the repo's
   own conventions. Remove each leftover now, or log it `open` in `docs/lessons.md` with a
   tracked removal task. **Never leave an undocumented rig.**
3. **Docs currency check.** Confirm `CLAUDE.md` and `README.md` still match reality; update
   if drifted. A stale `CLAUDE.md` misleads every future session that loads it.
4. **Lessons promotion review.** For every `open` entry in `docs/lessons.md`, propose its
   home — script · skill/command · `CLAUDE.md` guardrail · ADR. Promote what you can; for an
   ADR or anything needing the user's call, recommend, draft the Decision section, and
   **ask** — never create or edit an ADR without approval. Capture any new lesson.
5. **Write the handoff** to `docs/sessions/NN.md` (next zero-padded number) in the format
   from the ritual spec — **before** the comprehension checks, and tell the user it is ready.
6. **Comprehension checks** — 3–5 questions tied to what was actually built or decided
   (favour "why", "what breaks if", "predict the next step"). **Pose them interactively**,
   one at a time, confirming or correcting each. Record in the handoff *exactly* what
   happened; "posed; not self-answered" is the honest result when the user declines. Never a
   fabricated score, and never a result line copied from a previous handoff.
7. **Leave a forward brief only if the next session genuinely needs one** — a judgment
   call, and "no brief" is the common, correct outcome.
8. **Suggest a concept note** if something substantial and durable was built and lacks one
   (`concept-note` skill). Offer; don't auto-generate.
9. **Sync the work board, if the project keeps one.** `CLAUDE.md` names the board. For each
   item this session touched, and any work with no item: set status to where the work
   actually is; attach the evidence link (**an item you cannot give an artifact is not
   done**); park what stalled in the state naming who it waits on. If you cannot reach the
   board, that is a **park, not a skip**: record what the item should say under a **BOARD
   NOT SYNCED** heading in the handoff and in the PR body. Never record a field you did not
   verify. A project with no board records the same facts in the handoff.
10. **Push + open/update the PR**, linking the handoff and summarising changes, gate status
   and open questions — only after steps 1–9 succeed. Name and link any board items you
   moved; board state never appears in the diff.

A session is "wrapped" only when: gates green · no undocumented rigs · docs current · open
lessons triaged · handoff written · comprehension checks actually posed after it (and
truthfully recorded) · a forward brief left or consciously skipped · the board synced or the
failure recorded · branch pushed and PR open.
