#!/usr/bin/env bash
#
# reader-verdict.sh — turn the reader's verdict file into the one word merge.yml reads.
#
# THE READER IS THE JUDGEMENT HALF; THIS IS THE MECHANICAL HALF. The reader (the xal-factory plugin's
# `reader` agent, run by reader.yml on every session PR) reads the diff against the admitted
# spec and this repo's standards and writes a verdict file. Whether that file says "land it"
# is not something to leave to a model's prose, so the answer is decided here, by a script
# with committed fixtures — the same split ADR-0008 made for the plan critic.
#
# THE VERDICT FILE, written by the reader:
#
#   { "standards": "PASS" | "FINDINGS",
#     "spec":      "PASS" | "FINDINGS",
#     "findings":  [ { "axis": "spec" | "standards", "ref": "...", "where": "...", "what": "..." } ] }
#
# THE ONE-WAY RULE. `success` is printed only for a file that is well formed, says PASS on
# BOTH axes, and names no finding. Everything else is `failure` — a finding, a missing file,
# a file that is not JSON, a value outside the vocabulary, and the two contradictions (PASS
# with findings listed; FINDINGS with none named). A reader that crashed, ran out of turns or
# wrote nonsense has not read the pull request, and "the reviewer said nothing" must never
# read as "the reviewer found nothing". That is the unjudged-is-not-green rule once more.
#
# EXIT CODES — the driver's convention:
#   0  the file was read: `success` or `failure` alone on stdout
#   3  REFUSED — the file is missing or malformed; `failure` is STILL on stdout, so a caller
#      that only reads stdout cannot turn a broken verdict into a green one
#   2  CANNOT RUN — bad arguments, or jq is absent
#
# With --summary <path> it also writes the findings as markdown for the PR comment.
#
# Usage: reader-verdict.sh --file verdict.json [--summary summary.md]
# Deps: bash, jq (declared in .xal/gate-inputs; this script's fixtures run in the gate chain).

set -uo pipefail

FILE="" SUMMARY=""
while [ $# -gt 0 ]; do
  case "$1" in
    (--file)    FILE="${2:-}"; shift 2 ;;
    (--summary) SUMMARY="${2:-}"; shift 2 ;;
    (*) printf 'reader-verdict: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$FILE" ] || { printf 'reader-verdict: --file is required\n' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf 'reader-verdict: CANNOT RUN: jq is not installed\n' >&2; exit 2; }

summary() { [ -z "$SUMMARY" ] || printf '%s\n' "$1" > "$SUMMARY"; }

malformed() {
  printf 'failure\n'
  printf 'REFUSED: the reader verdict is unusable — %s. That is a failure, never a pass:\n' "$1" >&2
  printf '         a reader that did not produce a readable verdict has not read the PR.\n' >&2
  printf '::error title=Reader verdict::%s\n' "$1" >&2
  summary "**Reader: no usable verdict** — $1. This pull request stays open for a person."
  exit 3
}

[ -f "$FILE" ] || malformed "no verdict file at $FILE"
jq -e 'type == "object"' "$FILE" >/dev/null 2>&1 || malformed "the file is not a JSON object"

std="$(jq -r '.standards // empty' "$FILE")"
spec="$(jq -r '.spec // empty' "$FILE")"
n="$(jq -r 'if (.findings | type) == "array" then (.findings | length) else "bad" end' "$FILE")"

for pair in "standards:$std" "spec:$spec"; do
  case "${pair#*:}" in
    (PASS|FINDINGS) ;;
    (*) malformed "axis '${pair%%:*}' is '${pair#*:}', not PASS or FINDINGS" ;;
  esac
done
[ "$n" != "bad" ] || malformed "'findings' is not an array"

if [ "$std" = PASS ] && [ "$spec" = PASS ]; then
  [ "$n" -eq 0 ] || malformed "both axes say PASS yet $n finding(s) are listed — a contradiction is not a verdict"
  printf 'success\n'
  printf '  reader: PASS on both axes, no findings\n' >&2
  summary "**Reader: PASS** on both axes (Standards, Spec). No findings."
  exit 0
fi

[ "$n" -gt 0 ] || malformed "an axis says FINDINGS yet no finding is named — a finding nobody can read is not one"
bad="$(jq -r '[.findings[] | select((.axis != "spec" and .axis != "standards") or ((.what // "") == ""))] | length' "$FILE")"
[ "$bad" = 0 ] || malformed "$bad finding(s) have no axis in {spec, standards} or no 'what'"

printf 'failure\n'
printf '  reader: Standards %s, Spec %s — %s finding(s)\n' "$std" "$spec" "$n" >&2
if [ -n "$SUMMARY" ]; then
  {
    printf '**Reader: FINDINGS** — Standards **%s**, Spec **%s**. This pull request does not merge\n' "$std" "$spec"
    printf 'without a person; each finding is also a candidate lesson (the 2026-09-19 loop).\n\n'
    printf '| Axis | Ref | Where | What |\n|---|---|---|---|\n'
    jq -r '.findings[] | "| \(.axis) | \(.ref // "") | \(.where // "") | \(.what | gsub("\\|"; "\\\\|") | gsub("\n"; " ")) |"' "$FILE"
  } > "$SUMMARY"
fi
exit 0
