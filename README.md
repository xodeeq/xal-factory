# Xal Software Factory

**A software factory you can clone and run: the path from a one-line idea to a monitored
service, with a gate at every step that a script or a named person decides, and agents doing
the building inside bounds you set.** Made by [xodeeq](https://github.com/xodeeq).

Every rule here was extracted from a private, multi-service estate where it was earned by a
specific failure: a gate that passed because it matched nothing, a deploy blocked for hours
by an input one workflow forgot, an agent that reported success after being refused 26
times, a session that cost $20 and recorded nothing. The rules sit next to the failures, so
they read as decisions rather than preferences.

> **LANGUAGE IS AN IMPLEMENTATION DETAIL BEHIND A STANDARD CONTRACT.**

## The lifecycle

1. **Idea**: one line, `/idea`, into the ops repo's inbox.
2. **Research and spec**: a brief with sources, then a ten-section spec, every flag defaulted.
3. **Intake**: the spec is admitted verbatim, its digest in a ledger.
4. **Seed**: the service repo arrives with its gate and its pipeline; its stack is its first ADR.
5. **Plan and critic**: sessions with risk classes, gates and retry caps, checked by a script and an agent.
6. **Driver**: one session, headless, judged by the gate the workflow runs, never by the agent.
7. **Reader and merge**: read on Spec and Standards, merged only inside the autonomy level.
8. **Deploy and smoke**: a configured adapter, then a smoke gate against the live URL.
9. **Monitor and learn**: alert runbooks, the weekday nudge, the cost ledger, lessons promoted into gates.

Each stage has an artifact, a gate and a decider: [`spec/lifecycle.md`](spec/lifecycle.md).
The sessions that run them are typed contracts: [`spec/session-types.md`](spec/session-types.md).

**Autonomy is configured, never assumed.** A plan's `autonomy_level` says which risk classes
may merge with no person present (`unset`, `code-only`, `code-and-tests-pre-deployment`);
infrastructure, billing, public surfaces and deletions never do. Every pipeline workflow can
be switched off with one command and on again with another, and every option ships with a
default.

## What you get

| | |
|---|---|
| [`PRINCIPLES.md`](PRINCIPLES.md) | Nineteen principles, each stated as a decision rule. Start here. |
| [`spec/`](spec/) | The spec a repo vendors: the lifecycle, session types, service and deployment contracts, the gate discipline, ADR, concept-note and session rituals. |
| [`scaffold/`](scaffold/) | `seed-service.sh` seeds a service repo with its gate, CI, declared inputs, fixtures **and the pipeline** (driver, chain, merge, reader). `seed-ops.sh` seeds the factory's ops repo: spec intake, the plan critic, status and the weekday nudge, the cost ledger, the planning and research agents. Go is the first language overlay. |
| [`plugins/xal-factory`](plugins/xal-factory/) | For Claude Code: `/begin-session`, `/run-session`, `/wrap-session`, `/idea`, `/explain`, the reader agent, and the concept-note and service-conventions skills. |
| [`sync/`](sync/) | How a repo vendors the spec, and how drift becomes a red gate instead of a silent divergence. |
| [`adr/`](adr/) | The factory's decisions: sync, seeding, the plugin boundary, declared inputs, the plan format, the problem document, the driver, auto-merge. |
| [`docs/lift-ledger.md`](docs/lift-ledger.md) | Where every lifted file came from, and what was stripped on the way. |
| [`scripts/check.sh`](scripts/check.sh) | This repo's own gate. CI runs this exact script, and [`gates/check.test.sh`](gates/check.test.sh) proves each of its gates can fail. |

## Quickstart

```bash
git clone https://github.com/xodeeq/xal-factory.git

# once per factory: the ops repo (specs, status, cost ledger, idea inbox, agents)
xal-factory/scaffold/seed-ops.sh --name acme --dest ./acme-ops

# per service: a repo that arrives with its gate and its pipeline
xal-factory/scaffold/seed-service.sh \
    --name orders --lang go --module github.com/you/orders \
    --ops-repo you/acme-ops --dest ./orders
cd orders && ./scripts/check.sh
```

Both seeders print what remains a person's to do (installing the agent's app, setting
secrets with their expiry dates) and stop. The service seeder refuses to pick a language:
stack selection is a decision recorded as the new repo's first ADR.

**Configure a seeded repo** in `.xal/factory.conf`; `scripts/driver/config.sh --list` shows
every key, its value and whether it is the default.

**Use the plugin** in any repo (a seeded repo has it already):

```bash
claude plugin marketplace add xodeeq/xal-factory
claude plugin install xal-factory@xal-factory
```

**Adopt in an existing repo**: [`docs/adopting.md`](docs/adopting.md).

## The shape of a seeded service repo

```
<repo>/
├── CLAUDE.md                 the living source of truth: start-here ritual, laws, open decisions
├── scripts/check.sh          THE gate; CI invokes it verbatim; cheapest gate first
├── scripts/driver/           the pipeline's scripts, config.sh first
├── scripts/smoke.sh          the post-deploy gate
├── .xal/factory.conf         this repo's factory options; everything else is a default
├── .xal/gate-inputs          every input the gate needs, declared as data, with expiry
├── .xal/protected-paths      gate configuration a driven session may not change undeclared
├── gates/check.test.sh       proves the gate can fail, naming which gate, and can pass
├── gates/driver.test.sh      proves the pipeline refuses, and says why
├── .github/workflows/        ci, deploy, driver, chain, merge, reader, claude
├── docs/process/             the vendored spec, read-only, pinned in sync.config
├── docs/plan/plan.md         the sessions the driver runs, with status and evidence
├── docs/spec/service.md      a pointer to the admitted spec, by digest
├── docs/adr/                 decisions, starting with the stack
├── docs/sessions/NN.md       one handoff per work session
├── docs/lessons.md           capture → review → promote
└── openapi.yaml              the HTTP source of truth
```

## Versioning

`VERSION` is the spec version consumers pin to. A change to `spec/` bumps it — patch for a
clarification, minor for a new obligation, major for a breaking one — and is tagged
`v<VERSION>`. A consumer's drift gate goes red until it re-syncs and reviews the diff; that
is the mechanism, not a side effect.

## How this repo is maintained

The process is used daily in the author's private repositories. Improvements that prove
themselves there and are not specific to that product are lifted here, stripped of the
product (the strip gate checks), as their own PRs, each row recorded in
[`docs/lift-ledger.md`](docs/lift-ledger.md): the spec change with its `VERSION` bump, the scaffold change with its
fixtures. Nothing lands here that has not been run for real somewhere. See
[`CONTRIBUTING.md`](CONTRIBUTING.md) for the bar a PR has to clear.

## License

[MIT](LICENSE).
