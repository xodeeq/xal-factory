---
description: Explain a topic, a component, or "what we just built" Socratically — teach it conversationally using the concept-note structure, then ask 2-3 predict/justify questions and correct my answers. Teaching only; never edits production code.
argument-hint: "[topic | component | (blank = what we just built this session)]"
allowed-tools: Bash, Read, Grep, Glob
---

# /explain $ARGUMENTS

Teach me **$ARGUMENTS** for active recall — a Socratic back-and-forth, not a
lecture. If `$ARGUMENTS` is empty, the subject is **"what we just built this
session."**

> **This command must NOT modify production code.** It reads and explains only. No
> edits to `src/`, no commits. (The one allowed *write* is optional and explicit:
> persisting a concept note in step 4, only if I say yes.)

## How to run it

### 1. Ground the explanation in real code
Identify the actual files/types/ADRs the subject lives in and read them, so the
explanation cites this repo, not generic knowledge. If the subject is a component,
open it. If it's a concept, find where the repo realizes it. If it's "what we just
built", look at the recent diff / session work.
```bash
git diff --stat main...HEAD    # what changed on this branch, when subject is "what we just built"
```

### 2. Explain conversationally (concept-note shape, spoken not written)
Walk the subject using the **concept-note structure** as a mental scaffold —
*problem it solves → how it works from first principles → the tradeoff space →
what THIS repo chose and why* — but as a flowing explanation, not a filled-in
template. Keep it tight. **Cite real files by their path in this repo** and the
relevant **ADR**, so the concept stays bridged to the implementation rather than
drifting into generic textbook content.

### 3. Turn it back on me (the point of the command)
Ask **2-3 questions** that make me **predict or justify the next step** — favor:
- "what would break if we did X instead?"
- "given this, what *should* the next change be, and why?"
- "why is it this way and not [plausible alternative]?"

Ask them **one at a time**. Wait for my answer. **Correct or confirm** each before
moving on — point out exactly what I got right, what I missed, and why. If I'm
hand-wavy, push once for precision. The goal is to surface gaps, not to award a
score.

### 4. Offer to make it durable (only if warranted)
If the subject is **substantial and durable** and lacks a note under
`docs/concepts/`, offer to persist one via the **concept-note** skill. Only create
it if I agree — otherwise the session stays read-only.

## Notes
- Default subject (no args) makes this a natural companion to `/wrap-session`'s
  comprehension checks — but `/explain` is for *learning on demand*, any time, not
  just at session end.
- If `$ARGUMENTS` names something not in the repo, say so and explain the closest
  real thing the repo *does* have, rather than inventing detail.
