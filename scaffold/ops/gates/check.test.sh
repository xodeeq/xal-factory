#!/usr/bin/env bash
#
# gates/check.test.sh: proof that scripts/check.sh has teeth, and says which tooth.
#
# Each fixture under gates/fixtures/check/<name>/ is an overlay copied OVER a throwaway copy
# of this repo; the repo itself is never modified. One fixture per gate that guards this
# repo's own state (the per-rule fixtures of each script live in their own harnesses), plus
# a clean one proving the chain can still say yes. Not a gate inside check.sh: it runs
# check.sh, so CI runs it as a separate step.
#
# Exit: 0 every fixture behaved · 1 one did not · 2 could not run
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/gates/fixtures/check"
[ -d "$FIX" ] || { printf 'no fixtures at %s\n' "$FIX"; exit 2; }
pass=0; fail=0
run() {
  local fx="$1" want="$2" pat="$3" desc="$4" tmp out rc
  tmp="$(mktemp -d)" || exit 2
  ( cd "$ROOT" && tar --exclude='./.git' -cf - . ) | ( cd "$tmp" && tar -xf - )
  ( cd "$FIX/$fx" && tar -cf - . ) | ( cd "$tmp" && tar -xf - )
  out="$( cd "$tmp" && bash scripts/check.sh 2>&1 )"; rc=$?
  rm -rf "$tmp"
  if [ "$rc" = "$want" ] && printf '%s' "$out" | grep -qE -- "$pat"; then
    printf '  ✔ %-30s exit %s  %s\n' "$fx" "$rc" "$desc"; pass=$((pass + 1))
  else
    printf '  ✗ %-30s exit %s, wanted %s and /%s/  (%s)\n' "$fx" "$rc" "$want" "$pat" "$desc"
    printf '%s\n' "$out" | tail -20 | sed 's/^/      | /'; fail=$((fail + 1))
  fi
}
run spec-edited-after-admission 1 'CHECK FAILED at: spec-intake \(every' 'an admitted spec whose digest no longer matches its ledger record'
run nudge-cannot-render         1 'CHECK FAILED at: status renders'       'a status file with an empty next_action, which the nudge cannot render'
run clean                       0 'ALL GATES PASSED'                      'a new ops repo, nothing admitted yet, must pass'
printf '\n──────── %s passed · %s failed ────────\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
