---
name: service-conventions
description: The language-agnostic contract every service under the Xal Engineering Process must satisfy, and the gate discipline that enforces it. Consult whenever creating or modifying ANY part of a service repo — it defines the stable surface that makes services composable across languages.
---

# Service conventions

A system of independently versioned services, possibly in several languages, only stays
operable if every service exposes the **same operational and contract surface**.

> **LANGUAGE IS AN IMPLEMENTATION DETAIL BEHIND A STANDARD CONTRACT.**

## The contract lives in this repo's vendored spec

Every repo that follows the process vendors a read-only copy of the spec into its own
`docs/process/`. The authoritative documents for the repo you are working in are:

- **`docs/process/service-conventions.md`** — the operational + HTTP contract (API
  description, health, telemetry, structured logs, trace propagation, container interface,
  versioned event envelope, domain purity, variation-behind-contract).
- **`docs/process/deployment-conventions.md`** — the deployment contract (runtime as code,
  migrations as a release step, secrets and fail-fast, health wiring, the smoke gate, CD
  from `main`).
- **`docs/process/gate-discipline.md`** — what makes the gate script's verdict trustworthy
  (one script, the gate order, declared inputs, committed failing fixtures, exit codes,
  coverage ratchets, nothing without a caller).

Those paths are deliberately written as repo-relative text rather than links: this skill is
distributed as a plugin to many repos, and a link from the plugin's own directory cannot
reach the consuming repo's files.

`docs/process/sync.config` records which process spec version this repo is pinned to.

## The read-only rule

The files under `docs/process/` are **vendored copies** and must never be edited in place.
Byte-identity with the process spec is not a nicety — it is the enforcement mechanism,
because the drift check is a plain diff. A local edit cannot be reconciled; it only holds
the gate red.

To change a convention: change it in
[`xal-engineering-process/spec/`](https://github.com/xodeeq/xal-engineering-process/tree/main/spec),
bump that repo's `VERSION` per its policy, then re-sync here and review the diff. This is
one-way: the process is upstream of every repo, always.

## How to use this skill

- **Building or modifying a service:** open the documents above and treat them as the
  acceptance checklist. Each convention is stated language-agnostically; mirror the *intent*
  in this repo's language. Wire every **[CI-enforceable]** item into this repo's gate script
  and CI.
- **When you change code a convention cites:** re-read the rule and confirm it still holds.
- **If a change would break an invariant** — the HTTP or event contract, health, trace
  propagation, the variation-invariant core — that is a **contract-version decision**
  recorded as an ADR, not a quiet edit.
- **When you add a gate:** it ships with a committed failing fixture that names it, and its
  inputs are declared in `.xal/gate-inputs` before any workflow is touched.
