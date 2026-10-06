#!/usr/bin/env bash
# Gate for scripts/status-render.sh: the two failing fixtures must fail naming
# their rule; the clean fixture must pass and render the expected lines.
set -u
cd "$(dirname "$0")/.."
fail=0
if scripts/status-render.sh gates/fixtures/status/missing-next-action.md >/dev/null 2>err.txt; then
  echo "FAIL: missing-next-action fixture passed"; fail=1
elif ! grep -q "next_action" err.txt; then
  echo "FAIL: missing-next-action did not name its rule"; fail=1
fi
if scripts/status-render.sh gates/fixtures/status/wrong-type.md >/dev/null 2>err.txt; then
  echo "FAIL: wrong-type fixture passed"; fail=1
elif ! grep -q "type" err.txt; then
  echo "FAIL: wrong-type did not name its rule"; fail=1
fi
out="$(scripts/status-render.sh gates/fixtures/status/clean.md)" || { echo "FAIL: clean fixture failed"; fail=1; }
echo "$out" | grep -q "^Today's one action: Do the one thing$" || { echo "FAIL: action line"; fail=1; }
[ "$(echo "$out" | grep -c '^Needs you: ')" = "2" ] || { echo "FAIL: blocker lines"; fail=1; }
scripts/status-render.sh status/current.md >/dev/null || { echo "FAIL: real status file does not render"; fail=1; }
rm -f err.txt
[ $fail = 0 ] && echo "status-render gate: PASS"
exit $fail
