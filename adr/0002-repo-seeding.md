# ADR-0002: Repo seeding — a new repo begins with its gate

- **Status:** Accepted
- **Date:** 2026-09-20 (originally decided 2026-09-15, re-recorded here on extraction)
- **Deciders:** Process maintainer

## Context

The whole process rests on a gate script whose exit code decides pass: the session ritual
wraps on it, continuous deployment gates on it, any automated build pipeline decides on it.
A repo created without one does not fail loudly. It runs the whole pipeline emitting green
from a gate that is not there — the single most-repeated failure shape this process guards
against (a rule that matches nothing and a rule that finds nothing emit byte-identical
green), arriving at the one step that precedes all the others.

Two mechanisms looked like they should cover "every new repo begins with a gate", and
neither did. The scaffold (ADR-0001) had the right scope — it is what a new repo is copied
from — but shipped no gate script. A plugin reaches every repo but **cannot ship an
executable CI can run**: CI runs plain scripts, and bootstrapping a plugin before the gate
step would itself be a new gate input in every workflow in every repo (ADR-0004's problem,
reproduced by the mechanism meant to avoid it). The mechanism with the right scope had the
wrong reach and vice versa, and adoption was left to whoever remembered.

## Decision

### 1. The scaffold is the mechanism, grown up

```
scaffold/
  common/            everything language-agnostic
  lang/<language>/   the language-specific overlay; go/ is the first
  seed-service.sh    the seeder: copy common, overlay lang, sync the spec, fill placeholders
```

The seeder is plain bash with no inputs beyond the process checkout it lives in — the same
discipline as `process-sync.sh`, for the same reason: a seeding step that can need a
toolchain is a seeding step that can be missing one.

### 2. What a seeded repo contains on day one

| | Artifact | From |
|---|---|---|
| **Context** | `CLAUDE.md` from the template, pointing at the vendored conventions, with every undecided section left as an explicit placeholder | `common/` |
| **Gate** | `scripts/check.sh` in the process's gate order, realized for the language | `lang/<language>/` |
| | `.xal/gate-inputs`, pre-declared for that language's inputs, so gate 0 is live from commit one | `lang/<language>/` |
| | `.xal/check-gate-inputs.sh`, copied from **this repo's own `.xal/`** — one copy per repo, no extra replica pair | seeder |
| **CI** | `ci.yml`, invoking the gate script and its fixture harness and nothing else, supplying every declared input, checking out this repo for the drift gate | `lang/<language>/` |
| | `deploy.yml`, the CD-from-main shape, **dispatch-only at seeding** (§5) | `lang/<language>/` |
| | the agent workflows, inert until a person installs the App (§6) | `common/` |
| **Drift** | `docs/process/` vendored and `sync.config` pinned by the seeder running `process-sync.sh`; the drift gate is the last gate | seeder |
| **Docs** | `docs/spec/`, `docs/plan/`, `docs/adr/`, `docs/lessons.md`, `docs/briefs/`, `docs/concepts/`, `docs/sessions/` | `common/` |
| **Fixtures** | `gates/check.test.sh` with committed failing fixtures and a clean one | `lang/<language>/` |
| **Build** | `Dockerfile`, linter config, the coverage-floors file, an `openapi.yaml` stub, `.gitignore`, `.claude/settings.json` | mixed |

### 3. The fixtures, and why they are not a gate inside `check.sh`

The rule is one committed fixture proving the gate fails, **asserting which gate fired**,
plus a clean fixture proving it can say yes. Applied to `check.sh` itself the naive shape
recurses. So `gates/check.test.sh` copies the repo to a temp dir, overlays one fixture, runs
**that copy's** `check.sh`, and asserts both the exit code and the gate name; `ci.yml`
invokes it as a **separate step**. The Go realization ships two failing fixtures — one that
trips an early, cheap gate so the failing run is seconds, and one that trips the
coverage-floors gate, the only gate whose logic is hand-written rather than delegated to a
tool and therefore the only one that can be silently wrong — and one clean one. Fixture
source lives under `gates/_fixtures/`; the leading underscore keeps the Go tool from picking
it up in the repo's own gate run, and the format gate prunes it explicitly because the
formatter has no such rule.

### 4. The language comes from the repo's own first ADR, never from a default

`--lang` omitted is exit 2, not a default; `--lang` naming a missing overlay is exit 2,
listing what exists. A default language is a stack decision taken by a script, and stack
decisions are a person's, recorded as the repo's first ADR. The seeder writes
`.xal/seed.config` recording the language, the ADR path, the module path, the pinned
`VERSION` and the date, so "why is this repo Go?" resolves to a record, mechanically.

### 5. This repo gates the scaffold's completeness

`scripts/check-seed-set.sh`: every directory under `scaffold/lang/` ships the full required
artifact set, every overlay's `ci.yml` invokes both the gate and the harness, and the seeder
is **executed** with a missing and an unknown `--lang` and must exit 2 leaving nothing
behind. It ships with `gates/seed.test.sh` and one fixture per rule, each proving that rule
fires and no other. Rule 4 is behavioural on purpose: a default added later would be
invisible to any grep written today.

**One deviation, stated rather than smuggled.** The deployment conventions say the deploy
workflow triggers on push to `main`. A freshly seeded repo has no deploy target, and a
push-triggered `deploy.yml` would manufacture a red `main` on every merge from commit one —
which is how a signal becomes one everyone learns to ignore. The seeded `deploy.yml` is
dispatch-only, with the push trigger commented in place and a banner naming the human-only
action that un-comments it.

### 6. Human-only at creation

The line is blast radius, not difficulty. Creating the remote, pushing, opening the first
PR: reversible, the seeder's closing message says how. Writing the stack ADR; installing a
third-party App on the repo; minting its credential; making the repo public; provisioning
the deploy target: a person's. The seeder goes as far as `git init` and one commit, then
**stops and prints the list**, rather than reporting success over a repo whose agent
workflows are committed and silently inert. Those workflows ship at seeding precisely so
the install has something to activate.

## Rejected alternatives

**A GitHub template repository.** A second source of truth for content that already lives
in `scaffold/`, which nothing diffs; it cannot take a parameter, so "Go or Rust" becomes N
template repos; and a template repo is not gated, which is exactly how one comes to ship a
gate script that no longer runs.

**Copying the previous service by hand.** The status quo, and what produced the gap. It
carries one language into another repo and requires the copier to know which root files are
process contract and which are that service's own — a judgement satisfied ambiently and
therefore unreliably.

**A generator in a plugin.** Right reach, wrong mechanism: a plugin cannot ship an
executable CI can run without becoming a gate input in every workflow in every repo.

## Consequences

- **Positive:** "a new repo has a gate" is decided by `check-seed-set.sh` on every PR here,
  and "that gate can fail" by the seeded repo's own harness on every PR there. Neither is
  "someone remembers".
- **Positive:** a second language arrives as data — one directory under `scaffold/lang/` —
  and the gate refuses it until it is complete.
- **Cost — seeding is a one-shot copy.** A later improvement to `lang/go/scripts/check.sh`
  does not reach an already-seeded repo, and nothing diffs them. The gate script is a
  *starting point* a repo owns, while the *spec* is a contract it keeps tracking. Extending
  `sync/` to the gate script would mean a repo could not adapt its own gate, which is worse.
  Recorded as an open risk, not solved.
- **Cost:** `check-gate-inputs.sh` has one copy per seeded repo; drift between copies is
  detected only by whoever compares them.

## Revisit triggers

1. A second language is added and the `common/` / `lang/` split turns out to be in the wrong
   place; `ci.yml` is the likeliest candidate, being mostly boilerplate.
2. A seeded repo's `check.sh` diverges far enough from the scaffold's that the scaffold stops
   being a useful starting point; the answer is to re-extract, not to sync.
3. An unattended pipeline needs to seed a repo and the human-only stop in §6 blocks a run
   rather than protecting it; the response is to batch the human actions into a single
   approval, not to remove them.
