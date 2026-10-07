---
type: status
title: <FACTORY> operating status
updated: <DATE>
active_track: "Nothing in build yet. The first track is the first service: research, spec, intake, seed, plan."
next_action: "Write or admit the first spec (specs/README.md), then seed its service repo."
research_lane: ""
blockers: []
---

# <FACTORY> operating status

This file is the cross-session memory for the factory. Every session, in any repo, reads it
first and updates it last. The frontmatter is machine-read by `scripts/status-render.sh` (the
weekday nudge, `.github/workflows/nudge.yml`); the prose below is for people. What is not
written here, in a repo, or in an issue is lost.

## The one rule this file enforces

ONE active build track (only it ships code, infrastructure or repo changes), and at most ONE
research lane (read, evaluate, write up). Research pauses if the build track stalls.

## Decision queue

Decisions that are the owner's, each with its options and a recommendation. A decision is
not parked in a conversation: it is here, or in an issue, or it does not exist.

## Blocked

Waits on the outside world, each with what unblocks it and who checks.

## Cadence

- Weekdays: the nudge renders this file's frontmatter into the pinned `nudge` issue.
- Weekly review: drain the decision queue, triage the `ideas` inbox (every line accounted
  for), read the cost ledger against the ceilings, read gate 0's expiry warnings.
