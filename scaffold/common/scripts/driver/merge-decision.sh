#!/usr/bin/env bash
#
# merge-decision.sh — decide whether a finished session's pull request may land with no
# person present. Pipeline S7; ADR-0008 in the factory.
#
# THE RULING THIS IMPLEMENTS, 2026-09-19: automated runs' PRs merge with no human push,
# PROVIDED THE GATES THAT APPLY TO A PR ARE OBEYED. There is no branch protection on these
# private repos (403 without GitHub Pro, and Pro was refused 2026-09-24), so GitHub enforces
# none of it. This script is where "obeyed" is decided, and merge.yml is only the thing that
# gathers the facts and acts on the answer. That split is the one select-next.sh and spend.sh
# already make: the component that decides whether something irreversible happens must be
# runnable by anyone, offline, against a committed fixture.
#
# WHAT IT READS, AND FROM WHERE — the part that is easy to get wrong ---------------------
#
#   autonomy_level  from MAIN's plan. Never from the session branch.
#   risk_class      from MAIN's plan. Never from the session branch.
#   status          from the HEAD's plan, because that is the only place the driver writes it.
#
# A session branch that could state its own autonomy or its own risk class would be a branch
# approving its own merge — the same shape driver.yml refuses at the top ("the plan must be
# the one on the default branch"), arriving at the other end of the pipeline. And because the
# head's plan IS read, the head may differ from main's plan in exactly two lines — this
# session's `status` and `evidence`, which the driver writes — and in nothing else.
#
# WHAT MAY MERGE -------------------------------------------------------------------------
#
#   autonomy_level                   the risk classes it admits
#   code-only                        code-only
#   code-and-tests-pre-deployment    code-only, data-migration, secrets        (R1, 2026-09-16)
#   unset, or anything else          nothing — REFUSED, named
#
# `infra`, `billing`, `public-surface` and `delete` are admitted by no value. Widening into
# one of them is a new ruling, never a threshold being met (roadmap §6b).
#
# ... and only when ALL of these hold, checked in this order:
#
#   1. the head's plan differs from main's in this session's status/evidence lines only
#   1b. the pull request edits no GATE or PIPELINE path its session block does not declare as
#      an artifact. CI runs the head's OWN scripts/check.sh, so a session that weakened the
#      gate would be judged green by the gate it weakened; with a person reading every PR that
#      was caught by eye, and from S7 nothing reads a merged-unattended PR before it lands.
#      Protected: scripts/ gates/ .github/ .xal/ docs/process/ — the pipeline's own paths,
#      the same in every service — plus whatever `.xal/protected-paths` lists, which is
#      where a language overlay names its gate's configuration (the reference Go overlay
#      lists `.golangci.yml`, the linter config). Read from the checkout this script runs
#      in, which merge.yml makes MAIN, so the head cannot widen or shrink the list. A plan
#      that means a session to change its gate says so in `artifacts`, which the owner approved
#      — S3, S7 and S15 of the first service's plan all did.
#   2. this session's status on the head is `passed`
#   3. autonomy_level is in the vocabulary, and admits this session's risk_class
#   4. CI's gate check on the head concluded `success` — anything else, INCLUDING NO VERDICT,
#      refuses. An unjudged head is not a green one; this is the red-PR fixture the
#      2026-09-19 ruling requires, and its absent-verdict twin.
#   5. the reader's verdict on the head is `success` — a finding, a pending run, or no
#      verdict at all refuses. ADR-0009 decision 10: a merge must not race the reviewer.
#   6. the head is not behind main. If it is, the answer is `update`, not `merge`: two
#      sessions green against their own bases can be red combined, and with no merge queue
#      the head is re-based onto main and re-gated before it may land.
#
# A red check is never re-gated into green by updating the branch. Red refuses first.
#
# EXIT CODES — the driver's convention:
#   0  a decision to ACT: `merge` or `update` alone on stdout
#   3  REFUSED, with a named reason on stderr — the PR stays open for a person
#   2  CANNOT RUN — a missing argument or a plan this cannot read; this decides nothing
#
# Usage:
#   merge-decision.sh --main-plan M --head-plan H --session S1 --changed-files F \
#                     --ci <conclusion> --reader <state> --behind <n> [--protected P]
#   (F lists the paths the pull request changes, one per line; it may be empty. P lists
#   extra protected path patterns, one per line, `#` comments allowed; it defaults to
#   .xal/protected-paths at this repository's root and is optional there.)
# Deps: bash, awk, diff, grep, and plan-read.sh beside this file. No network, no credential.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER="$HERE/plan-read.sh"

MAIN="" HEAD="" SID="" CI="" RD="" BEHIND="" CHANGED=""
PROTECTED="$HERE/../../.xal/protected-paths"
CI_SET=0 RD_SET=0
while [ $# -gt 0 ]; do
  case "$1" in
    (--main-plan) MAIN="${2:-}"; shift 2 ;;
    (--head-plan) HEAD="${2:-}"; shift 2 ;;
    (--session)   SID="${2:-}"; shift 2 ;;
    # --ci and --reader may legitimately be EMPTY (no verdict yet), so their presence is
    # tracked separately: an empty value is a fact to refuse on, an absent flag is a caller bug.
    (--ci)        CI="${2:-}"; CI_SET=1; shift 2 ;;
    (--reader)    RD="${2:-}"; RD_SET=1; shift 2 ;;
    (--behind)    BEHIND="${2:-}"; shift 2 ;;
    (--changed-files) CHANGED="${2:-}"; shift 2 ;;
    (--protected) PROTECTED="${2:-}"; shift 2 ;;
    (*) printf 'merge-decision: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

cannot_run() { printf 'merge-decision: CANNOT RUN: %s\n' "$1" >&2; exit 2; }

refuse() {
  printf 'REFUSED: %s\n' "$1" >&2
  printf '         The pull request stays open. A person reads it, or the cause is fixed and\n' >&2
  printf '         merge.yml is re-entered with a manual dispatch.\n' >&2
  printf '::error title=Merge refused::%s\n' "$1" >&2
  exit 3
}

[ -f "$READER" ] || cannot_run "plan-read.sh not found beside this script"
[ -n "$SID" ]    || cannot_run "--session is required"
[ -f "$MAIN" ]   || cannot_run "main's plan not found: ${MAIN:-<none given>}"
[ -f "$HEAD" ]   || cannot_run "the head's plan not found: ${HEAD:-<none given>}"
[ -f "$CHANGED" ] || cannot_run "--changed-files must name a file listing the changed paths (it may be empty)"
[ "$CI_SET" = 1 ] || cannot_run "--ci is required (pass an empty value for 'no verdict')"
[ "$RD_SET" = 1 ] || cannot_run "--reader is required (pass an empty value for 'no verdict')"
case "$BEHIND" in
  (''|*[!0-9]*) cannot_run "--behind must be a non-negative integer, got '${BEHIND}'" ;;
esac

# rd <plan> <reader args…> — into $REPLY, or CANNOT RUN from THIS shell. Not `x="$(…)"` with
# an exit inside: preflight.sh's header records what that cost.
rd() {
  local plan="$1"; shift
  REPLY="$(bash "$READER" --plan "$plan" "$@" 2>&1)" || cannot_run "plan-read.sh failed on $plan — $REPLY"
}

rd "$MAIN" --sessions; SESSIONS="$REPLY"
printf '%s\n' "$SESSIONS" | grep -qx -- "$SID" || refuse "main's plan declares no session '$SID'"

# --- 1. the head changed this session's status and evidence, and nothing else -----------
# Two conditions, because either alone is fooled. The diff shape proves only status/evidence
# lines moved; the per-session comparison proves they moved in THIS session's block and not
# in a neighbour's, which the diff alone cannot see.
changed="$(diff "$MAIN" "$HEAD" | grep -E '^[<>]' || true)"
stray="$(printf '%s\n' "$changed" | grep -vE '^[<>] - (status|evidence):' | grep -v '^$' || true)"
if [ -n "$stray" ]; then
  refuse "the head's plan changes more than $SID's status and evidence — first stray line: $(printf '%s' "$stray" | head -1 | cut -c1-120)"
fi
while IFS= read -r other; do
  [ -n "$other" ] && [ "$other" != "$SID" ] || continue
  rd "$MAIN" --session "$other" --field status; before="$REPLY"
  rd "$HEAD" --session "$other" --field status; after="$REPLY"
  [ "$before" = "$after" ] || \
    refuse "the head's plan changes $other's status ('${before:-<empty>}' → '${after:-<empty>}'), which is not the session this PR carries"
done <<< "$SESSIONS"

# --- 1b. the gate is not edited behind the plan's back ---------------------------------
# An artifact covers a path when it names it exactly, or names a directory (trailing `/`)
# the path sits under. Read from MAIN's plan: the head may not declare its own permission.
#
# The built-in set is the pipeline's own paths, identical in every service. The overlay's
# additions come from .xal/protected-paths — one shell pattern per line, matched the way the
# built-ins are — and that file sits under `.xal/`, so it is itself protected.
EXTRA=""
if [ -n "$PROTECTED" ] && [ -f "$PROTECTED" ]; then
  EXTRA="$(sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//' "$PROTECTED" | grep -v '^$' || true)"
fi
is_protected() {  # is_protected <path> — 0 when the path is a gate or pipeline path
  local path="$1" pat
  case "$path" in
    (scripts/*|gates/*|.github/*|.xal/*|docs/process/*) return 0 ;;
  esac
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    # shellcheck disable=SC2254
    case "$path" in ($pat) return 0 ;; esac
  done <<< "$EXTRA"
  return 1
}
rd "$MAIN" --session "$SID" --field artifact; ARTIFACTS="$REPLY"
while IFS= read -r path; do
  [ -n "$path" ] || continue
  is_protected "$path" || continue
  covered=""
  while IFS= read -r art; do
    [ -n "$art" ] || continue
    case "$art" in
      (*/) case "$path" in ("$art"*) covered=1 ;; esac ;;
      (*)  [ "$path" = "$art" ] && covered=1 ;;
    esac
  done <<< "$ARTIFACTS"
  [ -n "$covered" ] || \
    refuse "the pull request changes $path, a gate or pipeline path $SID does not declare as an artifact — CI judged this head with the head's own gate, so a person reads it"
done < "$CHANGED"

# --- 2. the driver judged this session passed ------------------------------------------
rd "$HEAD" --session "$SID" --field status; STATUS="$REPLY"
[ "$STATUS" = "passed" ] || \
  refuse "$SID's status on the head is '${STATUS:-<empty>}', not 'passed' — only a session the driver's own gate passed may land"

# --- 3. the autonomy ruling admits this session's risk class ---------------------------
rd "$MAIN" --fm autonomy_level; AUTONOMY="$REPLY"
rd "$MAIN" --session "$SID" --field risk_class; RISK="$REPLY"
case "$AUTONOMY" in
  (code-only)                     admits="code-only" ;;
  (code-and-tests-pre-deployment) admits="code-only data-migration secrets" ;;
  (unset)
    refuse "autonomy_level is 'unset' — no autonomy ruling exists for this plan, so nothing in it merges without a person (ADR-0009 revisit trigger 3)" ;;
  (*)
    refuse "autonomy_level '${AUTONOMY:-<empty>}' is not one of code-only | code-and-tests-pre-deployment" ;;
esac
case " $admits " in
  (*" $RISK "*) ;;
  (*) refuse "$SID is risk_class '${RISK:-<empty>}', which autonomy_level '$AUTONOMY' does not admit ($admits) — this one is the owner's to merge" ;;
esac

# --- 4. CI judged the head, and judged it green ----------------------------------------
case "$CI" in
  (success) ;;
  ('')      refuse "CI has no gate verdict on the head — an unjudged head is not a green one" ;;
  (*)       refuse "CI's gate check on the head concluded '$CI' — a red pull request never merges" ;;
esac

# --- 5. the reader read the head, and found nothing ------------------------------------
case "$RD" in
  (success) ;;
  ('')      refuse "the reader has no verdict on the head — a merge must not race the reviewer (ADR-0009 decision 10)" ;;
  (pending) refuse "the reader is still reading the head — a merge must not race the reviewer (ADR-0009 decision 10)" ;;
  (*)       refuse "the reader's verdict on the head is '$RD' — its findings are the owner's to read before this lands" ;;
esac

# --- 6. the head is current with main, or it is re-gated first -------------------------
if [ "$BEHIND" -gt 0 ]; then
  printf 'update\n'
  printf '  %s is %s commit(s) behind main — re-base and re-gate before it may land\n' "$SID" "$BEHIND" >&2
  exit 0
fi

printf 'merge\n'
printf '  %s may land: passed, %s within %s, CI green, reader clean, current with main\n' \
  "$SID" "$RISK" "$AUTONOMY" >&2
exit 0
