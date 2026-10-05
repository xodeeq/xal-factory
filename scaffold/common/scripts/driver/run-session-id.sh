#!/usr/bin/env bash
#
# run-session-id.sh — recover which plan session a finished Driver run was, from its title.
#
# WHY THIS IS A SCRIPT AND NOT FOUR LINES IN A WORKFLOW. Two workflows now need the answer —
# chain.yml (retry or escalate) and merge.yml (land it or stop) — and the first version of
# this logic in chain.yml read the WRONG FIELD: `workflow_run.head_branch`, which for a
# dispatched run is the ref it was dispatched ON, `main`, every time. The retry path refused
# every run it was handed and escalation was unreachable. Measured on run 35777940382. The
# lesson from S6 is that a fix recorded in one component is not learned by the system, so the
# answer lives here once and both callers use it.
#
# THE ONLY PLACE THE SESSION SURVIVES A DISPATCH is driver.yml's `run-name`
# ("Driver — S<n>"), which arrives in a `workflow_run` event as `display_title`. The event
# does not carry the inputs that started the run.
#
# EXIT CODES — the driver's convention:
#   0  the session id alone on stdout, and it is a session of the plan
#   3  REFUSED, named — the title names no session, or the plan does not declare it.
#      A caller must STOP here rather than guess: retrying or merging the wrong session
#      spends money or lands work nobody asked for.
#   2  CANNOT RUN — bad arguments or an unreadable plan
#
# Usage: run-session-id.sh --plan docs/plan/plan.md --title "Driver — S12"

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN="" TITLE="" TITLE_SET=0
while [ $# -gt 0 ]; do
  case "$1" in
    (--plan)  PLAN="${2:-}"; shift 2 ;;
    (--title) TITLE="${2:-}"; TITLE_SET=1; shift 2 ;;
    (*) printf 'run-session-id: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$PLAN" ] && [ -f "$PLAN" ] || { printf 'run-session-id: plan not found: %s\n' "${PLAN:-<none>}" >&2; exit 2; }
[ "$TITLE_SET" = 1 ] || { printf 'run-session-id: --title is required\n' >&2; exit 2; }

session="$(printf '%s' "$TITLE" | sed -n 's/.*[^A-Za-z]\(S[0-9][0-9]*\)$/\1/p')"
if [ -z "$session" ]; then
  printf 'REFUSED: the run is titled "%s", which names no session.\n' "$TITLE" >&2
  printf '         The session id reaches this point through driver.yml`s run-name and\n' >&2
  printf '         nothing else; a run predating that change cannot be identified.\n' >&2
  printf '::error title=Session unknown::cannot recover the session from "%s"\n' "$TITLE" >&2
  exit 3
fi

sessions="$(bash "$HERE/plan-read.sh" --plan "$PLAN" --sessions 2>&1)" || {
  printf 'run-session-id: plan-read.sh failed — %s\n' "$sessions" >&2; exit 2; }
if ! printf '%s\n' "$sessions" | grep -qx -- "$session"; then
  printf 'REFUSED: %s is not a session of %s.\n' "$session" "$PLAN" >&2
  printf '::error title=Session unknown::%s is not in this plan\n' "$session" >&2
  exit 3
fi

printf '%s\n' "$session"
exit 0
