#!/usr/bin/env bash
#
# branch-check.sh — refuse a session branch the remote cannot hold.
#
# WHY THIS IS A SCRIPT AND NOT FOUR LINES IN driver.yml ----------------------------------
#
# Because workflow YAML cannot be run locally, so a rule written there is a rule no fixture
# can prove. The check below has a negative case that matters as much as its positive ones
# — a SIBLING session branch (`…/s2`) must NOT block `…/s1`, or pipeline S6's chaining
# would refuse its own second session — and an untested rule that refuses everything looks
# exactly like one that refuses the right things, right up until it stops the pipeline.
#
# THE BUG IT EXISTS FOR, FOUND ON THE FIRST REAL DRIVER RUN (2026-09-17) -----------------
#
# A git ref and a directory cannot share a path. The planner named its plan-PR branch
# `plan/<plan-id>`; the driver names session branches `plan/<plan-id>/s<n>`. While the
# first exists, the remote can hold NONE of the second — and `git ls-remote --exit-code
# --heads origin plan/<plan-id>/s1` reports nothing, because the conflict is one level up.
#
# What that would have cost: the branch is created LOCALLY without complaint, the agent
# runs the entire session, and `git push` fails at the very end. The whole run paid for,
# nothing kept. Checking a precondition after the expensive step is the same shape as a
# gate that runs after the deploy, which is why this check runs before the agent does.
#
# Prefix matching uses `case`, never a regex: a branch name is not a safe ERE, and a `.`
# or `+` in a plan id would quietly widen the match — a rule matching more than it should
# is as wrong as one matching nothing, and harder to notice because it fails loudly on
# the wrong input.
#
# Usage:  git ls-remote --heads origin | branch-check.sh --branch plan/p/s1 --refs -
#         branch-check.sh --branch plan/p/s1 --refs some-file
# Exit:   0 the remote can hold this branch
#         3 REFUSED, naming the conflicting ref and which of the three conflicts it is
#         2 CANNOT RUN (no --branch, or the refs source is unreadable)
# Deps:   bash only.

set -uo pipefail

BRANCH=""
REFS=""
RETRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --branch) BRANCH="$2"; shift 2 ;;
    --refs)   REFS="$2";   shift 2 ;;
    --retry)  RETRY=1;     shift ;;
    *) printf 'branch-check.sh: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$BRANCH" ] || { printf 'branch-check.sh: --branch is required\n' >&2; exit 2; }
[ -n "$REFS" ]   || { printf 'branch-check.sh: --refs is required (a file, or - for stdin)\n' >&2; exit 2; }
[ "$REFS" = "-" ] || [ -f "$REFS" ] || { printf 'branch-check.sh: no such refs file: %s\n' "$REFS" >&2; exit 2; }

if [ "$REFS" = "-" ]; then input="$(cat)"; else input="$(cat "$REFS")"; fi

conflict=""
kind=""
while read -r _sha ref; do
  [ -n "${ref:-}" ] || continue
  name="${ref#refs/heads/}"
  if [ "$name" = "$BRANCH" ]; then
    conflict="$name"; kind="the branch already exists"
  fi
  case "$BRANCH" in
    "$name"/*) conflict="$name"; kind="a ref sits where this branch needs a directory" ;;
  esac
  case "$name" in
    "$BRANCH"/*) conflict="$name"; kind="a branch sits below the one being created" ;;
  esac
done <<EOF
$input
EOF

# A RETRY IS ALLOWED TO REUSE ITS OWN BRANCH, AND ONLY ITS OWN.
#
# Attempt 1 creates plan/<plan-id>/s<N> at step 5 of the driver, so EVERY retry of a real
# session met "the branch already exists" and was refused instantly. retry_cap was in the
# plan, read by the chain, and unreachable for the second time — measured 2026-09-22 on
# S10, where three attempts failed here in 53 seconds.
#
# `--retry` downgrades exactly that one case. The two D/F conflicts still refuse, because
# they are a different hazard: a ref and a directory cannot share a path, and no amount of
# intent makes that possible. So this permits reusing THIS session's branch and nothing else.
#
# What the caller then does is reset it to `main` — a retry means "try this session again",
# not "continue the wreckage" — and the failed attempt survives in its own run's bundle,
# which is what that net was built for.
if [ -n "$conflict" ] && [ "$RETRY" = "1" ] && [ "$kind" = "the branch already exists" ]; then
  printf '  %s exists and this is a retry — the caller may reset it to the base\n' "$BRANCH"
  exit 0
fi

if [ -n "$conflict" ]; then
  printf 'REFUSED: the remote cannot hold %s — %s: %s\n' "$BRANCH" "$kind" "$conflict"
  printf '::error title=Driver refused::cannot create %s (%s: %s)\n' "$BRANCH" "$kind" "$conflict"
  printf '    A git ref and a directory cannot share a path. A merged plan branch left\n'
  printf '    behind is the usual cause: delete it, then re-dispatch.\n'
  exit 3
fi

printf '  %s is free on the remote\n' "$BRANCH"
exit 0
