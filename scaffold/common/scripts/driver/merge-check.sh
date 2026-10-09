#!/usr/bin/env bash
#
# merge-check.sh — the properties merge.yml must hold, asserted rather than trusted.
#
# WHY A STATIC CHECKER. merge.yml only acts when a real driver run ends, so its behaviour is
# unreachable from a fixture; its decision is merge-decision.sh's, which has fixtures of its
# own. What is left is the SHAPE of the workflow around that decision — and every rule below
# guards a way the shape could merge something the decision never approved, or approve
# nothing forever, while every gate stays green. chain-check.sh exists for the same reason one
# workflow over, and each rule here is a failure that file has already paid for once.
#
# THE RULES:
#
#   1. Exactly ONE merge, and it carries `--match-head-commit`. A second merge site is a path
#      around the decision; a merge without the sha pin can land a head pushed AFTER the
#      verdict was read.
#   2. No `--admin` and no `--auto`. The first overrides requirements; the second hands the
#      merge to GitHub to perform LATER, detached from the facts this run judged.
#   3. merge-decision.sh runs before the merge. It is the only thing allowed to say yes.
#   4. CI's verdict is read before the merge AND inside a retry loop. Read once, it finds
#      nothing — CI starts on the driver's last push at the same instant this workflow does —
#      and "unjudged is not green" then stops every session. chain.yml shipped exactly that
#      (run 35774727222); presence and ordering were both true and it was still dead.
#      The read is scripts/driver/ci-verdict.sh, through the Actions API, and the Checks API
#      (`check-runs`) is refused outright: GitHub gives fine-grained tokens no Checks
#      permission, so a check-runs read under a fine-grained FACTORY_WRITE_TOKEN is a 403 and
#      every session stops (the factory's first live proof, 2026-10-08).
#   5. The reader's verdict is read before the merge (ADR-0009 decision 10: a merge must not
#      race the reviewer).
#   6. The merge runs under FACTORY_WRITE_TOKEN. A merge authored by GITHUB_TOKEN triggers no
#      workflow, so chain.yml's `advance` would never fire and the plan would stop in silence.
#   7. It fires only on a SUCCESSFUL Driver run (or a manual dispatch), and it has a
#      concurrency group. A failed session must never reach the merge path, and two merge
#      decisions racing each other is the concurrency hazard the 2026-09-19 ruling names.
#
# Exit codes follow the driver's convention: 0 fine · 3 REFUSED, named · 2 cannot read the
# file, or the file is not a merge workflow at all.
#
# Usage: merge-check.sh --workflow .github/workflows/merge.yml

set -uo pipefail

WF=""
while [ $# -gt 0 ]; do
  case "$1" in
    (--workflow) WF="${2:-}"; shift 2 ;;
    (*) printf 'merge-check: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done
[ -n "$WF" ] || { printf 'merge-check: --workflow is required\n' >&2; exit 2; }
[ -f "$WF" ] || { printf 'merge-check: workflow not found: %s\n' "$WF" >&2; exit 2; }

# CODE ONLY, NOT PROSE, WITH LINE NUMBERS KEPT. Comment lines are blanked rather than deleted:
# the header of merge.yml explains `--match-head-commit`, `--admin` and `--auto` in words, and
# a rule that fires on the paragraph describing it is one whose cheapest fix is deleting the
# explanation (chain-check rule 3's first version did exactly that). Blanking keeps every
# remaining line at its real number, so an ordering rule and its error message agree — the
# second thing chain-check rule 9 got wrong once.
CODE="$(awk '{ if ($0 ~ /^[[:space:]]*#/) print ""; else print }' "$WF")"

refuse() {
  printf 'REFUSED: %s\n' "$1" >&2
  printf '::error title=Merge shape::%s\n' "$2" >&2
  exit 3
}
first_line() { printf '%s\n' "$CODE" | grep -nE -- "$1" | head -1 | cut -d: -f1; }

merges="$(printf '%s\n' "$CODE" | grep -nE 'gh pr merge' || true)"
if [ -z "$merges" ]; then
  printf 'merge-check: %s never runs `gh pr merge` — this file is not a merge workflow\n' "$WF" >&2
  exit 2
fi

# --- 1. exactly one merge, pinned to the judged sha --------------------------------------
[ "$(printf '%s\n' "$merges" | wc -l | tr -d ' ')" = 1 ] || \
  refuse "$WF merges in more than one place (lines $(printf '%s\n' "$merges" | cut -d: -f1 | tr '\n' ' ')) — a second merge site is a path around the decision" \
         "more than one merge site"
MERGE="$(printf '%s\n' "$merges" | cut -d: -f1)"
printf '%s\n' "$merges" | grep -q -- '--match-head-commit' || \
  refuse "the merge at line $MERGE does not pin --match-head-commit — a head pushed after the verdict could land unjudged" \
         "merge not pinned to the judged sha"

# --- 2. no override, no deferral ---------------------------------------------------------
bypass="$(first_line 'gh pr merge.*--(admin|auto)|--(admin|auto)\b.*gh pr merge')"
[ -z "$bypass" ] || \
  refuse "line $bypass merges with --admin or --auto — the first overrides requirements, the second merges later, detached from what this run judged" \
         "an override or deferred merge"

# --- 3. the decision precedes the merge --------------------------------------------------
DECIDE="$(first_line 'merge-decision\.sh')"
[ -n "$DECIDE" ] || refuse "$WF never runs merge-decision.sh — nothing decided that this merge may happen" "no merge decision"
[ "$DECIDE" -lt "$MERGE" ] || \
  refuse "merge-decision.sh runs at line $DECIDE, after the merge at line $MERGE" "the decision follows the merge"

# --- 4. CI's verdict is read first, and waited for ---------------------------------------
CHECKS="$(first_line 'check-runs')"
[ -z "$CHECKS" ] || refuse "$WF reads CI through the Checks API at line $CHECKS, which a fine-grained FACTORY_WRITE_TOKEN cannot reach (a 403 that stops every session): read it with scripts/driver/ci-verdict.sh" "CI read through the Checks API"
CI="$(first_line 'ci-verdict\.sh')"
[ -n "$CI" ] || refuse "$WF never reads CI's gate verdict for the head (scripts/driver/ci-verdict.sh)" "no CI verdict read"
[ "$CI" -lt "$MERGE" ] || refuse "CI's verdict is read at line $CI, after the merge at line $MERGE" "CI read after the merge"
window="$(printf '%s\n' "$CODE" | awk -v s="$CI" 'NR >= s - 10 && NR <= s + 10')"
printf '%s\n' "$window" | grep -qE 'for .*seq |while .*; do|until ' || \
  refuse "CI's verdict at line $CI is read once, with no retry around it — CI starts on the driver's last push at the same instant this workflow does, so a single read finds nothing and every session stops (chain.yml, run 35774727222)" \
         "the CI verdict is not waited for"

# --- 5. the reader's verdict is read first -----------------------------------------------
READ="$(first_line '/statuses')"
[ -n "$READ" ] || refuse "$WF never reads the reader's verdict — a merge must not race the reviewer (ADR-0009 decision 10)" "no reader verdict read"
[ "$READ" -lt "$MERGE" ] || refuse "the reader's verdict is read at line $READ, after the merge at line $MERGE" "reader read after the merge"

# --- 6. the merge is authored by the PAT -------------------------------------------------
tok="$(printf '%s\n' "$CODE" | head -n "$MERGE" | grep -E 'GH_TOKEN:' | tail -1)"
case "$tok" in
  (*FACTORY_WRITE_TOKEN*) ;;
  ("") refuse "the merge at line $MERGE has no GH_TOKEN in scope" "merge has no credential" ;;
  (*)  refuse "the merge at line $MERGE runs under $(printf '%s' "$tok" | tr -s ' ') — a GITHUB_TOKEN merge triggers no workflow, so chain.yml never advances and the plan stops in silence" \
              "merge would not trigger the chain" ;;
esac

# --- 7. only after a successful driver run, one decision at a time ----------------------
printf '%s\n' "$CODE" | grep -qE 'workflows:[[:space:]]*\[[[:space:]]*"Driver"' || \
  refuse "$WF is not triggered by the Driver workflow" "wrong trigger"
printf '%s\n' "$CODE" | grep -qE "workflow_run\.conclusion[[:space:]]*==[[:space:]]*'success'" || \
  refuse "$WF does not require the Driver run to have SUCCEEDED — a failed session would reach the merge path" \
         "no success filter on the driver run"
printf '%s\n' "$CODE" | grep -qE '^concurrency:' || \
  refuse "$WF has no workflow-level concurrency group — two merge decisions could race" "no concurrency group"

printf 'the merge is decided first (line %s), waits for CI (line %s) and the reader (line %s), lands once, pinned, as the PAT (line %s), and only after a successful driver run\n' \
  "$DECIDE" "$CI" "$READ" "$MERGE"
exit 0
