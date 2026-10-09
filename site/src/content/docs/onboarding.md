---
title: Onboarding
description: What xal-factory init asks, what each answer does, and how to change it later.
---

`xal-factory init` sets up a factory in about two minutes. Every question shows its default,
Enter takes it, and every answer is followed by the one command that changes it later.

```bash
xal-factory init            # ask
xal-factory init --yes      # take every default
xal-factory init --set pipeline.chain=on --set plan.session_ceiling_usd=40   # script it
```

## What it asks

**The factory.** Your GitHub owner (read from `gh`), a name, and the ops repo's name and
location. The ops repo holds admitted specs, the status file, the cost ledger and the idea
inbox.

**How the factory runs.** The options marked *asked* on the [options page](/options/). The
defaults are the safe choice: the driver builds a session only when you dispatch it, nothing
chains, and nothing merges without you.

| Asked | Default | What you are choosing |
|---|---|---|
| escalation label | `needs-human` | the label a stopped pull request gets |
| fallback language | `go` | what `seed` pre-selects; the stack ADR still decides |
| driver model | the strongest | quality against cost, per session |
| plan and session ceilings | `$600`, `$70` | the spend bounds every plan starts with |
| driver | `on` | whether `/run-session` builds sessions, or you build them by hand |
| chain | `off` | whether a merged session dispatches the next |
| auto-merge | `off` | what may merge with no person present |
| status nudge, idea inbox | `on` | the ops repo's weekday nudge and `/idea` inbox |

## What it does

1. Checks your tools and that git has an identity (the seeders commit; it asks for one if
   not).
2. Seeds the ops repo with its gate, and writes your answers into its `.xal/factory.conf`:
   only the ones that differ from a default. That file is the **factory profile**: every
   service you seed starts from it.
3. Offers to create the ops repo on GitHub (private), open and pin the idea inbox, and switch
   its workflows to match. Say no and it prints the commands instead.
4. Prints a summary of every option and its value, and what to do next.

## Then

```bash
xal-factory seed orders     # a service repo, from the profile, with its gate and pipeline
cd orders && ./scripts/check.sh
xal-factory apply           # once pushed: workflows on or off as the profile says
```

The seeder prints what remains yours: installing the Claude GitHub App, setting three
secrets ([Credentials](/credentials/) says which kind of token each one is), and writing each secret's real expiry into `.xal/gate-inputs`. Gate 0 stays red
until you do, on purpose.
