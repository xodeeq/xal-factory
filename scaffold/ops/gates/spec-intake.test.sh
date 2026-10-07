#!/usr/bin/env bash
#
# gates/spec-intake.test.sh — proof that scripts/spec-intake-check.sh has teeth.
#
# CLAUDE.md, standing rules: "Every new gate ships with committed failing fixtures. A gate
# that has never been seen to fail has not been tested — a rule matching nothing and a rule
# finding nothing emit byte-identical green, and `return 0` passes just as convincingly as
# real logic. This estate has been bitten by that four times."
#
# So each fixture under gates/fixtures/spec-intake/ is the CLEAN one, broken in exactly one
# way, and three things are asserted per fixture, not one:
#   (a) the gate fails,
#   (b) the rule that fired is the intended one, and
#   (c) no OTHER rule fired.
#
# (b) and (c) are the point. A gate can fail for the wrong reason and look right from its
# exit code alone. This suite is also why rules 2-4 skip an absent key and why rule 6 keys
# on the section NUMBER: writing the discrimination assertions is what surfaced that a
# missing `date` would otherwise trip rules 1 AND 3, and a retitled section both 6 and 8.
#
# Rule 10 (2026-09-24) binds admissions by the ledger's date, so it needs its own clean
# fixture: `clean` is admitted 2026-09-14 and never reaches rule 10, which means it cannot
# prove rule 10 can say yes. `clean-with-flags` is admitted 2026-09-24 with a full flag
# table, and `rule-10-flag-without-default` is that fixture with one Default cell emptied.
#
# The clean fixture matters as much as the failing ones — a gate that flagged every spec
# would be deleted within a week — and so do the two exit-2 fixtures: "cannot run" must be
# distinguishable from "clean", or the intake layer reports green over a tree it never read.
#
# Usage:  gates/spec-intake.test.sh
# Exit:   0 every scenario behaved as specified · 1 at least one did not
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GATE="scripts/spec-intake-check.sh"
FIX="gates/fixtures/spec-intake"

if [ -t 1 ]; then BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; RST=$'\033[0m'
else BOLD=""; RED=""; GREEN=""; RST=""; fi

[ -f "$GATE" ] || { printf '%s%s not found%s\n' "$RED" "$GATE" "$RST"; exit 2; }

pass=0; fail=0
ok()  { printf '%s  ✔%s %s\n' "$GREEN" "$RST" "$1"; pass=$((pass + 1)); }
bad() { printf '%s  ✗%s %s\n' "$RED" "$RST" "$1"; fail=$((fail + 1)); }

# run <fixture> <want-exit> <want-pattern> <description>
run() {
  local fixture="$1" want_exit="$2" want_pat="$3" desc="$4" out rc
  out="$(bash "$ROOT/$GATE" --root "$ROOT/$FIX/$fixture" 2>&1)"; rc=$?
  local problem=""
  [ "$rc" = "$want_exit" ] || problem="exit $rc, wanted $want_exit"
  if [ -n "$want_pat" ] && ! printf '%s' "$out" | grep -qE -- "$want_pat"; then
    problem="${problem:+$problem; }output did not match /$want_pat/"
  fi
  if [ -z "$problem" ]; then
    printf '%s  ✔%s %-32s exit %s  %s\n' "$GREEN" "$RST" "$fixture" "$rc" "$desc"
    pass=$((pass + 1))
  else
    printf '%s  ✗%s %-32s %s  (%s)\n' "$RED" "$RST" "$fixture" "$problem" "$desc"
    printf '%s\n' "$out" | sed 's/^/      | /'
    fail=$((fail + 1))
  fi
}

printf '\n%s━━ spec-intake: a proven failure case per rule%s\n\n' "$BOLD" "$RST"

run clean                        0 'spec-intake clean' 'a valid admitted spec must PASS (guards against always-fails)'
run clean-with-flags             0 'spec-intake clean' 'a spec admitted on/after 2026-09-24 with a full flag table must PASS (rule 10 can say yes)'
run rule-1-missing-key           1 'RULE 1'  'a required frontmatter key is absent'
run rule-2-bad-version           1 'RULE 2'  'spec_version is not semver'
run rule-3-bad-date              1 'RULE 3'  'date is not an ISO 8601 calendar date'
run rule-4-bad-status            1 'RULE 4'  'status opens with no state token'
run rule-5-path-mismatch         1 'RULE 5'  'the directory and the frontmatter name different services'
run rule-6-missing-section       1 'RULE 6'  'a required section is missing'
run rule-7-out-of-order          1 'RULE 7'  'the ten sections are present but out of order'
run rule-8-wrong-title           1 'RULE 8'  'a section carries the wrong canonical title'
run rule-9-edited-after-admission 1 'RULE 9.*edited after admission' 'an admitted spec was edited after the fact'
run rule-9-orphan-record         1 'RULE 9.*does not exist'          'a ledger record whose spec was deleted'
run rule-10-flag-without-default 1 'RULE 10.*has no default'         'a flag with an empty Default cell, admitted on/after 2026-09-24'

# ── "cannot run" is not "clean" ────────────────────────────────────────────────
# The failure this repo has actually been bitten by is a gate that exits 0 having checked
# nothing. Both of these fixtures exist to prove exit 2 is reachable and distinct.
printf '\n%s━━ cannot-run is distinguishable from clean%s\n\n' "$BOLD" "$RST"
run empty-tree                   2 'refusing to report green' 'an intake tree with nothing admitted'
run no-ledger                    2 'not held immutable by anything' 'admitted specs with no ledger at all'

# ── discrimination ─────────────────────────────────────────────────────────────
# A rule that fires on everything is as broken as one that fires on nothing, so each
# fixture must trip its OWN rule and no other. The rule number is taken from the fixture
# name, so a fixture that drifts from its name fails here rather than passing quietly.
printf '\n%s━━ discrimination: each fixture trips exactly one rule%s\n\n' "$BOLD" "$RST"
for d in "$FIX"/rule-*; do
  name="$(basename "$d")"
  want="RULE $(printf '%s' "$name" | sed -E 's/^rule-([0-9]+)-.*/\1/')"
  out="$(bash "$ROOT/$GATE" --root "$ROOT/$d" 2>&1)"
  fired="$(printf '%s' "$out" | grep -oE 'RULE [0-9]+' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  if [ "$fired" = "$want" ]; then
    ok "$(printf '%-32s fired: %s' "$name" "$fired")"
  else
    bad "$(printf '%-32s fired: [%s], wanted exactly [%s]' "$name" "$fired" "$want")"
  fi
done

# ── the ledger is really being read ────────────────────────────────────────────
# rule-9-edited-after-admission differs from clean ONLY in the ledger, so if the gate
# ignored the ledger entirely both would be green and the suite above would still look
# healthy. Asserting the two fixtures' SPEC FILES are byte-identical is what makes that
# fixture a proof about the ledger rather than about the document.
printf '\n%s━━ rule 9 is a proof about the ledger, not about the file%s\n\n' "$BOLD" "$RST"
if diff -q "$FIX/clean/specs/admitted/xal-demo/1.0.0.md" \
           "$FIX/rule-9-edited-after-admission/specs/admitted/xal-demo/1.0.0.md" >/dev/null 2>&1; then
  ok "the clean and rule-9 specs are byte-identical — only the ledger differs"
else
  bad "the rule-9 fixture's spec differs from clean; it no longer isolates the ledger"
fi

printf '\n%s──────── %s passed · %s failed ────────%s\n' "$BOLD" "$pass" "$fail" "$RST"
[ "$fail" -eq 0 ] || exit 1
printf '%sspec-intake-check is proven able to fail, per rule, and to discriminate between rules.%s\n' "$GREEN" "$RST"
exit 0
