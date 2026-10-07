#!/usr/bin/env bash
#
# select-next.sh — choose the session the chain runs next, or refuse and say why.
#
# THE RULE (ADR-0007 decision 10): the LOWEST-NUMBERED ELIGIBLE SESSION.
#
# Eligible means two things, and both are read from the plan on the default branch:
#   - every id in `depends_on` carries `status: passed`
#   - this session's own status is one that invites a run: EMPTY, `failed` or `ungated`
#
# Those are preflight's rules 6 and 7, and this script deliberately does NOT re-implement
# them as a second opinion. It implements SELECTION — which of several runnable sessions the
# chain picks — and preflight remains the thing that refuses. Two components enforcing the
# same rule is two places to disagree, and the driver would believe whichever ran last.
#
# WHY LOWEST-NUMBERED AND NOT CRITICAL-PATH-FIRST. Critical-path needs a graph computation
# and a tie-break rule of its own, and neither is pinnable by one committed fixture. This
# rule is deterministic, and one fixture proves it — which is the property that matters for
# a rule that selects work while nobody is watching. The acknowledged cost is real and was
# accepted rather than argued away: it ignores the critical path, so a session leading to
# the longest downstream chain waits behind a lower-numbered one that leads nowhere.
#
# WHY IT REFUSES ON AN ESCALATED SESSION ANYWHERE IN THE PLAN. `escalated` means a person
# owns that session (preflight rule 7). If the chain simply stepped over it and ran the next
# eligible one, the escalation would be a note nobody is forced to read, and unattended spend
# would continue after a known failure. The chain halts instead, which is decision 5's ruled
# shape: escalate, and stop.
#
# EXIT CODES — the driver's convention, and they are not interchangeable:
#   0  a session was selected; its id is on stdout, alone, for the caller to read
#   4  COMPLETE — every session has passed. Not a refusal and not a failure: the plan is done,
#      and the chain run that follows the last merge must read GREEN. It was exit 3 until
#      pipeline S7, which made that run red (36079123762, the merge that completed
#      the first plan) — and a red run for a finished plan trains everyone to ignore red.
#   3  REFUSED, with a named reason: nothing is eligible, or the chain must stop
#   2  CANNOT RUN — the plan is missing or unparseable; this decides nothing
#
# A crashing bash script exits 1, 2 or 127, so a refusal never uses 1. The id goes to stdout
# and every explanation goes to stderr, so `next="$(select-next.sh …)"` is exactly the id and
# nothing else — a caller that has to strip commentary is a caller that will one day strip
# the wrong line.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER="$HERE/plan-read.sh"

PLAN=""
while [ $# -gt 0 ]; do
  case "$1" in
    (--plan) PLAN="${2:-}"; shift 2 ;;
    (*) printf 'select-next: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$PLAN" ] || { printf 'select-next: --plan is required\n' >&2; exit 2; }
[ -f "$PLAN" ] || { printf 'select-next: plan not found: %s\n' "$PLAN" >&2; exit 2; }
[ -x "$READER" ] || [ -f "$READER" ] || { printf 'select-next: plan-read.sh not found beside this script\n' >&2; exit 2; }

sessions="$(bash "$READER" --plan "$PLAN" --sessions 2>/dev/null)"
rc=$?
if [ "$rc" -ne 0 ] || [ -z "$sessions" ]; then
  printf 'select-next: the plan has no readable session blocks (plan-read exit %s)\n' "$rc" >&2
  exit 2
fi

field() { bash "$READER" --plan "$PLAN" --session "$1" --field "$2" 2>/dev/null; }

# FIRST PASS: an escalated session anywhere halts the chain, whatever else is runnable.
# Checked over the WHOLE plan rather than only over candidates, because an escalated session
# that nothing depends on would otherwise be stepped over silently — and "nobody is blocked
# by it" is not the same as "a person is not waiting on it".
esc=""
while IFS= read -r sid; do
  [ -n "$sid" ] || continue
  if [ "$(field "$sid" status)" = "escalated" ]; then esc="${esc:+$esc }$sid"; fi
done <<< "$sessions"

if [ -n "$esc" ]; then
  printf 'REFUSED: the chain stops — %s is escalated and a person owns it.\n' "$esc" >&2
  printf '         Chaining past an escalation would keep spending after a known failure and\n' >&2
  printf '         leave the escalation as a note nobody has to read. Clear it, then re-dispatch.\n' >&2
  printf '::error title=Chain refused::a session is escalated (%s); the chain halts\n' "$esc" >&2
  exit 3
fi

# SECOND PASS: the lowest-numbered session that may run. `--sessions` emits plan order, which
# is the plan's own numbering, so the first match IS the lowest-numbered one; nothing here
# sorts, because re-sorting would silently disagree with the file if a plan were ever written
# out of order, and the plan-critic is what governs that.
pending=0
while IFS= read -r sid; do
  [ -n "$sid" ] || continue

  status="$(field "$sid" status)"
  case "$status" in
    (passed) continue ;;                       # done; nothing to select
    (running) continue ;;                      # another dispatch holds it
    (""|failed|ungated) ;;                     # runnable — an invitation to run again
    (*) continue ;;                            # unknown status: not ours to interpret
  esac

  pending=$((pending + 1))

  # Dependencies. `depends_on` reads as `[S3, S6, S7]`; strip the brackets and split, so a
  # one-element list and an empty list both work without a special case.
  deps="$(field "$sid" depends_on | tr -d '[]' | tr ',' ' ')"
  blocked=""
  for d in $deps; do
    [ -n "$d" ] || continue
    if [ "$(field "$d" status)" != "passed" ]; then blocked="${blocked:+$blocked }$d"; fi
  done

  if [ -z "$blocked" ]; then
    printf '%s\n' "$sid"
    printf '  selected %s (status %s, depends_on %s — all passed)\n' \
      "$sid" "${status:-empty}" "$(field "$sid" depends_on)" >&2
    exit 0
  fi
done <<< "$sessions"

if [ "$pending" -eq 0 ]; then
  printf 'COMPLETE: every session in this plan is passed — there is nothing to chain to.\n' >&2
  printf '::notice title=Chain::the plan is complete\n' >&2
  exit 4
fi

printf 'REFUSED: %s session(s) remain and none is eligible — every one is waiting on a\n' "$pending" >&2
printf '         dependency that has not passed. A chain cannot break this by itself.\n' >&2
printf '::error title=Chain refused::no eligible session (%s pending, all dependency-blocked)\n' "$pending" >&2
exit 3
