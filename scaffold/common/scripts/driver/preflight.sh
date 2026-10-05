#!/usr/bin/env bash
#
# preflight.sh — decide whether the driver may run one session, and REFUSE loudly if not.
#
# THE CONTRACT THAT MAKES THIS USEFUL ---------------------------------------------------
#
# Three exit codes, and they mean three different things. This matters more than it looks:
# the brief that commissioned this asked, in as many words, whether a refusal is
# distinguishable from a crash. Under `set -e` a crashing bash script exits 1, 2, or 127 —
# so a refusal MUST NOT use any of those, or "the driver declined to run an unapproved
# plan" and "the driver fell over" are the same signal to whatever reads the exit code.
#
#   0  may run      — every condition below is satisfied; the driver proceeds
#   3  REFUSED      — a deliberate, named decision. Prints `REFUSED: <reason>` and a
#                     ::error:: annotation. NOTHING is committed, no branch is created,
#                     no PR is opened. Fail closed.
#   2  CANNOT RUN   — the plan is missing or unparseable. Distinct from a refusal for the
#                     gate-7 precedent's reason: a check that could not run has not passed,
#                     and it has not decided anything either.
#
# WHAT IT REFUSES, AND WHY EACH ONE -----------------------------------------------------
#
#   1. plan status is not `approved`      ADR-0005 in the factory decision 8, execution half.
#                                         Roadmap §4.4: only an approved plan may be run.
#   2. approval names no approver or date ADR-0008 rule 11's execution half. Rule 11 runs
#                                         in ANOTHER REPO's CI, over a fixture set, and has
#                                         never run against this plan in this repo. The
#                                         driver does not trust a rule it cannot see fire.
#   3. autonomy_level not a ruled value  Asked for by the S5 brief; `unset` refused since S7.
#   4. no such session in the plan        A typo'd id must not silently run nothing.
#   5. human_only_actions_before non-empty Roadmap §7.2: things the owner must do FIRST.
#   6. a depends_on session is not passed  §4.5's ordering, enforced rather than assumed.
#   7. the session holds a SETTLED outcome  `passed` (re-running overwrites real evidence),
#                                         `escalated` (a person owns it) or `running`
#                                         (another dispatch holds it). NOT `failed` or
#                                         `ungated` — both are invitations to run again,
#                                         which is what every session's retry_cap is for.
#
# WHAT IT DELIBERATELY DOES NOT CHECK ----------------------------------------------------
#
# The spec digest. Rule 1 of the critic requires the plan to cite its spec by a sha256 the
# ledger can recompute — and recomputing it means reading the ops repo, which may be private.
# That is an input, and a credential, in the one component that must not have one (ADR-0005
# §3: "a check that catches missing inputs must not be able to have one"). The critic
# reconciles the digest at authoring time. This is a named residual, not an oversight.
#
# Usage:  preflight.sh --plan docs/plan/plan.md --session S1
# Deps:   bash, awk, sed, grep, and scripts/driver/plan-read.sh. No network, no credential.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER="$HERE/plan-read.sh"

PLAN="docs/plan/plan.md"
SID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --plan)    PLAN="$2"; shift 2 ;;
    --session) SID="$2";  shift 2 ;;
    *) printf 'preflight.sh: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then RED=$'\033[31m'; GREEN=$'\033[32m'; RST=$'\033[0m'
else RED=""; GREEN=""; RST=""; fi

# A refusal is one function so every refusal looks identical to whatever greps the log, and
# so no future edit can add a quiet one.
refuse() {
  printf '%sREFUSED: %s%s\n' "$RED" "$1" "$RST"
  printf '::error title=Driver refused::%s\n' "$1"
  printf '  Nothing was committed, no branch was created and no pull request was opened.\n'
  exit 3
}

cannot_run() {
  printf '%sCANNOT RUN: %s%s\n' "$RED" "$1" "$RST" >&2
  exit 2
}

[ -x "$READER" ] || cannot_run "plan-read.sh is missing at $READER"
[ -n "$SID" ]    || cannot_run "--session is required"
[ -f "$PLAN" ]   || cannot_run "plan not found: $PLAN"

# rd <reader args…> — read the plan into $REPLY, or exit 2 from THIS shell.
#
# READ THIS BEFORE "SIMPLIFYING" IT BACK INTO `x="$(read_or_die …)"`. That is what this
# was, and the fixture suite caught it on its first run: `exit` inside a command
# substitution exits the SUBSHELL. The parent carried on with an empty value and refused
# for a reason that was not true — an unparseable plan came back as `REFUSED: plan status
# is '<empty>'` (exit 3) instead of CANNOT RUN (exit 2), which is precisely the
# refusal-versus-crash confusion the three-code contract at the top of this file exists to
# make impossible. The assignment below happens in this shell, so `|| cannot_run` does too.
rd() {
  REPLY="$("$READER" --plan "$PLAN" "$@" 2>&1)" || cannot_run "plan-read.sh failed — $REPLY"
}

# --- 1 + 2: the plan is approved, and the approval names a person and a date -----------
rd --fm status;      STATUS="$REPLY"
[ "$STATUS" = "approved" ] || \
  refuse "plan status is '${STATUS:-<empty>}', not 'approved' — roadmap §4.4 permits only an approved plan to be executed"

rd --fm approved_by; APPROVED_BY="$REPLY"
rd --fm approved_on; APPROVED_ON="$REPLY"
if [ -z "$APPROVED_BY" ] || [ -z "$APPROVED_ON" ]; then
  refuse "plan claims 'approved' but names approved_by='${APPROVED_BY:-<empty>}' and approved_on='${APPROVED_ON:-<empty>}' — an approval with no person and no date is a word, not an approval"
fi

# --- 3: autonomy_level is a ruled value --------------------------------------------------
# `unset` WAS accepted here until pipeline S7, deliberately: a driver that never merged could
# run one session of a plan whose autonomy ruling was still pending, because running is not
# merging. Since S7 a finished session may land with no person present (merge.yml), so the
# driver no longer starts a session whose plan has no ruling about what may land — ADR-0009
# revisit trigger 3, discharged. merge-decision.sh refuses `unset` too; this refusal is the
# earlier and cheaper one, before any money is spent on a session nothing could merge.
rd --fm autonomy_level; AUTONOMY="$REPLY"
case "$AUTONOMY" in
  code-only|code-and-tests-pre-deployment) ;;
  unset) refuse "autonomy_level is 'unset' — since pipeline S7 a plan must carry an autonomy ruling before any session runs, because a driven session may now land without a person" ;;
  *) refuse "autonomy_level '${AUTONOMY:-<empty>}' is not one of code-only | code-and-tests-pre-deployment" ;;
esac

# --- 4: the session exists -------------------------------------------------------------
rd --sessions; ALL="$REPLY"
printf '%s\n' "$ALL" | grep -qx -- "$SID" || \
  refuse "no session '$SID' in $PLAN — it declares: $(printf '%s' "$ALL" | tr '\n' ' ')"

# --- 5: nothing is owed by a human before this session ----------------------------------
rd --session "$SID" --field human_only_actions_before; HOA="$REPLY"
case "$HOA" in
  ""|"[]") ;;
  *) refuse "$SID declares human_only_actions_before: $HOA — a person must do that first" ;;
esac

# --- 6: every dependency has passed ------------------------------------------------------
rd --session "$SID" --field depends_on; DEPS="$REPLY"
for dep in $(printf '%s' "$DEPS" | grep -oE 'S[0-9]+' || true); do
  printf '%s\n' "$ALL" | grep -qx -- "$dep" || \
    refuse "$SID depends on '$dep', which $PLAN does not declare"
  rd --session "$dep" --field status; dep_status="$REPLY"
  [ "$dep_status" = "passed" ] || \
    refuse "$SID depends on $dep, whose status is '${dep_status:-<empty>}' — not 'passed'"
done

# --- 7: this session does not already hold a settled outcome -----------------------------
#
# NOT "has not already run". The original rule refused ANY non-empty status, which reads as
# caution and is a defect two ways over. The plan declares `retry_cap: 2` and
# `on_exhaustion: escalate` for every session — and a retry is a re-run, so preflight would
# have refused the first retry pipeline S6 ever attempted, making a field the plan carries on
# all fifteen sessions unreachable. It also strands a session whose gate produced no verdict
# at all: run 35440579899 was cancelled mid-gate, and under the old rule the only way back
# was a person hand-editing the plan.
#
# What must be protected is a SETTLED outcome, and there are three. `passed` is real evidence
# and re-running it would overwrite it. `escalated` means a human owns the decision and a
# machine must not quietly resume. `running` means something else already holds this session.
# `failed` and `ungated` are the opposite: both are invitations to run again, which is what
# retry_cap exists for, and neither satisfies a `depends_on`, so nothing downstream can move
# on them either way.
rd --session "$SID" --field status; OWN="$REPLY"
case "$OWN" in
  passed)     refuse "$SID already carries status 'passed' — re-running it would overwrite the evidence of the run that produced it" ;;
  escalated)  refuse "$SID is 'escalated' — a person owns this decision, and a driver must not resume it unasked" ;;
  running)    refuse "$SID is already 'running' — another dispatch holds it" ;;
esac

# --- cleared -----------------------------------------------------------------------------
rd --session "$SID" --field risk_class; RISK="$REPLY"
rd --session "$SID" --field gate.command; GATE="$REPLY"

printf '%s✔ %s may run%s\n' "$GREEN" "$SID" "$RST"
rd --fm plan_id
printf '  plan          %s (approved_by %s on %s)\n' "$REPLY" "$APPROVED_BY" "$APPROVED_ON"
printf '  autonomy      %s  (what may land unattended is merge-decision.sh'"'"'s to decide)\n' "$AUTONOMY"
printf '  risk_class    %s\n' "$RISK"
printf '  depends_on    %s — all passed\n' "${DEPS:-[]}"
printf '  gate          %s\n' "$GATE"
printf '  NOT checked   the spec digest (needs a read of the ops repo; see the header)\n'
exit 0
