# ADR-0003: The `.claude/` boundary — a plugin-distributed normative core plus a repo-owned overlay

- **Status:** Accepted
- **Date:** 2026-09-20 (originally decided 2026-08-15 and recorded 2026-09-17, re-recorded here on extraction)
- **Deciders:** Process maintainer

## Context

`sync/manifest` covers `spec/` → `docs/process/` and nothing else. The first scaffold also
shipped the session-ritual commands (`/begin-session`, `/wrap-session`) and the skills under
`scaffold/.claude/`, as a one-time copy at repo creation that `--check` never inspected. They
drifted, silently and permanently: two repos' `/wrap-session` restated the ritual that
`spec/session-ritual.md` owned canonically, with no mechanism to notice when they disagreed.

Three options were on the table: (a) extend the sync model to cover `.claude/`; (b) split
into a synced normative core plus an explicitly repo-owned overlay; (c) accept the drift
deliberately and say so.

## Decision

**Option (b): a normative core distributed as a Claude Code plugin, plus an explicitly
repo-owned overlay.** `sync/manifest` is **not** extended to cover `.claude/`.

The boundary is one duplication test, and it is the same test that drives the spec
extraction — do not invent a second:

> **If a definition would be byte-identical in the next repo, it belongs in the plugin. If
> it encodes something true only of this repo, it stays in that repo's `.claude/`.**

Applied:

| Plugin-distributed core (shared, one-way) | Repo-owned overlay (local, owned) |
|---|---|
| the session ritual commands, the concept-note skill, the service-conventions skill (`xal-factory`) | the repo's `CLAUDE.md`: bounded context, stack, ADR index, the gate command |
| language-agnostic agent definitions, when they exist | language-specific agent definitions and commands |

**Sync is one-way.** Shared behaviour changes by a PR against this repo, never by editing an
installed copy. The plugin's commands name no gate command, no language and no test
framework; those live in the consuming repo's `CLAUDE.md`, which the commands tell the
reader to consult.

**The scaffold registers the marketplace and enables the plugin** through
`scaffold/common/.claude/settings.json`, so a seeded repo gets the core without a manual
install step and holds no copy of it. **The scaffold's `.claude/` otherwise ships empty**:
the overlay is the repo's to write.

### Alternatives considered

**(a) Extend `sync/manifest` to cover `.claude/`.** Rejected. It needs a second manifest or
destination paths, plus a rule for the parts a repo legitimately customises — a
`/wrap-session` that names one repo's gate script must not be inherited verbatim by a repo
in another language. More decisively, **a file copy has no version identity.** A marketplace
gives pinning and an explicit update step; `cp -r` gives neither, which is how the drift
started. Extending the copy mechanism would have scaled the failure, not fixed it.

**(c) Accept the drift and say so.** Rejected, but it deserves its due: honest, free, and it
removes the false assurance that `--check` covers `.claude/`. Rejected because the drift is
not benign — two statements of the session ritual that disagree is a correctness problem in
the thing that governs every session. Option (c) remains the right answer for anything
genuinely per-repo, which is what the overlay is.

**Seed from the plugin instead of distributing through it.** Rejected by ADR-0002: a plugin
is not resolvable from a plain CI `run:` step, so it cannot carry the gate script. "Distribute
as a plugin" and "seed from a plugin" look alike and are not.

## Consequences

- **Positive.** One statement of every shared behaviour, changed by PR with a reviewable
  diff, with version identity and an explicit update step. The process remains usable
  without an agent: the commands are launchers for a ritual the spec states in full.
- **Negative / cost.** Two distribution channels to keep straight, and the boundary is a
  judgement call on every new file — stated, not gated. A shared change now requires a
  release, a tag and an update in each consumer, which is slower than editing a copy in
  place, and that is the speed being given up on purpose.
- **Negative.** Plugin marketplaces are registered per machine by name, last-write-wins, so
  two repos on one machine pinned to different plugin versions may resolve the same one.
  Until per-repo pinning exists, ship **additive changes only** to the plugin: additive is
  the only change shape whose blast radius is known.
- **Deferred.** A gate for the boundary itself — nothing asserts that an overlay file could
  not have been shared. *Trigger:* the second time review catches a local reimplementation
  of a core behaviour.
