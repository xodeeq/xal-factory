# Adopting the process in an existing repo

Seeding is for new repos. An existing repo adopts the process by adding the same pieces a
seeded repo is born with, in this order, each one landing as its own PR so the repo's own
review sees it.

## 1. Vendor the spec

From your repo root, with this repo cloned as a sibling:

```bash
../xal-factory/sync/process-sync.sh ../xal-factory
```

This writes `docs/process/` and `sync.config`. Commit the result. Add a `docs/process/README.md`
like the scaffold's, so a reader knows the directory is read-only.

## 2. Give the repo one gate script

If you already have a check script, keep it and make it the one CI invokes verbatim. If
your gates live only in the workflow file, move them into `scripts/check.sh` and make the
workflow call the script. Put the gates in the process's order
(`docs/process/gate-discipline.md` §2), cheapest first. Add the drift gate last:

```bash
"$XAL_PROCESS_DIR/sync/process-sync.sh" "$XAL_PROCESS_DIR" --check
```

with `XAL_PROCESS_DIR` defaulting to `../xal-factory` and CI checking this repo
out into `.xal-process`. `scaffold/lang/go/scripts/check.sh` is the model, including the
"skip locally, mandatory under `CI=true`" shape for gates whose tool may be absent.

## 3. Declare the gate's inputs

Copy `.xal/check-gate-inputs.sh` from this repo into `.xal/` and write `.xal/gate-inputs`
with one row per input your gate script needs (a toolchain, a linter, the process checkout,
a credential with its expiry). Make gate 0 of your script run the checker. Run the script:
it will tell you which inputs it derived that you have not declared, and which workflows do
not supply them.

## 4. Prove the gate can fail

Add `gates/check.test.sh` modelled on the Go overlay's: copy the repo to a temp dir, overlay
one fixture, run that copy's `check.sh`, assert the exit code and the gate name. Commit one
cheap failing fixture, one for any gate whose arithmetic is hand-written, and a clean one.
Call the harness from CI as a separate step after the gate.

## 5. Add the session layer

- `docs/sessions/README.md`, `docs/briefs/README.md`, `docs/lessons.md`,
  `docs/concepts/README.md`, `docs/adr/README.md` — copy them from `scaffold/common/docs/`.
- A `CLAUDE.md` (or whatever your agent reads) with the start-here ritual, the standing
  laws, the gate command, and the open design decisions. `scaffold/common/CLAUDE.md.template`
  is the shape.
- Optionally, `.claude/settings.json` from `scaffold/common/.claude/` to enable the
  `xal-factory` plugin, which supplies `/begin-session` and `/wrap-session`.

Write the first handoff, `docs/sessions/01.md`, describing the adoption itself. The next
session reads it first.

## 6. Bring the service up to the conventions

Treat `docs/process/service-conventions.md` and `deployment-conventions.md` as a checklist.
Each **[CI-enforceable]** item you satisfy becomes a gate with a fixture; each
**[review-only]** item becomes a line in `CLAUDE.md`'s working agreements. Record anything
you decide *not* to satisfy as an ADR, so the gap is a decision rather than an omission.
