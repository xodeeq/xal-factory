#!/usr/bin/env bash
#
# gates/reader-eval.test.sh — proof that reader-eval.sh can fail, and fails for the right reason.
#
# reader-eval.sh judges the REAL reader's verdicts in .github/workflows/reader-eval.yml, which
# spends tokens and so runs only when the reader or its fixture changes. This suite runs on
# every build and costs nothing: canned verdicts, each asserting the exit code AND which
# expectation failed. The case that earns it is noise-misses-omission — a reader that reports
# SOMETHING on the Spec axis but not the omitted clause. An evaluator checking only "Spec says
# FINDINGS" would pass it, and that reader would wave the omission through on a real PR.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
EV="scripts/reader-eval.sh"; V="gates/fixtures/reader/verdicts"
pass=0; fail=0
check() {  # check <label> <want_exit> <want_pattern> -- <cmd…>
  local label="$1" want="$2" pat="$3"; shift 4
  local out rc; out="$("$@" 2>&1)"; rc=$?
  if [ "$rc" = "$want" ] && printf '%s' "$out" | grep -qE -- "$pat"; then
    printf '  ✔ %-26s exit %s\n' "$label" "$rc"; pass=$((pass + 1))
  else
    printf '  ✗ %-26s exit %s (wanted %s /%s/)\n' "$label" "$rc" "$want" "$pat"
    printf '%s\n' "$out" | sed 's/^/      | /'; fail=$((fail + 1))
  fi
}
check clean-passes          0 'PASS on the clean fixture'  -- bash "$EV" --verdict "$V/pass.json" --expect pass
check omission-caught       0 'omission of FX-FR-02 was reported' -- bash "$EV" --verdict "$V/catches-omission.json" --expect findings:FX-FR-02
check clean-flagged         3 'expected PASS on both axes' -- bash "$EV" --verdict "$V/catches-omission.json" --expect pass
check omission-passed       3 "Spec axis says 'PASS'"      -- bash "$EV" --verdict "$V/pass.json" --expect findings:FX-FR-02
check omission-noise        3 'no spec-axis finding names FX-FR-02' -- bash "$EV" --verdict "$V/noise-misses-omission.json" --expect findings:FX-FR-02
check omission-wrong-axis   3 "Spec axis says 'PASS'"      -- bash "$EV" --verdict "$V/standards-only.json" --expect findings:FX-FR-02
check no-verdict            3 'wrote no verdict file'      -- bash "$EV" --verdict "$V/does-not-exist.json" --expect pass
check bad-expectation       2 'must be pass or findings'   -- bash "$EV" --verdict "$V/pass.json" --expect maybe
printf '──── %s passed · %s failed ────\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
