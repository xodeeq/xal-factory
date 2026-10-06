# The spec-intake layer

A **spec** is the document that says what a service must be, in enough detail that
building it is execution rather than design. This directory is where a spec becomes a
**typed artifact of the factory** instead of a file in a chat thread: "the process is a
repo", applied to the one input the build pipeline consumes.

| | |
|---|---|
| [`TEMPLATE.md`](TEMPLATE.md) | the typed format: frontmatter schema + the ten sections |
| [`admitted/`](admitted/) | admitted specs, one file per version, **verbatim** |
| [`ledger`](ledger) | the admission record: a sha256 per admitted file |
| [`../scripts/spec-intake-check.sh`](../scripts/spec-intake-check.sh) | the gate, ten rules |
| [`../gates/spec-intake.test.sh`](../gates/spec-intake.test.sh) | one committed failing fixture per rule |

## The format

**Frontmatter — four required keys, and only these are checked.**

```yaml
---
service: orders           # the service the spec governs; matches its directory
spec_version: 1.0.0       # semver; matches the filename
date: 2026-09-14          # ISO 8601 calendar date
status: APPROVED by the owner 2026-09-14, pending only the stack ADR
---
```

`status` opens with a state token — `draft`, `proposed`, `in-review`, `approved`,
`accepted`, `superseded`, `withdrawn`, `rejected` — and then says whatever else is true.
The token is what a machine reads; the rest is what a human needs. A closed vocabulary
was rejected deliberately: a real approval carries its conditions ("pending only the stack ADR, and
the m2m credential ADR landing before `feed=on`"), and a format that cannot hold them
forces the author to drop them at the door, which is the one thing intake must never do.

**Structure — ten numbered sections, in order, with these titles:**

| § | Title | What only this section answers |
|---:|---|---|
| 1 | Purpose and boundary | what the service is for, and what it is explicitly not |
| 2 | Decomposition and rationale | why this is one unit and not two |
| 3 | Functional requirements | the numbered, individually testable obligations |
| 4 | Data ownership and schema sketch | what it owns; nobody else may write it |
| 5 | Synchronous interfaces | the HTTP surface and its error contract |
| 6 | Events | emitted, consumed, envelope, transport |
| 7 | Non-functional requirements | the right-sized targets, not aspirations |
| 8 | Human-only actions | the irreversible line: what an agent must not do |
| 9 | Open decisions | what is still the owner's, stated as a question |
| 10 | Source ledger | every input, and what it settled |

A title may carry a suffix — `## 7. Non-functional requirements (right-sized)` is the
same section 7. A **section 0** (a preface: what changed since the last version) and
**appendices after section 10** are both permitted and neither is required.

**Flags — a table, and every flag ships with a default (rule 10, admissions from
2026-09-24).** Somewhere in the spec, usually §3, the unit's variation flags (platform
`service-conventions.md` §9) sit in a markdown table whose header has a `Flag` column and
a `Default` column; the other columns are the author's. Every row's Default cell is
filled. A flag that genuinely cannot be defaulted says `required: <why>` in that cell,
and that is expected to be rare: a person selecting the service answers
only those questions, and everything else runs on the default profile. The rule was ruled
on 2026-09-24 and binds by the ledger's `admitted` date, so a spec admitted earlier is
exempt until its next version.

```markdown
| Flag | Values | Default | Note |
|---|---|---|---|
| `storage` | postgres, sqlite | postgres | sqlite is for a single-node deployment |
| `tenant` | any string | required: names the client deployment | one per deployment |
```

Sections 8, 9 and 10 are the three the gate exists for. They are the ones an author
under time pressure drops, and they are the ones that make a spec *governable*: §8 is
where "humans gate the irreversible" is made concrete for this service, §9 is what routes to the owner's queue instead
of being guessed, and §10 is what makes every claim in the document traceable to the
artifact it came from (verify artifacts, never self-reports).

## Admission: verbatim, or flagged

**An admitted spec is copied byte-for-byte.** Intake types a document; it does not edit
one. If the source does not fit the format, the answer is never to reshape it quietly —
the transformation is **flagged in the admission PR** and the document goes in as it is,
or does not go in at all. A spec silently normalised at the door is a spec whose author
no longer recognises it, and every later claim to have "the approved spec" is then false
in a way no gate can see.

This is enforced, not promised. `ledger` records a sha256 per admitted file; the gate
recomputes it on every run, so a post-admission edit — however well-intentioned — is a
red build. Immutability is a claim about time, and a gate cannot see time, so the record
is **declared data** the gate can check.

To admit a spec:

1. `cp <source> specs/admitted/<service>/<spec_version>.md` — no edits, not even
   whitespace.
2. Append a record to `ledger`: `service | spec_version | sha256 | admitted | source`.
3. `scripts/spec-intake-check.sh` until green. Every failure is either a fix to the
   ledger or a **finding about the source document** — never a silent edit to it.
4. PR. The PR body names every rule that fired and how it was resolved.

A superseded version is **not deleted**. `0.2.0.md` and `1.0.0.md` sit side by side;
the ledger records both. What a spec said when a decision was taken is evidence, and
deleting it destroys the only copy of that evidence.

## Why this lives outside `docs/`

An admitted spec carries its author's frontmatter, held verbatim, and its `status` line
says whatever was true at approval ("approved by the owner, pending only the stack
decision"). A repo that checks its own documents against a frontmatter schema would find an
admitted spec outside that schema by construction. So the two are kept in two trees rather
than reconciled: `specs/` is not `docs/`, a document checker skips `specs/admitted/`, and
`spec-intake-check` scans nothing else. A finding in a verbatim copy is unfixable where it is
found, and a link checker run against a document at an address it was never written for
reports a defect in the checker's assumptions, not in the document.
