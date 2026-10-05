#!/usr/bin/env bash
#
# step-order.sh — the gate's verdict must be about the tree the driver will push.
#
# WHY THIS EXISTS. The toolchain is resolved before the agent, from the manifest that existed
# at checkout. A session may edit that manifest: the first service's plan S2 (2026-09-18) added a module
# and `go get` moved the `go` directive as a side effect. The pre-agent resolution had judged
# the tree green — while ci.yml re-read the edited file, resolved a different toolchain, and
# failed the audit gate with 22 standard-library advisories. The driver wrote `status: passed`
# into the plan for a tree CI rejects.
#
# Under v0 a person read every session PR and caught it. Under the chain that stops being
# true: preflight.sh reads `passed` and starts the next session on top, so a false green
# becomes the foundation of everything after it.
#
# THE RULE IS AN ORDERING, NOT A PRESENCE. "driver.yml mentions the toolchain" was always true
# and would have passed the defect unchanged. What has to hold is that the toolchain the gate
# runs under is established AFTER the agent can no longer change its inputs — which is why
# this script compares positions rather than grepping for a step name.
#
# THE RULE KNOWS NO LANGUAGE. The driver is seeded from the platform scaffold's common tree
# and the toolchain is the language overlay's, behind ONE composite action at
# `./.github/actions/toolchain` that both resolves the toolchain and installs the tools the
# gate shells out to. This rule asks only that the action runs between the agent and the
# gate. It does not ask what the action does, and it refuses an inline re-resolve for exactly
# that reason: it cannot see whether an inline step also reinstalled the gate's tools, and a
# re-resolve that leaves tools built by the previous toolchain in place is the same defect
# one layer down. The action is one unit so that neither half can be re-run without the other.
#
# Exit codes follow the driver's convention: 0 may run · 3 refused, with the reason · 2 the
# file could not be read or understood. A crashing bash script exits 1/127, so a deliberate
# decision is never confused with a fall-over.

set -uo pipefail

WF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --workflow) WF="${2:-}"; shift 2 ;;
    *) printf 'step-order: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$WF" ] || { printf 'step-order: --workflow is required\n' >&2; exit 2; }
[ -f "$WF" ] || { printf 'step-order: workflow not found: %s\n' "$WF" >&2; exit 2; }

# Line of the first step whose `- name:` contains the given text. Empty when absent.
line_of() {
  grep -n -- "- name:.*$1" "$WF" 2>/dev/null | head -1 | cut -d: -f1
}

AGENT="$(line_of "Run the session headless")"
GATE="$(line_of "Run the session's gate")"

[ -n "$AGENT" ] || { printf 'step-order: no agent step in %s\n' "$WF" >&2; exit 2; }
[ -n "$GATE" ]  || { printf 'step-order: no gate step in %s\n' "$WF" >&2; exit 2; }

if [ "$GATE" -lt "$AGENT" ]; then
  printf 'step-order: the gate precedes the agent in %s — this file is not a driver\n' "$WF" >&2
  exit 2
fi

# The overlay's toolchain action between the agent and the gate. Any one occurrence there
# re-reads the post-agent manifests and rebuilds the gate's tools under the result, which is
# the property being asserted.
TOOLCHAIN_ACTION='./.github/actions/toolchain'
RESOLVE=""
while IFS=: read -r n _; do
  [ -n "$n" ] || continue
  if [ "$n" -gt "$AGENT" ] && [ "$n" -lt "$GATE" ]; then RESOLVE="$n"; break; fi
done < <(grep -n "uses: *$TOOLCHAIN_ACTION" "$WF" 2>/dev/null)

if [ -z "$RESOLVE" ]; then
  printf 'REFUSED: the toolchain is not re-established between the agent (line %s) and the gate (line %s)\n' \
    "$AGENT" "$GATE" >&2
  printf '         by `uses: %s`. The gate then runs on a toolchain resolved BEFORE the agent —\n' "$TOOLCHAIN_ACTION" >&2
  printf '         or on one an inline step re-resolved without rebuilding the gate'"'"'s tools, which this\n' >&2
  printf '         rule cannot tell apart — and a session that edits its manifest is gated under the\n' >&2
  printf '         previous resolution. The driver can then write status=passed for a tree CI rejects.\n' >&2
  printf '         Run the toolchain action again after the agent, before the gate.\n' >&2
  exit 3
fi

# A STEP THAT ALWAYS RUNS NEEDS ITS PRECONDITIONS TO BE AT LEAST AS UNCONDITIONAL.
#
# Run 35437944054: the agent hit --max-turns, so its step failed. `Restore the push
# credential` carried no `if:`, which means success(), so it was skipped — while the state
# write is `if: always()`, so it ran, computed `S5 status=failed`, committed, and could not
# push. A session that had just cost $20.87 left NO record in the plan, which under chaining
# reads as "never attempted" and invites an identical re-dispatch.
#
# Checked as a RELATION rather than a value: it is not "the restore step says always", it is
# "the restore step is not more conditional than the write that depends on it". Both steps
# must exist for the question to mean anything, so a file lacking either is not judged here.
cond_of() {
  awk -v want="$1" '
    index($0, "- name:") && index($0, want) { found = 1; next }
    found && /^[[:space:]]*if:/ { sub(/^[[:space:]]*if:[[:space:]]*/, ""); print; exit }
    found && index($0, "- name:")           { exit }
    found && /^[[:space:]]*(run|uses):/     { print "success()"; exit }
  ' "$WF"
}

WRITE_LINE="$(line_of 'Write status and evidence')"
RESTORE_LINE="$(line_of 'Restore the push credential')"

if [ -n "$WRITE_LINE" ] && [ -n "$RESTORE_LINE" ]; then
  WRITE_IF="$(cond_of 'Write status and evidence')"
  RESTORE_IF="$(cond_of 'Restore the push credential')"
  if [ "$WRITE_IF" = "always()" ] && [ "$RESTORE_IF" != "always()" ]; then
    printf 'REFUSED: the state write is `if: %s` but the credential it pushes with is restored\n' "$WRITE_IF" >&2
    printf '         `if: %s` (line %s). On any agent failure the restore is skipped, the write\n' \
      "$RESTORE_IF" "$RESTORE_LINE" >&2
    printf '         still runs, and its push dies unauthenticated — the plan records nothing about\n' >&2
    printf '         a session that already cost money. Measured on run 35437944054.\n' >&2
    exit 3
  fi
fi

# EVERY RUN MUST RECORD AN ATTEMPT, WHATEVER IT COST.
#
# The spend ledger is where `attempts` is counted from, so a run that records nothing is a run
# that never happened. The cost comes from the agent's execution file, which exists only if
# the agent step completed — so conditioning the record step on a non-empty cost means a run
# CANCELLED mid-agent records nothing, `attempts` never rises, and the chain re-dispatches the
# same session forever. `retry_cap` is in the plan, is read by the chain, and can never fire.
#
# An unbounded loop that leaves no trace of itself is strictly worse than a ledger that
# undercounts, which is why the record step takes `always()` and defaults an unknown cost to
# zero with a loud warning. Checked as the ABSENCE of a cost precondition, because that is the
# exact shape the defect had.
RECORD_LINE="$(line_of 'Record what this run spent')"
if [ -n "$RECORD_LINE" ]; then
  RECORD_IF="$(cond_of 'Record what this run spent')"
  case "$RECORD_IF" in
    (*outputs.cost*|*outputs.turns*)
      printf 'REFUSED: the spend record at line %s is conditioned on `%s`.\n' "$RECORD_LINE" "$RECORD_IF" >&2
      printf '         A run cancelled mid-agent produces no execution file and so no cost —\n' >&2
      printf '         it would record NOTHING, `attempts` would never rise, and the chain\n' >&2
      printf '         would re-dispatch the same session forever. retry_cap could not fire.\n' >&2
      printf '         Record the attempt unconditionally; default an unknown cost to 0 loudly.\n' >&2
      printf '::error title=Driver shape::a cancelled run would record no attempt\n' >&2
      exit 3 ;;
  esac
fi

# THE COMMIT A PERSON MERGES MUST BE ONE CI HAS JUDGED.
#
# The gate here runs on the tree the agent produced, and ci.yml agrees on that commit. But
# the driver then writes the plan status as a FURTHER commit and pushes it, so the commit at
# the head of the pull request — the one a merge actually takes — is not the commit either
# verdict was about.
#
# That would be harmless if CI simply ran again on the new head. It does not, and the reason
# is a credential. A push authenticated with GITHUB_TOKEN is attributed to
# `github-actions[bot]`, and a `pull_request` run triggered by that identity lands in
# `action_required`: created, never executed, awaiting approval. A push authenticated with a
# user PAT runs normally. So the driver opening the PR with FACTORY_WRITE_TOKEN and pushing with
# GITHUB_TOKEN produces exactly one judged commit and one unjudged one, with the unjudged one
# on top.
#
# Measured on run 35472339107 (plan S6): the gated commit 5730fd7 was CI-green, and the PR
# head d4e946c carried no gate check at all. It is not new — plan S3's merged head 77be019
# and S4's b017e64 are on main with only GitGuardian against them; S2's and S5's heads have a
# gate only because a PERSON pushed their last commit by hand.
#
# WHY IT BLOCKS THE RULING RATHER THAN MERELY ANNOYING IT. the owner's 2026-09-19 verdict lets an
# automated run's PR merge with no human push "provided the gates that apply to a PR are
# obeyed", and with no branch protection on these private repos that guarantee has to live in
# our own code: the driver waits on its own CI conclusion and merges only on green. On the
# head commit that conclusion is `action_required` — neither green nor red. This is the
# `ungated` lesson one layer out: S5 taught that `failed` could not express "never judged",
# and CI cannot either, at the merge gate. A driver reading "not failed" as "green" would
# auto-merge a commit nothing has judged.
#
# Checked as a RELATION, like the one above it: not "the restore step names a PAT", but "the
# credential that pushes the head is the same one that opened the PR". Naming a specific
# secret would pass the day someone renames it and would say nothing about the property.
secret_of() {
  awk -v want="$1" '
    index($0, "- name:") && index($0, want) { found = 1; next }
    found && index($0, "- name:")           { exit }
    found {
      if (match($0, /secrets\.[A-Za-z_][A-Za-z0-9_]*/)) {
        print substr($0, RSTART + 8, RLENGTH - 8); exit
      }
    }
  ' "$WF"
}

PR_LINE="$(line_of 'Open the pull request')"

if [ -n "$PR_LINE" ] && [ -n "$RESTORE_LINE" ]; then
  PR_SECRET="$(secret_of 'Open the pull request')"
  PUSH_SECRET="$(secret_of 'Restore the push credential')"
  if [ -n "$PR_SECRET" ] && [ -n "$PUSH_SECRET" ] && [ "$PR_SECRET" != "$PUSH_SECRET" ]; then
    printf 'REFUSED: the pull request is opened with secrets.%s (line %s) but the push credential\n' \
      "$PR_SECRET" "$PR_LINE" >&2
    printf '         is restored from secrets.%s (line %s). The plan-status commit pushed with the\n' \
      "$PUSH_SECRET" "$RESTORE_LINE" >&2
    printf '         second credential becomes the PR HEAD, and a run triggered by that identity is\n' >&2
    printf '         left `action_required` rather than executed — so the commit a merge takes has\n' >&2
    printf '         no CI verdict at all. Measured on run 35472339107; S3 and S4 are on main that\n' >&2
    printf '         way. Push the head with the same credential that opens the pull request.\n' >&2
    exit 3
  fi
fi

# THE FAILURE NET MUST COVER A CANCELLATION, WHICH IS NOT A FAILURE.
#
# `if: failure()` does not match a job killed by `timeout-minutes` — GitHub reports that as
# CANCELLED, and a cancelled job skips every remaining step. Run 35440579899 proved it: the
# bundle and upload steps were skipped exactly when a net was most wanted. It cost nothing
# that time only because the timeout landed after the push; had it landed during the agent
# step, the session's work would have existed solely on a runner about to be destroyed.
BUNDLE_LINE="$(line_of 'Bundle the session')"
if [ -n "$BUNDLE_LINE" ]; then
  BUNDLE_IF="$(cond_of 'Bundle the session')"
  case "$BUNDLE_IF" in
    *cancelled\(\)*) ;;
    *)
      printf 'REFUSED: the bundle step is `if: %s` (line %s), which does not match a job killed\n' \
        "$BUNDLE_IF" "$BUNDLE_LINE" >&2
      printf '         by timeout-minutes — GitHub calls that CANCELLED, and a cancelled job skips\n' >&2
      printf '         remaining steps. The net would be absent in the one case it exists for.\n' >&2
      exit 3 ;;
  esac
fi

printf 'the gate is judged under the session'"'"'s own tree (toolchain re-established line %s, gate line %s)\n' \
  "$RESOLVE" "$GATE"
exit 0
