# ADR-0001: Process repo structure + template/sync consumption model

- **Status:** Accepted
- **Date:** 2026-09-20 (originally decided 2026-06-18, re-recorded here on extraction)
- **Deciders:** Process maintainer

## Context

A set of services in different languages needs one statement of the conventions they all
satisfy. The first service held the originals; the second service was about to copy them,
and copies drift. The conventions needed a home that no service owns, and a way for a
service to *consume* them that makes drift visible instead of silent.

Two mechanisms were considered and rejected before this one: **git submodules** (awkward
detached checkouts, easy to forget, and they pin a working copy rather than expressing
"conform to this spec") and **per-language packages** (premature — they multiply the
published-artifact surface across a polyglot set before there is enough shared *code*, as
opposed to shared *prose*, to justify it).

The load-bearing constraint to preserve: the process owns the language-agnostic **spec**;
each repo owns its language's **implementation**. The process must never contain
language-specific tooling as a normative requirement.

## Decision

A dedicated process repo (a sibling of each consuming repo) with this structure:

- **`spec/`** — the canonical shared assets: the lifecycle guide, the service and
  deployment conventions, the gate discipline, the ADR discipline and template, the
  concept-note structure, the session ritual. The only normative source; never
  language-specific.
- **`adr/`** — the process's own decision log (this file).
- **`scaffold/`** — the template a new repo is seeded from (ADR-0002).
- **`sync/`** — the consumption mechanism, below.
- **`VERSION`** — a semver spec version that consumers pin to.

**Consumption is vendored-copy + pinned-version sync, drift surfaced as a reviewable diff:**

1. A repo vendors a **read-only copy** of the `spec/` files (per `sync/manifest`) into its
   own `docs/process/`, recording the process `VERSION` it pinned in `sync.config`.
2. `sync/process-sync.sh <process-path>`, run from the consumer, copies the manifest files
   forward and updates the pinned version, **leaving the changes unstaged**, so the
   consumer's ordinary PR review *is* the drift review.
3. `sync/process-sync.sh <process-path> --check` (CI mode) compares the vendored copies and
   pinned version against the process repo and **exits 1 if the consumer is behind** (2 if it
   could not run), making "the spec changed and this repo hasn't synced" a visible, gating
   state rather than a silent one.

The spec is edited **only** in this repo; a vendored copy is never edited. Because the
copies are byte-identical, `--check` is a plain diff and a local edit is unreconcilable.

**A manifest file's relative links may not escape the vendored set.** A file is copied
verbatim into a consumer's `docs/process/`, where `../` means that repo's `docs/`. A link
that is correct here can be broken in every consumer at once. This repo's gate 2 enforces
it; it exists because three such links shipped and reached a consumer.

## Consequences

- **Positive:** one source of truth for conventions across every repo; the spec stops
  living in, and drifting from, whichever repo was built first.
- **Positive:** the spec-vs-implementation split is structural — gate 1 refuses a
  language-specific token in normative prose — so the process stays language-agnostic while
  each repo stays idiomatic.
- **Positive:** `--check` is the embryonic conformance gate for any future service
  catalogue: the same spec a catalogue would check against starts life as the synced spec.
- **Cost:** the sync step is a real, small process tax, and "behind on the spec" is a state
  that must be surfaced and reviewed. Accepted as cheaper than uncontrolled copy-paste drift.
- **Cost:** a `spec/` change here reds every consumer's drift gate until it re-syncs. That
  is deliberate; it makes `VERSION` bumps a considered act.
- **Deferred:** a generic export of the observability IaC modules into the scaffold.
  *Trigger:* a seeded service needs deployable observability.
