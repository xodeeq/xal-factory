---
title: FAQ
description: Common questions about the Xal Software Factory.
---

## Do I need Claude Code?

To build sessions with the driver and to have them read, yes: the driver and the reader run
Claude Code in GitHub Actions. The process itself (the spec, the gates, the seeders, the
ritual) needs no agent, and every pipeline workflow can be switched off.

## Which languages?

Go is the first language overlay. The spec is language-agnostic, and a new language is one
pull request adding `scaffold/lang/<name>/` with the artifact set the seed-set gate lists.
`stack.default_lang` only pre-selects a language: the stack is each service's first ADR.

## What does it cost?

Your Claude usage and your CI minutes. Every plan carries two ceilings, per plan and per
session, checked against a ledger every run appends to before the next session starts. They
bound spend to the ceiling plus one session. The defaults are $600 and $70.

## Can an agent merge to main without me?

Only inside the level you set, and only for the risk classes it admits. The default merges
nothing. See [Autonomy and risk classes](/autonomy/).

## Where does my configuration live?

In each repo's `.xal/factory.conf`, reviewed like code. The defaults come from one registry,
[`factory/options.tsv`](https://github.com/xodeeq/xal-factory/blob/main/factory/options.tsv),
listed on the [options page](/options/).

## Can I use it in an existing repo?

Yes: [Adopting](/adopting/) adds the same pieces a seeded repo is born with, one pull request
at a time, with the pipeline as the last and optional step.

## Where did it come from?

It was extracted from Xal's private estate, where every rule was run for real first. What
was lifted, from where and when, is in the
[lift ledger](https://github.com/xodeeq/xal-factory/blob/main/docs/lift-ledger.md).
