# Service scaffold

The seed a **new repo** is created from. A repo seeded from here arrives with its gate
already working — the gate script, its declared input contract, the CI that supplies those
inputs, and committed fixtures proving the chain can fail and can pass — so it conforms to
the process from commit one rather than from whenever someone remembers.

That last clause is the whole point, and it is recorded in
[ADR-0002](../adr/0002-repo-seeding.md). A repo created without a gate does not fail loudly.
It emits green from a gate that is not there.

## Create a new service

```bash
# from this repo:
scaffold/seed-service.sh \
    --name orders \
    --lang go \
    --module github.com/you/orders \
    --adr docs/adr/0001-stack-selection.md \
    --dest ../orders
```

Then, as the seeder's closing message says: run the gate locally, create the remote, push,
open the first PR. **Two things remain that only a person can do**: writing the stack ADR
the seed cites, and (if you use it) installing the Claude GitHub App and setting its secret.
The seeder prints them and stops rather than reporting success over a repo whose agent
workflows are committed and silently inert.

### `--lang` has no default, deliberately

A default language is a stack decision taken by a script. Stack selection is a per-service,
human-gated decision — made on that service's workload and recorded as **that service's
first ADR** — so the seeder exits 2 rather than guess, and exits 2 again for a language it
has no overlay for. `--adr` records where the decision lives; it lands in the new repo's
`.xal/seed.config`, so "why is this repo Go?" resolves to a decision record rather than to
whoever remembers.

## What's in here

```
common/            language-agnostic; every seeded repo gets all of it
lang/<language>/   the language overlay; the gate script, CI, Dockerfile, fixtures
seed-service.sh    the seeder
```

| Path | Purpose |
|---|---|
| `common/CLAUDE.md.template` | the repo's living-source-of-truth skeleton: the start-here ritual, the placeholders a session must decide deliberately |
| `common/.claude/settings.json` | registers this repo's plugin marketplace and enables `xal-factory` (the `/begin-session` and `/wrap-session` commands, the concept-note and service-conventions skills). Optional: the process is followable without an agent |
| `common/.github/workflows/claude*.yml` | the Claude GitHub App workflows — inert until the App is installed, which is why they ship at seeding: the install has something to activate. Delete if unused |
| `common/docs/spec/`, `common/docs/plan/` | where the service spec (or a pointer to it) and the multi-session build plan live. Seeded as real directories: a path a session writes to is part of the seed |
| `common/docs/{adr,concepts,briefs,sessions}/`, `docs/lessons.md` | the decision log, curriculum, ephemeral briefs, handoffs, improvement ledger |
| `common/docs/process/` | where the vendored process spec lands after sync (read-only) |
| `common/openapi.yaml.template` | the HTTP contract, stubbed — so the description-vs-routes gate has a source of truth to fail against rather than nothing to compare |
| `lang/go/scripts/check.sh` | the gate script, in the process's gate order, realized in Go |
| `lang/go/.xal/gate-inputs` | every input those gates need, declared as data |
| `lang/go/.github/workflows/ci.yml` | invokes the gate script and the fixture harness, nothing else; supplies every declared input |
| `lang/go/.github/workflows/deploy.yml` | the CD-from-main shape, dispatch-only until a deploy target exists (see its banner) |
| `lang/go/gates/` | the fixture harness and the committed fixtures that prove the gate chain can fail, naming which gate fired, and can still pass |

## Adding a language

One PR that adds `lang/<name>/` with the **full** artifact set.
[`../scripts/check-seed-set.sh`](../scripts/check-seed-set.sh) enumerates what that set is and
refuses a partial overlay, because a missing piece is silent: the seeded repo still builds,
and simply enforces less than everyone believes it does. Its fixtures are in
[`../gates/seed.test.sh`](../gates/seed.test.sh). Use `lang/go/` as the model: same gate
order, same `.xal/gate-inputs` shape, same fixture pairing, the language's own tools behind
each gate.

## What seeding does *not* do

**It is a one-shot copy.** A later improvement to `lang/go/scripts/check.sh` does not reach
an already-seeded repo, and nothing diffs them. That is deliberate: the gate script is a
starting point the service then **owns** and adapts, unlike the process spec under
`docs/process/`, which is a vendored contract the drift gate keeps current. Extending
`sync/` to cover the gate script would mean a service could not adapt its own gate.

The sync contract itself is unchanged by any of this — see
[`../sync/SYNC.md`](../sync/SYNC.md). Keep `docs/process/` in sync (the seeded gate script's
last gate does exactly that) so a service never silently drifts from the conventions.
