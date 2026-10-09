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

Pass `--ops-repo <owner>/<name>` as well when the factory's ops repo exists; it is written
to `.xal/factory.conf`, and the driver refuses to run without it. Then, as the seeder's
closing message says: run the gate locally, create the remote, push, open the first PR.
**What remains is a person's**: writing the stack ADR the seed cites; installing the Claude
GitHub App on the new repo; setting `CLAUDE_CODE_OAUTH_TOKEN`, `FACTORY_READ_TOKEN` and
`FACTORY_WRITE_TOKEN` as repository secrets; and writing each secret's real expiry into
`.xal/gate-inputs` in place of the placeholder gate 0 refuses. Which kind of token each
secret is, and its permissions: https://factory.getxal.com/credentials/ (`FACTORY_WRITE_TOKEN`
is a classic `repo` token for now). All are grants or
credentials, and none is scriptable. The seeder prints them and stops rather than reporting
success over a repo whose workflows are committed and silently inert.

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
| `common/CLAUDE.md.template` | the repo's living-source-of-truth skeleton: the start-here ritual, the rule that a plan session is dispatched rather than written, the placeholders a session must decide deliberately |
| `common/.claude/settings.json` | registers the factory's plugin marketplace and enables `xal-factory` (`/begin-session`, `/run-session`, `/wrap-session`, the reader agent, the concept-note and service-conventions skills). Optional: the process is followable without an agent |
| `common/.github/workflows/claude*.yml` | the Claude GitHub App workflows, inert until the App is installed, which is why they ship at seeding: the install has something to activate |
| `common/.github/workflows/{driver,chain,merge,reader}.yml` | **the pipeline** ([ADR-0007](../adr/0007-pipeline-driver.md), [ADR-0008](../adr/0008-auto-merge-and-the-reader.md)): the driver builds one plan session headless; the chain selects, retries, escalates and bounds spend; the merge lands a finished session when every condition holds; the reader reads every session PR first. Language-agnostic: the only language-specific step is `uses: ./.github/actions/toolchain`, the overlay's |
| `common/scripts/driver/` | the scripts those workflows run: the configuration reader, preflight, plan read and write, branch and spec checks, the session prompt, selection, spend, the merge decision, the reader's verdict, and the shape checkers for the driver, chain and merge |
| `common/gates/driver.test.sh`, `common/gates/_fixtures/` | the proof the pipeline refuses and says why: every rule with a committed failing fixture and a clean one. Runs from commit one |
| `common/docs/spec/`, `common/docs/plan/` | where the admitted-spec pointer and the multi-session build plan live. Seeded as real directories: a path the pipeline writes to is part of the seed |
| `common/docs/{adr,concepts,briefs,sessions}/`, `docs/lessons.md` | the decision log, curriculum, ephemeral briefs, handoffs, improvement ledger |
| `common/docs/process/` | where the vendored process spec lands after sync (read-only) |
| `common/openapi.yaml.template` | the HTTP contract, stubbed — so the description-vs-routes gate has a source of truth to fail against rather than nothing to compare |
| `lang/go/scripts/check.sh` | the gate script, in the process's gate order, realized in Go |
| `lang/go/.xal/gate-inputs` | every input those gates need, declared as data |
| `lang/go/.github/actions/toolchain/action.yml` | the ONE place the language's toolchain is resolved and the gate's tooling installed, with every pin; `ci.yml`, `deploy.yml` and the driver call it, and the driver calls it again after the agent so the gate judges the tree it will push |
| `lang/go/.github/workflows/ci.yml` | invokes the gate script and the fixture harness, nothing else; supplies every declared input through the toolchain action |
| `lang/go/.xal/protected-paths` | the overlay's gate-configuration paths (`.golangci.yml`) that `merge-decision.sh` protects beyond the built-in pipeline paths |
| `lang/go/.github/workflows/deploy.yml` | the CD-from-main shape, dispatch-only until a deploy target exists (see its banner) |
| `lang/go/gates/` | the fixture harness and the committed fixtures that prove the gate chain can fail, naming which gate fired, and can still pass |

## Adding a language

One PR that adds `lang/<name>/` with the **full** artifact set.
[`../scripts/check-seed-set.sh`](../scripts/check-seed-set.sh) enumerates what that set is and
refuses a partial overlay, because a missing piece is silent: the seeded repo still builds,
and simply enforces less than everyone believes it does. Its fixtures are in
[`../gates/seed.test.sh`](../gates/seed.test.sh). The same gate asserts that `common/` ships
the whole pipeline — the four workflows, `gates/driver.test.sh`, and every
`scripts/driver/*.sh` those files name — so a driver that lost a script would fail here, in
the PR, rather than in the first repo seeded from it.

**What the pipeline asks of a language overlay.** Exactly one thing: a composite action at
`.github/actions/toolchain/action.yml` that resolves the language's toolchain from the repo's
own manifest and installs whatever the gate script shells out to. The driver runs it before
the agent and again after, `scripts/driver/step-order.sh` asserts that ordering without
knowing the language, and `.xal/gate-inputs` names the action's path as the caller pattern
for the inputs it supplies. Optionally, `.xal/protected-paths` lists the overlay's gate
configuration files so a driven session cannot change them undeclared. The Go overlay is the
worked example of both.

## What seeding does *not* do

**It is a one-shot copy.** A later improvement to `lang/go/scripts/check.sh` does not reach
an already-seeded repo, and nothing diffs them. That is deliberate: the gate script is a
starting point the service then **owns** and adapts, unlike the process spec under
`docs/process/`, which is a vendored contract the drift gate keeps current. Extending
`sync/` to cover the gate script would mean a service could not adapt its own gate.

The sync contract itself is unchanged by any of this — see
[`../sync/SYNC.md`](../sync/SYNC.md). Keep `docs/process/` in sync (the seeded gate script's
last gate does exactly that) so a service never silently drifts from the conventions.
