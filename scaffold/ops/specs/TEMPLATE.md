---
service: <service>
spec_version: 0.1.0
date: YYYY-MM-DD
status: draft
---

# <service>: <one line, what this service is>

<Phase and position. What this unit is the first of, what it revisits, what it unblocks.>

Verification basis: <every repo, ref, file and ruling this document was checked against.
A spec that names no basis is an opinion.>

## 0. What the private inputs changed (read first)

*Optional. Present from the second version onward: one row per input that moved the
document, so a reader who knows the last version can read only this.*

| # | Input | What it settled | Effect on this spec |
| :--- | :--- | :--- | :--- |
| V-1 | | | |

## 1. Purpose and boundary

Purpose. <One question this service answers for a deployment. Nothing else.>

In scope:
-

Out of scope, and who owns it instead:
- <Never just "out of scope" — name the owner, or the boundary is a gap.>

## 2. Decomposition and rationale

<Why this is one unit and not two, or three. The alternative decompositions considered
and why they were rejected.>

## 3. Functional requirements

<Numbered, individually testable, one obligation each. `<SVC>-FR-NN`. Every row carries
how it is verified — a test, a startup assertion, a named artifact. Verify artifacts, never self-reports.>

| # | Requirement | Verify |
| :--- | :--- | :--- |
| <SVC>-FR-01 | | |

## 4. Data ownership and schema sketch

<What this service owns and nobody else writes. Tables, keys, indexes that carry a
correctness obligation, retention. Ownership first, columns second.>

## 5. Synchronous interfaces

<The HTTP surface: paths, auth, status codes, the error shape. What a caller may
depend on, and what is deliberately not promised.>

## 6. Events

### 6.1 Envelope
### 6.2 Emitted
### 6.3 Consumed
### 6.4 Transport

## 7. Non-functional requirements

<Right-sized and justified. A latency target with no traffic estimate behind it is
decoration; say what the number is for.>

## 8. Human-only actions

<The irreversible line: the blast radius for this service. Everything reversible is an agent's;
everything here stops and waits. Each row says what the human does and when.>

| # | Action | When |
| :--- | :--- | :--- |
| stack | | |

## 9. Open decisions

<Each one a question the owner can answer, with the options and a recommendation — never a
placeholder. `Decision needed` = the owner's queue; `Blocked` = waiting on the world.>

| # | Decision | State |
| :--- | :--- | :--- |
| O-1 | | |

## 10. Source ledger

<Every input, what was read of it, and what it contributed. This is what makes the
document checkable by someone who does not trust it.>

| Source | Read | Contributed |
| :--- | :--- | :--- |
| | | |

## Appendix A. <optional>

*Appendices are permitted after section 10 and are not checked for structure. Use one
for material destined for another repo — a replacement passage, a draft ADR — so the
spec carries its own downstream changes instead of scattering them.*
