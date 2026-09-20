# Contributing

This repo follows its own process. A PR clears the same bar the process asks of any repo.

## Before you open a PR

- **Run the gate:** `scripts/check.sh`. CI runs this exact script; if it is red locally it
  is red in CI. Gate 5 needs the `claude` CLI and skips locally without it.
- **Run the fixture harnesses:** `gates/check.test.sh` and `gates/seed.test.sh`. They prove
  the gates can fail. If you changed a gate, its fixture changes in the same PR.
- **A `spec/` change bumps `VERSION`** — patch for a clarification, minor for a new
  obligation, major for a breaking change — and says so in the PR title. Every consumer's
  drift gate goes red until it re-syncs; that is the point, so make the diff worth reading.
- **No language-specific token in normative spec prose.** Gate 1 will tell you. Put the
  illustration in a `**Reference:**` citation or mark the paragraph `<!-- reference -->`.
- **A vendored file links only to other vendored files**, relatively. Anything else is an
  absolute URL. Gate 2 will tell you.

## What lands here

A change to the process lands here only after it has been run for real somewhere: a gate
that fired, a convention that a service actually satisfied, a scaffold change that seeded a
repo whose CI went green. The PR says where. A rule that has never been exercised is a
claim, and this repo's own gate discipline says not to accept one.

**Nothing enters without a caller.** A new script is wired to something in the same PR; a
new fixture is named by a harness; a new convention is enforced by a gate or explicitly
tagged review-only.

## Decisions

A structural change — the sync model, the scaffold shape, the versioning policy, a new gate
rule — is an ADR in `adr/`, following `spec/adr-discipline.md`, opened as `Proposed` and
discussed in the PR. Routine changes are commits with a body that says why.

## Adding a language overlay

See `CLAUDE.md` → "Adding a language overlay". `scripts/check-seed-set.sh` refuses a partial
overlay, and the PR should show the overlay seeding a repo whose first CI run passed both
the gate and the fixture harness.

## Commit messages

Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`), small logical commits, the
reasoning in the body.
