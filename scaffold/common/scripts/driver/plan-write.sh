#!/usr/bin/env bash
#
# plan-write.sh — write ONE session's `status` and `evidence` back into docs/plan/plan.md.
#
# This is the half of the driver that makes the plan the pipeline's state file (roadmap
# §4.5: "State lives in the plan file"). It is deliberately the narrowest possible writer:
# two fields, one session block, nothing else in the file may move.
#
# WHERE IT MAY WRITE, AND WHY IT MATTERS -------------------------------------------------
#
# The SESSION BRANCH, never `main`. The driver re-reads `main`'s plan at every session
# boundary (§4.4), so a driver able to write there is a driver able to mark its own failure
# passed, on the artifact every later decision is taken from. Writing on the branch puts the
# state change in the PR diff, where a person reads it next to the work that earned it.
# Nothing in this script enforces that — it writes wherever --plan points — so the
# obligation lives in driver.yml, which only ever runs it on a checked-out session branch.
#
# `ungated` IS NOT `failed`, AND THE DISTINCTION IS LOAD-BEARING. `failed` means the gate ran
# and said no. `ungated` means no verdict was produced at all — the run was cancelled by
# `timeout-minutes`, or the gate step was skipped because something upstream failed. Run
# 35440579899 is why the word exists: its gate was cancelled mid-run, the driver wrote
# `failed`, and the work turned out to be entirely green when ci.yml judged the same commit.
#
# Conflating them is cheap today, because a person reads every session. It stops being cheap
# at pipeline S6: retry logic reading `failed` cannot tell bad work from unjudged work, so it
# re-dispatches a session that may already be green — S5 cost $27 a run. Neither value
# satisfies a `depends_on`, so a plan does not advance on either; the difference is entirely
# in what the next decision should BE, which is the thing a state machine needs.
#
# A RED GATE IS STILL WRITTEN. `status: failed` with the PR and the failing run URLs is the
# point of the exercise. A session that fails and records nothing is indistinguishable from
# a driver that never ran, which is ADR-0003 item 5 ("a scheduled run may never fail
# silently") applied to the artifact rather than to the workflow.
#
# Usage:  plan-write.sh --plan P --session S1 --status passed --evidence "PR: <url> · CI: <url>"
# Exit:   0 both fields written
#         3 REFUSED — the status value is not in the vocabulary
#         2 CANNOT RUN — no plan, no such session block, or the fields are not where the
#           format says they are. Never 0 on a miss: a writer that silently writes nothing
#           reports success for a plan that still says the session never ran.
# Deps:   bash, awk, grep, mktemp.

set -uo pipefail

PLAN="docs/plan/plan.md"
SID=""
STATUS=""
EVIDENCE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --plan)     PLAN="$2";     shift 2 ;;
    --session)  SID="$2";      shift 2 ;;
    --status)   STATUS="$2";   shift 2 ;;
    --evidence) EVIDENCE="$2"; shift 2 ;;
    *) printf 'plan-write.sh: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then RED=$'\033[31m'; GREEN=$'\033[32m'; RST=$'\033[0m'
else RED=""; GREEN=""; RST=""; fi

cannot_run() { printf '%sCANNOT RUN: %s%s\n' "$RED" "$1" "$RST" >&2; exit 2; }

[ -n "$SID" ]    || cannot_run "--session is required"
[ -n "$STATUS" ] || cannot_run "--status is required"
[ -f "$PLAN" ]   || cannot_run "plan not found: $PLAN"

# The vocabulary is roadmap §7.2's, and it is closed. An unrecognised status written into
# the plan would be read by the next session boundary as something the driver understands.
case "$STATUS" in
  pending|running|passed|failed|ungated|escalated) ;;
  *)
    printf '%sREFUSED: status '\''%s'\'' is not one of pending | running | passed | failed | ungated | escalated%s\n' \
      "$RED" "$STATUS" "$RST"
    printf '::error title=Driver refused::plan-write.sh will not write status '\''%s'\''\n' "$STATUS"
    exit 3
    ;;
esac

grep -qE "^## Session $SID:" "$PLAN" || cannot_run "no '## Session $SID:' block in $PLAN"

TMP="$(mktemp)" || cannot_run "mktemp failed"
# shellcheck disable=SC2064
trap "rm -f '$TMP'" EXIT

# Replace the first `- status:` and `- evidence:` lines INSIDE the target block only. The
# block ends at the next `## ` heading, so a later session's identically-named fields are
# never in scope. Counts are printed on the last line and checked below: an edit that
# matched nothing must not report success.
awk -v sid="$SID" -v st="$STATUS" -v ev="$EVIDENCE" '
  $0 ~ "^## Session " sid ":" { inblock = 1; print; next }
  /^## / { inblock = 0; print; next }
  inblock && !wrote_s && /^-[ \t]+status:/   { print "- status: " st; wrote_s = 1; next }
  inblock && !wrote_e && /^-[ \t]+evidence:/ { print "- evidence: " ev; wrote_e = 1; next }
  { print }
  END { printf("\037%d\037%d\n", wrote_s + 0, wrote_e + 0) > "/dev/stderr" }
' "$PLAN" > "$TMP" 2> "$TMP.counts"

counts="$(cat "$TMP.counts")"; rm -f "$TMP.counts"
wrote_s="$(printf '%s' "$counts" | awk -F'\037' '{print $2}')"
wrote_e="$(printf '%s' "$counts" | awk -F'\037' '{print $3}')"

[ "$wrote_s" = "1" ] || cannot_run "no '- status:' line inside the $SID block — the plan format is not what this writer expects"
[ "$wrote_e" = "1" ] || cannot_run "no '- evidence:' line inside the $SID block — the plan format is not what this writer expects"

# Byte-count sanity: the file must still be a plan, not a truncated one. A writer that
# empties its target and exits 0 is the failure this line exists to make impossible.
[ -s "$TMP" ] || cannot_run "the rewritten plan is empty — refusing to replace $PLAN with it"

cat "$TMP" > "$PLAN"

printf '%s✔ %s: status=%s%s\n' "$GREEN" "$SID" "$STATUS" "$RST"
printf '  evidence: %s\n' "${EVIDENCE:-<empty>}"
exit 0
