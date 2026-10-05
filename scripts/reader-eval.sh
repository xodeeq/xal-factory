#!/usr/bin/env bash
#
# reader-eval.sh — did the reader catch what it must catch, and pass what it must pass?
#
# THE READER'S FAILING FIXTURE, ruled 2026-09-20 (adjudication §3h): "a diff that omits a cited
# spec clause and must be reported". gates/fixtures/reader/ holds that diff (omission/: the
# session cites FX-FR-02, nothing realises it, and a commit message claims it anyway) beside a
# clean one (clean/: both clauses realised, each asserted, RED before GREEN). The workflow
# .github/workflows/reader-eval.yml runs the real reader (the xal-factory plugin's `reader` agent) over
# each and hands its verdict here.
#
# WHY THIS IS SPLIT FROM THE RUN. The run spends tokens, so it happens in a workflow when the
# reader's definition or its fixture changes. The JUDGEMENT of the run is mechanical, so it is
# this script, and this script's own fixtures (gates/reader-eval.test.sh, canned verdicts under
# gates/fixtures/reader/verdicts/) run in scripts/check.sh on every build: a checker that
# could pass a reader which missed the omission would be caught before any reader is run.
#
# EXPECTATIONS
#   --expect pass              PASS on both axes and no findings
#   --expect findings:<REF>    Spec says FINDINGS, and a spec-axis finding names <REF> in its
#                              `ref` or its `what`. Findings about other things are allowed;
#                              missing <REF> is not — a reader that reports noise and misses
#                              the omission has failed exactly the way that matters.
#
# EXIT: 0 the verdict meets the expectation · 3 it does not (named) · 2 cannot run
# Usage: reader-eval.sh --verdict .reader/verdict.json --expect findings:FX-FR-02
# Deps: bash, jq (declared in .xal/gate-inputs).

set -uo pipefail

VERDICT="" EXPECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    (--verdict) VERDICT="${2:-}"; shift 2 ;;
    (--expect)  EXPECT="${2:-}"; shift 2 ;;
    (*) printf 'reader-eval: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done
[ -n "$EXPECT" ] || { printf 'reader-eval: --expect is required\n' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf 'reader-eval: CANNOT RUN: jq is not installed\n' >&2; exit 2; }

miss() { printf 'EVAL FAILED: %s\n' "$1" >&2; printf '::error title=Reader eval::%s\n' "$1" >&2; exit 3; }

# A reader that produced no readable verdict has failed the eval, whatever was expected.
[ -n "$VERDICT" ] && [ -f "$VERDICT" ] || miss "the reader wrote no verdict file"
jq -e 'type == "object" and (.findings | type) == "array"' "$VERDICT" >/dev/null 2>&1 \
  || miss "the verdict is not a JSON object with a findings array"

std="$(jq -r '.standards // ""' "$VERDICT")"
spec="$(jq -r '.spec // ""' "$VERDICT")"
n="$(jq -r '.findings | length' "$VERDICT")"

case "$EXPECT" in
  (pass)
    [ "$std" = PASS ] && [ "$spec" = PASS ] && [ "$n" -eq 0 ] \
      || miss "expected PASS on both axes with no findings; got Standards=$std Spec=$spec with $n finding(s): $(jq -c '.findings' "$VERDICT" | cut -c1-300)"
    printf 'reader-eval: PASS on the clean fixture, as required\n' ;;
  (findings:*)
    ref="${EXPECT#findings:}"
    [ "$spec" = FINDINGS ] || miss "expected Spec FINDINGS naming $ref; the Spec axis says '$spec'"
    hit="$(jq -r --arg r "$ref" '[.findings[] | select(.axis == "spec") | select(((.ref // "") | contains($r)) or ((.what // "") | contains($r)))] | length' "$VERDICT")"
    [ "$hit" -gt 0 ] || miss "Spec says FINDINGS but no spec-axis finding names $ref — the omission was not caught: $(jq -c '.findings' "$VERDICT" | cut -c1-300)"
    printf 'reader-eval: the omission of %s was reported (%s spec finding(s) name it)\n' "$ref" "$hit" ;;
  (*) printf 'reader-eval: --expect must be pass or findings:<REF>, got %s\n' "$EXPECT" >&2; exit 2 ;;
esac
exit 0
