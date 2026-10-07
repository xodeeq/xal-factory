# Xal Software Factory

**A language-agnostic engineering process you can clone and build on: a spec every repo
vendors, a scaffold that seeds a new repo with a working gate, and the discipline that keeps
the gate's verdict honest.** Made by [xodeeq](https://github.com/xodeeq).

It was extracted from a private, multi-service, polyglot estate where every rule here was
earned by a specific failure — a gate that passed because it matched nothing, a deploy
blocked for hours by an input one workflow forgot, a spec link that was correct at home and
broken in every consumer. The rules are written next to the failures, so they read as
decisions rather than preferences.

> **LANGUAGE IS AN IMPLEMENTATION DETAIL BEHIND A STANDARD CONTRACT.**

## What you get

| | |
|---|---|
| [`PRINCIPLES.md`](PRINCIPLES.md) | The principles, each stated as a decision rule. Start here. |
| [`spec/`](spec/) | The canonical spec a repo vendors: the lifecycle guide, the service and deployment contracts, the gate discipline, ADRs, concept notes, the session ritual. |
| [`scaffold/`](scaffold/) | `seed-service.sh` and the `common/` + `lang/<language>/` trees it seeds from. A seeded repo arrives with its gate, its CI, its declared inputs and its failing fixtures. Go is the first language overlay. |
| [`sync/`](sync/) | How a repo vendors the spec and how drift becomes a red gate instead of a silent divergence. |
| [`plugins/xal-factory`](plugins/xal-factory/) | For Claude Code users: `/begin-session`, `/wrap-session`, the concept-note skill and the service-conventions skill. Optional; the process needs no agent. |
| [`adr/`](adr/) | This repo's own decisions: the sync model, seeding, the plugin boundary, declared gate inputs. |
| [`scripts/check.sh`](scripts/check.sh) | This repo's own gate. CI runs this exact script, and [`gates/check.test.sh`](gates/check.test.sh) proves each of its gates can fail. |

## Quickstart

**Seed a new service** (the whole point):

```bash
git clone https://github.com/xodeeq/xal-factory.git
xal-factory/scaffold/seed-service.sh \
    --name orders --lang go --module github.com/you/orders --dest ./orders
cd orders && ./scripts/check.sh      # the gate; some gates skip locally without their tool
```

The seeder refuses to pick a language for you: stack selection is a human decision recorded
as the new repo's first ADR, and the seeder records which ADR in `.xal/seed.config`.

**Adopt the process in an existing repo**: see [`docs/adopting.md`](docs/adopting.md). In
short, vendor the spec, add the drift gate and the declared-inputs meta-gate to your gate
script, and add a fixture harness.

**Use the Claude Code plugin** in any repo (a seeded repo has this already):

```bash
claude plugin marketplace add xodeeq/xal-factory
claude plugin install xal-factory@xal-factory
```

## The shape of a conforming repo

```
<repo>/
├── CLAUDE.md                 the living source of truth: start-here ritual, laws, open decisions
├── scripts/check.sh          THE gate; CI invokes it verbatim; cheapest gate first
├── .xal/gate-inputs          every input the gate needs, declared as data, with expiry
├── .xal/check-gate-inputs.sh gate 0: asserts every caller supplies every input
├── gates/check.test.sh       proves the gate can fail, naming which gate, and can pass
├── docs/process/             the vendored spec, read-only, pinned in sync.config
├── docs/adr/                 decisions: Context → Decision → Consequences
├── docs/sessions/NN.md       one handoff per work session; the next session's entry point
├── docs/lessons.md           capture → review → promote
├── docs/concepts/            the curriculum: teach the system, cite real code
├── docs/briefs/              ephemeral forward briefs, normally empty
└── openapi.yaml              the HTTP source of truth
```

## Versioning

`VERSION` is the spec version consumers pin to. A change to `spec/` bumps it — patch for a
clarification, minor for a new obligation, major for a breaking one — and is tagged
`v<VERSION>`. A consumer's drift gate goes red until it re-syncs and reviews the diff; that
is the mechanism, not a side effect.

## How this repo is maintained

The process is used daily in the author's private repositories. Improvements that prove
themselves there and are not specific to that product are lifted here, xal-stripped, as
their own PRs: the spec change with its `VERSION` bump, the scaffold change with its
fixtures. Nothing lands here that has not been run for real somewhere. See
[`CONTRIBUTING.md`](CONTRIBUTING.md) for the bar a PR has to clear.

## License

[MIT](LICENSE).
