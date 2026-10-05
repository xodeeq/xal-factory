#!/usr/bin/env bash
#
# spend.sh — the per-session spend ledger, and the two ceilings read from it.
#
# WHERE THE FILE LIVES, AND WHY THIS SCRIPT DOES NOT KNOW. Pipeline R2 ruled the collection
# location: a per-session JSONL in the ops repo, the `costs.jsonl` pattern. This script takes
# `--file` and operates on a LOCAL path, so the workflow owns fetching and pushing and this
# owns arithmetic. That split is what makes every rule below provable by a committed fixture
# with no network and no credential — the component that decides whether money may be spent
# must be runnable by anyone, offline.
#
# AWK, NOT jq OR python3, AND THAT IS A DELIBERATE CONSTRAINT. This script is exercised by
# `gates/driver.test.sh`, the driver-fixtures gate of `scripts/check.sh`. Anything it needs
# becomes an INPUT to that gate, and every input must be declared in `.xal/gate-inputs` and
# supplied by every caller (ADR-0004 in the factory). The gate chain today needs neither jq nor
# python3 — `fetch-spec.sh` uses `gh api --jq`, which is gh's own, not the binary. Reaching
# for either here would add an undeclared input to the gate chain, which is precisely the
# 2026-08-12 outage shape this estate keeps re-learning.
#
# A MALFORMED LINE IS A REFUSAL, NEVER A SKIP. The parser below is narrow on purpose: it
# reads a flat schema this script itself writes. If a line carries a plan_id and a session
# but no readable cost, the file is not something this script may sum — and a ceiling that
# silently undercounts is worse than no ceiling, because it reports green while the number
# it is defending drifts. So an unreadable record exits 2 (cannot run) and names the line.
#
# WHAT THE CEILINGS CAN AND CANNOT DO, stated because the honest limit matters more than the
# feature. Cost is per token, so no check here can stop a run that is already going; this is
# the same limitation `timeout-minutes` has and it was argued out on 2026-09-19. What these
# ceilings do is refuse to START the next thing: `--check` is called BEFORE the agent step,
# so a plan that has spent its budget cannot begin another session, and a session that has
# spent its own bound cannot begin another attempt. That is the bound that was missing when
# a failed attempt cost $20.87 inside every limit that existed.
#
# MODES
#   --append        add one record; needs --plan-id --session --attempt --status --cost --run-url
#                   and takes an optional --kind (`reader` for the reader's run, below)
#   --plan-total    sum cost_usd for a plan
#   --session-total sum cost_usd for one session of a plan
#   --attempts      count records for one session of a plan (this is the retry counter)
#   --check         refuse if starting another run would begin past either ceiling
#
# EXIT CODES — the driver's convention:
#   0  fine; any requested number is on stdout, alone
#   3  REFUSED, named — a ceiling is already reached
#   2  CANNOT RUN — bad arguments, missing file, or a record this script cannot read

set -uo pipefail

MODE="" FILE="" PLAN_ID="" SESSION="" ATTEMPT="" STATUS="" COST="" TURNS="" RUN_URL="" KIND=""
PLAN_CEILING="" SESSION_CEILING=""

while [ $# -gt 0 ]; do
  case "$1" in
    (--file)             FILE="${2:-}"; shift 2 ;;
    (--append)           MODE="append"; shift ;;
    (--plan-total)       MODE="plan-total"; shift ;;
    (--session-total)    MODE="session-total"; shift ;;
    (--attempts)         MODE="attempts"; shift ;;
    (--check)            MODE="check"; shift ;;
    (--plan-id)          PLAN_ID="${2:-}"; shift 2 ;;
    (--session)          SESSION="${2:-}"; shift 2 ;;
    (--attempt)          ATTEMPT="${2:-}"; shift 2 ;;
    (--status)           STATUS="${2:-}"; shift 2 ;;
    (--cost)             COST="${2:-}"; shift 2 ;;
    (--turns)            TURNS="${2:-}"; shift 2 ;;
    (--run-url)          RUN_URL="${2:-}"; shift 2 ;;
    (--kind)             KIND="${2:-}"; shift 2 ;;
    (--plan-ceiling)     PLAN_CEILING="${2:-}"; shift 2 ;;
    (--session-ceiling)  SESSION_CEILING="${2:-}"; shift 2 ;;
    (*) printf 'spend: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$MODE" ] || { printf 'spend: one mode is required\n' >&2; exit 2; }
[ -n "$FILE" ] || { printf 'spend: --file is required\n' >&2; exit 2; }

# --- append ------------------------------------------------------------------------------
# One line, flat, fixed key order. Written by this script and read by the parser below, which
# is why the order is fixed: a machine-written file with a machine-written reader is allowed
# to be narrow, and saying so here is what stops someone widening one without the other.
if [ "$MODE" = "append" ]; then
  for req in PLAN_ID SESSION ATTEMPT STATUS COST; do
    eval "v=\${$req}"
    [ -n "$v" ] || { printf 'spend: --append needs --%s\n' "$(printf '%s' "$req" | tr 'A-Z_' 'a-z-')" >&2; exit 2; }
  done
  case "$COST" in
    (''|*[!0-9.]*) printf 'spend: --cost must be a number, got %s\n' "$COST" >&2; exit 2 ;;
  esac
  case "$KIND" in
    (''|reader) ;;
    (*) printf 'spend: --kind must be `reader` or absent, got %s\n' "$KIND" >&2; exit 2 ;;
  esac
  mkdir -p "$(dirname "$FILE")" 2>/dev/null
  # `kind` is written LAST and only when given, so every record the driver wrote before
  # pipeline S7 is still exactly the shape this parser reads.
  printf '{"ts":"%s","plan_id":"%s","session":"%s","attempt":%s,"status":"%s","cost_usd":%s,"turns":%s,"run_url":"%s"%s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PLAN_ID" "$SESSION" "$ATTEMPT" "$STATUS" "$COST" "${TURNS:-0}" "$RUN_URL" \
    "${KIND:+,\"kind\":\"$KIND\"}" \
    >> "$FILE" || { printf 'spend: could not append to %s\n' "$FILE" >&2; exit 2; }
  printf '  recorded %s %s attempt %s: $%s (%s)\n' "$PLAN_ID" "$SESSION" "$ATTEMPT" "$COST" "$STATUS" >&2
  exit 0
fi

# An absent ledger is not an error for a READ: a plan that has spent nothing has spent
# nothing, and the first session of a new plan must not be refused because no file exists
# yet. It is distinguished from an unreadable one, which exits 2 below.
if [ ! -f "$FILE" ]; then
  case "$MODE" in
    (plan-total|session-total) printf '0\n'; exit 0 ;;
    (attempts)                 printf '0\n'; exit 0 ;;
    (check)                    printf '  no ledger at %s yet — nothing has been spent\n' "$FILE" >&2; exit 0 ;;
  esac
fi

[ -n "$PLAN_ID" ] || { printf 'spend: --plan-id is required for %s\n' "$MODE" >&2; exit 2; }

# --- the parser --------------------------------------------------------------------------
# Narrow by design (see the header). `want_session` empty means "every session of this plan".
# An unreadable record is fatal rather than skipped.
sum_and_count() {
  local want_session="$1"
  awk -v plan="$PLAN_ID" -v want="$want_session" '
    function sval(line, key,   s, re) {
      re = "\"" key "\"[ ]*:[ ]*\"[^\"]*\""
      if (match(line, re)) {
        s = substr(line, RSTART, RLENGTH)
        sub("^\"" key "\"[ ]*:[ ]*\"", "", s)
        sub("\"$", "", s)
        return s
      }
      return ""
    }
    function nval(line, key,   s, re) {
      re = "\"" key "\"[ ]*:[ ]*[0-9]+([.][0-9]+)?"
      if (match(line, re)) {
        s = substr(line, RSTART, RLENGTH)
        sub("^\"" key "\"[ ]*:[ ]*", "", s)
        return s + 0
      }
      return "NaN"
    }
    {
      if ($0 ~ /^[ \t]*$/) next
      p = sval($0, "plan_id")
      s = sval($0, "session")
      if (p == "" || s == "") {
        printf("spend: line %d has no readable plan_id/session: %s\n", NR, $0) > "/dev/stderr"
        bad = 1; exit
      }
      if (p != plan) next
      if (want != "" && s != want) next
      c = nval($0, "cost_usd")
      if (c == "NaN") {
        printf("spend: line %d has no readable cost_usd: %s\n", NR, $0) > "/dev/stderr"
        bad = 1; exit
      }
      total += c
      # A READER RECORD IS SPEND, NOT AN ATTEMPT. Since pipeline S7 each reader run on a
      # session PR is recorded against that session, so both ceilings see what reading it
      # cost. But attempts is the retry counter, and a reader run is not a try at building
      # the session: counting it would make retry_cap fire one attempt early for every PR
      # the reader read. (No apostrophes in this block: it sits inside a single-quoted awk
      # program, and one ended the program here on the first draft.)
      if (sval($0, "kind") != "reader") n += 1
    }
    END {
      if (bad) exit 2
      printf("%.4f %d\n", total + 0, n + 0)
    }
  ' "$FILE"
}

read_totals() {
  local out
  out="$(sum_and_count "$1")" || return 2
  [ -n "$out" ] || return 2
  printf '%s\n' "$out"
}

case "$MODE" in
  (plan-total)
    out="$(read_totals "")" || { printf 'spend: the ledger could not be read\n' >&2; exit 2; }
    printf '%s\n' "${out%% *}"; exit 0 ;;
  (session-total)
    [ -n "$SESSION" ] || { printf 'spend: --session is required for --session-total\n' >&2; exit 2; }
    out="$(read_totals "$SESSION")" || { printf 'spend: the ledger could not be read\n' >&2; exit 2; }
    printf '%s\n' "${out%% *}"; exit 0 ;;
  (attempts)
    [ -n "$SESSION" ] || { printf 'spend: --session is required for --attempts\n' >&2; exit 2; }
    out="$(read_totals "$SESSION")" || { printf 'spend: the ledger could not be read\n' >&2; exit 2; }
    printf '%s\n' "${out##* }"; exit 0 ;;
esac

# --- check -------------------------------------------------------------------------------
[ "$MODE" = "check" ] || { printf 'spend: unreachable mode %s\n' "$MODE" >&2; exit 2; }
[ -n "$SESSION" ] || { printf 'spend: --session is required for --check\n' >&2; exit 2; }

plan_out="$(read_totals "")"      || { printf 'spend: the ledger could not be read\n' >&2; exit 2; }
sess_out="$(read_totals "$SESSION")" || { printf 'spend: the ledger could not be read\n' >&2; exit 2; }
plan_total="${plan_out%% *}"
sess_total="${sess_out%% *}"
attempts="${sess_out##* }"

over() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 >= b + 0) }'; }

# A ceiling that is absent or `unset` is declared intent, not a number, and enforcing a
# fabricated one is worse than enforcing none (ADR-0008). Say which bound is inert rather
# than printing a green that means "not checked".
if [ -n "$PLAN_CEILING" ] && [ "$PLAN_CEILING" != "unset" ]; then
  if over "$plan_total" "$PLAN_CEILING"; then
    printf 'REFUSED: this plan has spent $%s against spend_ceiling_usd %s.\n' "$plan_total" "$PLAN_CEILING" >&2
    printf '         The ceiling cannot stop a run already going — cost is per token — so it\n' >&2
    printf '         stops the next one. Raise it deliberately or stop the plan.\n' >&2
    printf '::error title=Spend ceiling::plan total $%s >= %s\n' "$plan_total" "$PLAN_CEILING" >&2
    exit 3
  fi
else
  printf '  plan ceiling: not enforced (unset)\n' >&2
fi

if [ -n "$SESSION_CEILING" ] && [ "$SESSION_CEILING" != "unset" ]; then
  if over "$sess_total" "$SESSION_CEILING"; then
    printf 'REFUSED: %s has spent $%s over %s attempt(s) against session_ceiling_usd %s.\n' \
      "$SESSION" "$sess_total" "$attempts" "$SESSION_CEILING" >&2
    printf '         This is the bound that was missing when a failed attempt cost $20.87\n' >&2
    printf '         inside every limit that existed. Escalate rather than re-dispatching.\n' >&2
    printf '::error title=Spend ceiling::%s total $%s >= %s\n' "$SESSION" "$sess_total" "$SESSION_CEILING" >&2
    exit 3
  fi
else
  printf '  session ceiling: not enforced (unset)\n' >&2
fi

printf '  within both ceilings: plan $%s/%s, %s $%s/%s over %s attempt(s)\n' \
  "$plan_total" "${PLAN_CEILING:-unset}" "$SESSION" "$sess_total" "${SESSION_CEILING:-unset}" "$attempts" >&2
exit 0
