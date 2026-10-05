---
description: Dispatch the pipeline driver to build ONE session of the approved plan headless. You do not write the code, the driver does.
argument-hint: "[service] <session id> — e.g. `<SERVICE> S2`, or just `S2` from inside a service repo"
allowed-tools: Bash, Read, Grep
---

# /run-session

Run one session of `docs/plan/plan.md` through the driver.

> **YOU ARE NOT THE SESSION. DO NOT IMPLEMENT IT YOURSELF.**
>
> This is the failure mode this file exists to prevent. Asked to "run S2", the helpful
> thing to do looks like writing S2's code — and that bypasses the entire pipeline: no
> machine-authored commits, no gate run by the workflow, no status written into the plan,
> and a session that was supposed to prove the driver works instead proves nothing. Your
> job is to dispatch, watch, and verify. If the driver cannot run, say so and stop; do not
> substitute yourself for it.

## First, move into the service repo. Everything else follows from that.

A factory usually keeps its repos side by side in one workspace folder, and sessions often
start there so that each one has the whole system in view. Repo-aware commands run from that
folder would address the wrong repository.

**The answer is to `cd`, not to qualify every command.** One `cd` and then `git` and `gh`
both infer the repository from where they are: no `-R`, no owner, no service name anywhere
in the procedure. That matters beyond tidiness: this command ships in the plugin and serves
every service, so a hardcoded repository would be wrong for all but one. **Nothing below
names a service.**

```bash
# From the workspace folder, name the service. From inside one already, omit it.
SVC="${1:-.}"
[ -f "$SVC/docs/plan/plan.md" ] || { echo "no plan at $SVC/docs/plan/plan.md: name the service repo"; exit 2; }
cd "$SVC" || exit 2
```

Do this **before** running anything or changing anything. A session that starts work and
then works out where it is has already made a change somewhere it did not intend.

**If you are running sessions for more than one service concurrently, say which service in
your prompt.** There is no default and there should not be one: guessing the target of an
operation that opens pull requests and pushes branches is not a convenience.

## Before you dispatch

`preflight.sh` enforces all of this and refuses with exit 3 naming the reason, so none of
it is on you to guarantee — but checking locally costs seconds and a refused dispatch
costs a round trip:

```bash
git fetch -q origin && git log --oneline -1 origin/main
./scripts/driver/preflight.sh --plan docs/plan/plan.md --session <SID>

PLAN_ID=$(./scripts/driver/plan-read.sh --plan docs/plan/plan.md --fm plan_id)
git ls-remote --heads origin | ./scripts/driver/branch-check.sh \
  --branch "plan/$PLAN_ID/$(echo '<SID>' | tr 'A-Z' 'a-z')" --refs -
```

`preflight` exits **0** may run · **3** refused, with the reason · **2** it could not read
the plan. A refusal is a decision, not a fault: read it and stop.

## Dispatch

```bash
gh workflow run driver.yml -f session=<SID>            # the model comes from .xal/factory.conf
gh workflow run driver.yml -f session=<SID> -f model=<id>   # one run on another model, deliberately
```

If `gh` reports the workflow is disabled, the owner has switched the driver off for this
repo (`gh workflow enable driver.yml` reverses it). Say so and stop rather than building the
session by hand.

## Watch it, and know what each stop means

```bash
gh run list --workflow=driver.yml --limit 1
gh run view <id> --job=<job id>
```

| Step that fails | What it means |
|---|---|
| **Read the factory configuration** | `.xal/factory.conf` sets an unknown key or leaves `factory.ops_repo` unset. Costs nothing |
| **Fetch the admitted spec** | `FACTORY_READ_TOKEN` cannot reach the ops repo. **Costs nothing: it runs before the agent.** |
| …with `REFUSED` | the spec no longer matches the digest in the plan. The plan is about a different document and must be re-emitted. Do not work around this. |
| **Run the session headless** | check `What the agent was permitted to do`: non-zero denials is a config bug in `driver.yml`, not a model problem |
| **Commit the session's work** | "produced no changes" is a real failure. The session did nothing |
| **Run the session's gate** | the session's work is red. The driver still writes `status: failed` and leaves the PR open — that is correct, not a bug to fix |
| **Open the pull request** | a credential problem. The work is safe: the branch is already pushed |
| anything, unexpectedly | the job uploads a **bundle** of the whole branch as an artifact. No run's work is ever lost to a failed step |

## Afterwards — verify artifacts, never the summary

```bash
git fetch -q origin
git log --format='%h %an %s' origin/main..origin/plan/<plan-id>/<sid>
gh pr list --state open
```

- commits authored by `claude[bot]`
- the gate result in the driver run, not in anything the agent said
- `docs/plan/plan.md` on the branch showing that session's `status` and `evidence`

**Leave the pull request alone.** `merge.yml` lands it with no person present only if the
session passed, its risk class is within the plan's `autonomy_level`, CI is green, the reader
(`factory/reader`) found nothing and the head is current with main; otherwise it is labelled
with the factory's escalation label and a person reads it (ADR-0008 in the factory). Then
update the ops repo's `status/current.md` as `/wrap-session` requires.

## One dispatch is ONE session. There is no nesting.

A **plan session** (`S1`, `S2`, … in `docs/plan/plan.md`) is one dispatch, one GitHub Actions
job, one fresh `claude-code-action` invocation, one fresh checkout. There is no sub-session
structure beneath it and nothing accumulates between dispatches.

**Sessions share nothing but artifacts.** The handoff from one to the next is
`docs/plan/plan.md` plus merged code on `main` — not a conversation, not a summary, not
inherited context. That is deliberate: it is why the plan file is the state machine, and
it is what makes a session reproducible and a failed one re-runnable.

## Why nothing here names a service

The test for anything shipped in the plugin is *"would this be byte-identical in the next
repo?"*, and after the `cd` above, this procedure is. An improvement to it is a pull request
against the factory, not an edit in one service.

## What this command does not do

Chain to the next session, retry, escalate, enforce the ceilings, or merge — those are
`chain.yml` and `merge.yml`, and both fire on their own once a
dispatched session ends or merges. This command is the ONE deliberate entry: the first
session of a plan, or a re-entry after a person has cleared a stop. Once the chain is
running, dispatching by hand alongside it is the concurrency hazard the driver's
concurrency group exists to refuse.
