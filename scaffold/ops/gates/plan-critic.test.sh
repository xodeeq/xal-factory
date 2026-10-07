#!/usr/bin/env bash
#
# gates/plan-critic.test.sh — proof that scripts/plan-critic-check.sh has teeth, and that
# it says which tooth.
#
# CLAUDE.md, standing rules: "Every new gate ships with committed failing fixtures. A gate
# that has never been seen to fail has not been tested — a rule matching nothing and a rule
# finding nothing emit byte-identical green, and `return 0` passes just as convincingly as
# real logic."
#
# So, per fixture, three assertions rather than one:
#   (a) the gate fails,
#   (b) the rule that fired is the intended one, and
#   (c) NO OTHER rule fired.
#
# (c) is the one that does the work. A rule that fires on everything is exactly as broken as
# one that fires on nothing, and both look healthy from an exit code. Writing (c) is what
# forced rule 9 to be fed only edges whose endpoints are declared sessions: without that
# guard a single typo'd dependency trips rules 8 AND 9, and a fixture that fires two rules
# proves neither.
#
# THE FOURTH ASSERTION, WHICH IS ABOUT THE FIXTURES RATHER THAN THE GATE -----------
#
# Every rule fixture must be the CLEAN one broken in exactly one way, and this suite proves
# it by diffing rather than by trusting the filenames. A fixture hand-written from scratch
# drifts from clean over time until it differs in several ways at once, and then it no
# longer isolates the rule it is named for — it just happens to trip it. The diff bound is
# what keeps "one fixture per rule" true a year from now.
#
#
# RULE 11'S FIXTURE IS THE ONE WRITTEN FROM AN OBSERVED FAILURE, NOT AN IMAGINED ONE. Every
# other fixture here was written alongside its rule. This one came from S4: the plan's PR was
# merged, §4.4 says a merge flips `status` to `approved`, nothing performs that sentence, and
# the field was then flipped by hand — which closed one hole and opened a worse one. A plan
# claiming `status: approved` with no approver and no date exited 0 on this gate, and it was
# proven by running it that way before the rule existed.
# AND THE FIFTH: CANNOT-RUN IS NOT CLEAN ------------------------------------------
#
# `no-plan` and `no-sessions` must exit 2, distinctly. The failure this estate has actually
# been bitten by is a gate that exits 0 having checked nothing: `.xal/check-gate-inputs.sh`
# sat vendored and uninvoked for 27 days while being current and diff-clean, and every
# signal a reader checks said it was covered. "The planner has not run" and "the plan is
# clean" must never emit the same verdict.
#
# Usage:  gates/plan-critic.test.sh
# Exit:   0 every scenario behaved as specified · 1 at least one did not
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GATE="scripts/plan-critic-check.sh"
FIX="gates/fixtures/plan-critic"

if [ -t 1 ]; then BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; RST=$'\033[0m'
else BOLD=""; RED=""; GREEN=""; RST=""; fi

[ -f "$GATE" ] || { printf '%s%s not found — there is no gate to prove%s\n' "$RED" "$GATE" "$RST"; exit 2; }
[ -d "$FIX" ]  || { printf '%sno fixtures at %s — refusing to report green over an empty suite%s\n' "$RED" "$FIX" "$RST"; exit 2; }

pass=0; fail=0
ok()  { printf '%s  ✔%s %s\n' "$GREEN" "$RST" "$1"; pass=$((pass + 1)); }
bad() { printf '%s  ✗%s %s\n' "$RED" "$RST" "$1"; fail=$((fail + 1)); }

# run <fixture> <want-exit> <want-pattern> <description>
run() {
  local fixture="$1" want_exit="$2" want_pat="$3" desc="$4" out rc problem=""
  [ -d "$FIX/$fixture" ] || { bad "$(printf '%-30s fixture directory does not exist' "$fixture")"; return; }
  # GOTCHA (inherited from gates/check.test.sh): never pipe a deliberately-failing command
  # into the condition. `set -o pipefail` is on, so `bash gate | grep -q` returns the GATE's
  # status, not grep's. Capture first, match second.
  out="$(bash "$ROOT/$GATE" --root "$ROOT/$FIX/$fixture" 2>&1)"; rc=$?
  [ "$rc" = "$want_exit" ] || problem="exit $rc, wanted $want_exit"
  if [ -n "$want_pat" ] && ! printf '%s' "$out" | grep -qE -- "$want_pat"; then
    problem="${problem:+$problem; }output did not match /$want_pat/"
  fi
  if [ -z "$problem" ]; then
    printf '%s  ✔%s %-30s exit %s  %s\n' "$GREEN" "$RST" "$fixture" "$rc" "$desc"
    pass=$((pass + 1))
  else
    printf '%s  ✗%s %-30s %s  (%s)\n' "$RED" "$RST" "$fixture" "$problem" "$desc"
    printf '%s\n' "$out" | sed 's/^/      | /'
    fail=$((fail + 1))
  fi
}

printf '\n%s━━ it can say yes%s\n\n' "$BOLD" "$RST"
run clean 0 'plan-critic clean' 'a well-formed plan must PASS (guards against a gate that always fails)'

printf '\n%s━━ a proven failure case per rule, naming the rule%s\n\n' "$BOLD" "$RST"
run rule-1-missing-spec-digest  1 'RULE 1'  'the spec citation loses its ledger digest'
run rule-2-no-gate-command      1 'RULE 2'  'a session with no machine-decidable done-criterion'
run rule-3-no-must-not          1 'RULE 3'  'a done-criterion with no boundary conditions beside it'
run rule-4-prose-artifact       1 'RULE 4'  'an artifact written as prose cannot be tested for existence'
run rule-5-no-scope-out         1 'RULE 5'  'the boundary that says what the session must leave alone'
run rule-6-continues-past-cap   1 'RULE 6'  'on_exhaustion continues instead of escalating — no stop condition'
run rule-7-total-mismatch       1 'RULE 7'  'sessions_total disagrees with the number of session blocks'
run rule-8-dangling-depends     1 'RULE 8'  'a dependency on a session the plan does not declare'
run rule-9-cycle                1 'RULE 9'  'a dependency cycle — no topological order exists'
run rule-10-no-risk-class       1 'RULE 10' 'no risk_class, which the autonomy ratchet keys on'
run rule-11-approved-by-nobody  1 'RULE 11' 'status: approved with no approver and no date — a word, not a decision'

printf '\n%s━━ cannot-run is distinguishable from clean%s\n\n' "$BOLD" "$RST"
run no-plan     2 'refusing to report green over a plan that does not exist' 'the planner has not run yet'
run no-sessions 2 'refusing to report green over a plan with no sessions'    'frontmatter only, not one session block'

# ── discrimination ────────────────────────────────────────────────────────────────
# The rule number is taken from the fixture NAME, so a fixture that drifts from its name
# fails here rather than passing quietly.
printf '\n%s━━ discrimination: each fixture trips exactly one rule, and it is its own%s\n\n' "$BOLD" "$RST"
for d in "$FIX"/rule-*; do
  name="$(basename "$d")"
  want="RULE $(printf '%s' "$name" | sed -E 's/^rule-([0-9]+)-.*/\1/')"
  out="$(bash "$ROOT/$GATE" --root "$ROOT/$d" 2>&1)"
  fired="$(printf '%s' "$out" | grep -oE 'RULE [0-9]+' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [ "$fired" = "$want" ]; then
    ok "$(printf '%-30s fired: %s' "$name" "$fired")"
  else
    bad "$(printf '%-30s fired: [%s], wanted exactly [%s]' "$name" "$fired" "$want")"
  fi
done

# ── every rule fixture is CLEAN, broken in exactly one way ────────────────────────
# Proven by diff, not by trusting the filename or the author. The bound is 4 changed lines:
# a one-line deletion is 1, a one-line substitution is 2, and the slack covers a value that
# legitimately spans a line boundary. Anything larger is a fixture that has drifted into
# testing several things at once, at which point it isolates nothing.
printf '\n%s━━ each rule fixture is the clean one, broken once%s\n\n' "$BOLD" "$RST"
CLEAN_PLAN="$FIX/clean/docs/plan/plan.md"
for d in "$FIX"/rule-*; do
  name="$(basename "$d")"
  p="$d/docs/plan/plan.md"
  if [ ! -f "$p" ]; then bad "$(printf '%-30s has no docs/plan/plan.md' "$name")"; continue; fi
  n="$(diff "$CLEAN_PLAN" "$p" | grep -c '^[<>]')"
  if [ "$n" -eq 0 ]; then
    bad "$(printf '%-30s is IDENTICAL to clean — it proves nothing' "$name")"
  elif [ "$n" -le 4 ]; then
    ok "$(printf '%-30s differs from clean in %s line(s)' "$name" "$n")"
  else
    bad "$(printf '%-30s differs from clean in %s lines — it no longer isolates one rule' "$name" "$n")"
  fi
done

printf '\n%s──────── %s passed · %s failed ────────%s\n' "$BOLD" "$pass" "$fail" "$RST"
if [ "$fail" -ne 0 ]; then
  printf '%s::error::plan-critic-check did not behave as its fixtures specify%s\n' "$RED" "$RST"
  exit 1
fi
printf '%splan-critic-check is proven able to fail, per rule, to discriminate between rules, and to pass.%s\n' \
  "$GREEN" "$RST"
exit 0
