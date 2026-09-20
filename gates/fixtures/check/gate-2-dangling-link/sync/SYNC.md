# The template + sync model

How a repo consumes the process spec without silently drifting from it. This realizes
[ADR-0001](../adr/0001-process-repo-and-sync-model.md), which chose **template + sync**
over git submodules and per-language packages.

## The model in one picture

```
process/spec/*.md   ──(seed-service.sh + process-sync.sh)──►   <repo>/docs/process/*.md   (read-only, vendored)
       ▲  edit here, the only source of truth                        │  pinned to a VERSION in sync.config
       └────────────  bump process/VERSION  ◄── drift detected by `--check` ─────────────┘
```

- **Template** — a new repo is seeded by [`../scaffold/seed-service.sh`](../scaffold/seed-service.sh),
  which lays down the docs structure, the gate script for the chosen language, CI, and an
  (empty) `docs/process/` landing dir, then runs the sync.
- **Sync** — [`process-sync.sh`](process-sync.sh) copies the spec files listed in
  [`manifest`](manifest) into the repo's `docs/process/` and records the process `VERSION`
  it pinned in `docs/process/sync.config`.

## Rules

1. **The spec is edited only in this repo.** Files under a consumer's `docs/process/` are
   **read-only vendored copies**. The copies are byte-identical to `spec/`, which is what
   makes `--check` a plain diff and a local edit unreconcilable — it only holds the gate red.
2. **A sync leaves changes unstaged.** `process-sync.sh` does not commit or stage; the
   consumer's normal **PR review is the drift review**: the diff of `docs/process/` shows
   exactly what spec changed, reviewed like any other change.
3. **`--check` makes "behind" visible.** Wire `process-sync.sh <process> --check` into the
   consumer's gate script (gate 9 in [`../spec/gate-discipline.md`](../spec/gate-discipline.md)).
   It exits 1 if any vendored file differs from the spec or the pinned version is stale, and
   2 if it could not run, so "the spec moved and this repo hasn't synced" is a gating,
   reviewable state rather than a silent one.
4. **Versioning.** Bump [`../VERSION`](../VERSION) whenever a `spec/` change should
   propagate (patch = clarification, minor = additive obligation, major = breaking); see
   [`../CLAUDE.md`](../CLAUDE.md). Tag the commit `v<VERSION>` so a consumer that prefers to
   sync on its own schedule can pin its CI checkout to the tag.

## Usage

```bash
# From the CONSUMING repo's root directory:

# vendor / update the spec (then review & commit the docs/process/ diff in your PR):
/path/to/xal-engineering-process/sync/process-sync.sh /path/to/xal-engineering-process

# CI / gate — fail if this repo is behind the process spec:
/path/to/xal-engineering-process/sync/process-sync.sh /path/to/xal-engineering-process --check
```

A freshly seeded repo already has `docs/process/` populated and `sync.config` written. A
re-run with no spec change is a clean no-op.

## What's in scope to sync

[`manifest`](manifest) lists the vendored files; keep it aligned with
[`../spec/README.md`](../spec/README.md). The manifest is the contract for "what a consumer
must carry a copy of" — add a spec file to both when it becomes a shared obligation.

### Rule: a manifest file's relative links may not escape the vendored set

A manifest file is copied **verbatim** into a consumer's `docs/process/`. Its links travel
with it, but its *neighbours* do not: inside a consumer, `../` resolves to that repo's
`docs/`, not to this repo's root. So a link that is perfectly correct here can be broken in
every consumer simultaneously, and it looks fine to anyone reviewing it here, which is
exactly how it goes unnoticed. It did: three such links shipped and reached a consumer
before a link check caught them.

Therefore, in any file listed in [`manifest`](manifest):

- **Allowed:** a relative link to another file **in the vendored set**, always as a bare
  sibling (`service-conventions.md`) — the whole set lands in one flat directory.
- **Not allowed:** any relative link outside that set — `../VERSION`, `../sync/SYNC.md`,
  `../adr/0001-….md`. Use an absolute
  `https://github.com/xodeeq/xal-engineering-process/blob/main/…` URL, or don't make it a link.
- **Move the link text too.** These links commonly use the path as their label; retargeting
  the URL alone leaves a label displaying a path that is wrong in a consumer.

Anywhere *outside* the manifest set — this file, `../README.md`, `../CLAUDE.md`, `../adr/` —
ordinary relative links are correct and preferred; those files are never vendored.

[`../scripts/check.sh`](../scripts/check.sh) gate 2 enforces this, and
[`../gates/check.test.sh`](../gates/check.test.sh) carries the fixture that reintroduces the
original bug.

See also [the old model](../sync/OLD-MODEL.md).
