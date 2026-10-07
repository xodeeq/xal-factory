#!/usr/bin/env bash
#
# gates/check.test.sh — proof that scripts/check.sh has teeth, and that it says which tooth.
#
# THE RULE THIS SATISFIES (spec/gate-discipline.md §5): "Every gate ships with committed
# failing fixtures. A gate that has never been seen to fail has not been tested — a rule
# matching nothing and a rule finding nothing emit byte-identical green." One committed
# fixture per gate, proving that gate fails and NAMING it, plus a clean fixture proving the
# chain can still say yes.
#
# WHY THIS IS NOT A GATE INSIDE check.sh: it runs check.sh. A gate inside check.sh that ran
# this would recurse forever. So ci.yml invokes it as a SEPARATE STEP, after the real gate
# run — a genuine failure is reported before a fixture failure and the two are never confused.
#
# HOW A FIXTURE IS APPLIED: each fixture under gates/fixtures/check/<name>/ is an overlay — a
# partial file tree copied OVER a throwaway copy of the repo, replacing the real files at the
# same paths. The repo itself is never modified, so this suite is re-runnable and cannot
# leave the working tree broken. check.sh prunes gates/fixtures from its own link scan for
# the same reason a fixture tree exists at all: its files are broken on purpose.
#
# Gate 5 (plugin manifests) is only provable where the `claude` CLI is present; locally
# without it the gate skips and its fixture is reported as skipped, never as passed. Under
# CI=true the CLI is an installed input and the fixture is asserted.
#
# Usage:  gates/check.test.sh
# Exit:   0 every fixture behaved as specified · 1 at least one did not · 2 could not run
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FIX="$ROOT/gates/fixtures/check"

if [ -t 1 ]; then BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YEL=$'\033[33m'; RST=$'\033[0m'
else BOLD=""; RED=""; GREEN=""; YEL=""; RST=""; fi

[ -f "$ROOT/scripts/check.sh" ] || {
  printf '%sscripts/check.sh not found — there is no gate to prove%s\n' "$RED" "$RST"; exit 2; }
[ -d "$FIX" ] || {
  printf '%sno fixtures at %s — refusing to report green over an empty suite%s\n' "$RED" "$FIX" "$RST"; exit 2; }

pass=0; fail=0; skipped=0

# run <fixture> <want_exit> <want_pattern> <description>
# want_pattern is matched against check.sh's own output, so it asserts WHICH gate fired.
run() {
  local fixture="$1" want_exit="$2" want_pat="$3" desc="$4"
  local tmp out rc problem=""

  [ -d "$FIX/$fixture" ] || {
    printf '%s  ✗%s %-28s fixture directory does not exist\n' "$RED" "$RST" "$fixture"
    fail=$((fail + 1)); return; }

  tmp="$(mktemp -d)" || { printf '%smktemp failed%s\n' "$RED" "$RST"; fail=$((fail + 1)); return; }

  # Copy the repo minus git history, then overlay the fixture. A fixture may carry a file
  # named DELETE listing paths to remove — the only way to express "this file is missing".
  # The site's build artifacts are excluded: they are hundreds of megabytes no gate reads, and
  # the strip gate scans every file when the copy has no .git.
  ( cd "$ROOT" && tar --exclude='./.git' --exclude='./site/node_modules' --exclude='./site/dist' \
      --exclude='./site/.astro' --exclude='./site/src/content/docs/spec' --exclude='./site/src/content/docs/adr' -cf - . ) | ( cd "$tmp" && tar -xf - )
  ( cd "$FIX/$fixture" && tar --exclude='./DELETE' -cf - . ) | ( cd "$tmp" && tar -xf - )
  if [ -f "$FIX/$fixture/DELETE" ]; then
    while IFS= read -r p; do [ -n "$p" ] && rm -rf "$tmp/${p#/}"; done < "$FIX/$fixture/DELETE"
  fi

  # Capture first, match second: with pipefail on, `check.sh | grep -q` would return the
  # check's status, not grep's.
  out="$( cd "$tmp" && bash scripts/check.sh 2>&1 )"
  rc=$?
  rm -rf "$tmp"

  [ "$rc" = "$want_exit" ] || problem="exit $rc, wanted $want_exit"
  if [ -n "$want_pat" ] && ! printf '%s' "$out" | grep -qE -- "$want_pat"; then
    problem="${problem:+$problem; }output did not name /$want_pat/"
  fi

  if [ -z "$problem" ]; then
    printf '%s  ✔%s %-28s exit %s  %s\n' "$GREEN" "$RST" "$fixture" "$rc" "$desc"
    pass=$((pass + 1))
  else
    printf '%s  ✗%s %-28s %s  (%s)\n' "$RED" "$RST" "$fixture" "$problem" "$desc"
    printf '%s\n' "$out" | tail -30 | sed 's/^/      | /'
    fail=$((fail + 1))
  fi
}

printf '\n%s━━ the gate chain fails, and names the gate that fired%s\n\n' "$BOLD" "$RST"

run gate-0-undeclared-input   1 'CHECK FAILED at: gate inputs' \
    'a five-field manifest record (the pre-expiry format) is refused by gate 0'

if command -v claude >/dev/null 2>&1; then
  run gate-5-broken-plugin    1 'CHECK FAILED at: plugin manifests' \
      'a plugin.json that is not valid JSON fails strict validation'
else
  printf '%s  ⚠ %-28s skipped — claude CLI unavailable (mandatory in CI)%s\n' "$YEL" "gate-5-broken-plugin" "$RST"
  skipped=$((skipped + 1))
  [ "${CI:-}" = "true" ] && { printf '%s  CI=true and the claude CLI is missing — this is a failure, not a skip%s\n' "$RED" "$RST"; fail=$((fail + 1)); }
fi

run gate-1-language-leak      1 'CHECK FAILED at: language-agnostic spec' \
    'a language-specific token stated as a rule, outside any citation'
run gate-1-informative-only   1 'CHECK FAILED at: language-agnostic spec' \
    'every manifest file marked informative — an empty scan must not be green'
run gate-8-product-term      1 'CHECK FAILED at: nothing of the source product' \
    'a lifted script keeps the source product escalation label'
run gate-2-escaping-link      1 'CHECK FAILED at: links resolve' \
    'a vendored file links to ../VERSION — the original bug, reintroduced'
run gate-2-dangling-link      1 'CHECK FAILED at: links resolve' \
    'a relative link to a file that does not exist'
run gate-3-never-vendored     1 'CHECK FAILED at: scaffold self-consistency' \
    'the scaffold links a docs/process/ file that sync/manifest never vendors'
run gate-9-no-evaluator      1 'CHECK FAILED at: reader evaluator' \
    'the reader evaluator is gone, so its fixtures cannot prove it can fail'
run gate-10-ops-red          1 'CHECK FAILED at: ops scaffold' \
    'the ops status template cannot be rendered, so a seeded ops repo is red'
run gate-11-bad-default       1 'CHECK FAILED at: options registry' \
    'an option whose default is not one of its choices'
run gate-12-no-installer      1 'CHECK FAILED at: installer and CLI' \
    'an install.sh that links nothing, so the CLI is never installed'
run gate-14-docs-miss-option  1 'CHECK FAILED at: docs options page' \
    'the options page generator drops a section'
run gate-4-broken-sync        1 'CHECK FAILED at: sync round-trip' \
    'process-sync.sh copies nothing — --check would pass vacuously'

printf '\n%s━━ and it can still say yes%s\n\n' "$BOLD" "$RST"

run clean                     0 'ALL GATES PASSED' \
    'a legitimate spec edit inside a reference citation must PASS'

printf '\n%s──────── %s passed · %s failed · %s skipped ────────%s\n' "$BOLD" "$pass" "$fail" "$skipped" "$RST"
if [ "$fail" -ne 0 ]; then
  printf '%s::error::the gate chain did not behave as its fixtures specify%s\n' "$RED" "$RST"
  exit 1
fi
printf '%sscripts/check.sh is proven able to fail, to name which gate fired, and to pass.%s\n' \
  "$GREEN" "$RST"
exit 0
