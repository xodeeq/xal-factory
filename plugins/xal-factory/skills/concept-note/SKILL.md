---
name: concept-note
description: Generate a durable educational concept note that teaches a topic end-to-end for a human who wants to understand it — problem, mechanism from first principles, tradeoffs, what THIS repo chose and why. Invoke when the user asks to understand a concept or component deeply, or after building something non-trivial worth capturing. Notes are saved under docs/concepts/ and MUST cite real code in this repo and the relevant ADR.
---

# concept-note

Produce a **concept note**: a teaching document for a human who wants to *understand* a
topic end-to-end — **not** API reference, not a changelog. The reader should come away
understanding *why the thing exists, how it works, and why this repo built it the way it
did.*

**Invoke when:**
- the user asks to understand a concept or component deeply, or
- something non-trivial was just built and is worth a durable explanation (`/wrap-session`
  step 8 may suggest this).

## The structure and rules live in the vendored process spec

Follow **`docs/process/concept-note-structure.md`** in the repo you are working in (the
read-only vendored process spec). It defines the fixed six-section form (problem →
mechanism from first principles → tradeoff space → what this project chose and why →
comprehension checks → go deeper), the hard rules, and the quality bar.

That path is written as repo-relative text rather than a link: this skill is distributed as
a plugin to many repos, and a link from the plugin's own directory cannot reach the
consuming repo's files.

## Process

1. Pick a kebab-case `<topic>`. Identify the **ADR(s)** and the **specific code** the note
   will cite (open them — quote real names, not from memory).
2. Draft each section in the fixed order. In the "what this project chose" section, cite real
   files by path and link the relevant ADR.
3. Write `docs/concepts/<topic>.md`.
4. Update `docs/concepts/README.md` so the curriculum still reads as a coherent onboarding
   path (foundational concepts before the ones that build on them).
5. Offer the reader the comprehension checks interactively if they want active recall now.

**Reject the note** if it fails any item in the spec's quality bar — especially: it must cite
at least one real file in *this* repo that exists, link the relevant ADR, teach a mechanism
(not an API) in §2, and update the curriculum index.
