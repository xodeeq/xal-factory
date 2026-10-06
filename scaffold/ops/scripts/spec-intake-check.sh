#!/usr/bin/env bash
#
# spec-intake-check.sh — enforce the spec-intake format (specs/README.md).
#
# A spec is the one document the build pipeline consumes. This gate is what makes
# "typed artifact of the company" true rather than asserted: the four frontmatter keys,
# the ten sections in order, the path↔frontmatter binding, and the verbatim guarantee.
#
# WHAT IT DELIBERATELY DOES NOT DO ------------------------------------------------
#
# It does not check prose, completeness, or whether the spec is any good — a critic
# reads for that. It checks the properties a machine can decide, and it checks them
# closed: a missing ledger record is a violation, not "nothing to compare against".
#
# It also does not scan anything outside specs/. A repo's own document frontmatter schema binds
# docs/ and .claude/agents/; this one binds specs/admitted/ and the two do not overlap
# by design (specs/README.md, "Why this lives outside docs/"). frontmatter-check skips
# specs/admitted/ for the same reason it skips docs/platform/: both are verbatim
# read-only copies, and a finding in one is unfixable where it is found.
#
# THE TEN RULES -------------------------------------------------------------------
#   1. missing frontmatter block, or a missing/empty required key
#      (service, spec_version, date, status)
#   2. spec_version is not semver MAJOR.MINOR.PATCH
#   3. date is not an ISO 8601 calendar date
#   4. status does not open with a state token from the vocabulary
#   5. the path↔frontmatter binding is broken: a file that is not
#      specs/admitted/<service>/<spec_version>.md as its own frontmatter declares it
#   6. a required section (1-10) is missing
#   7. numbered sections are not in strictly ascending order
#   8. a section title is not the canonical title for its number
#   9. the ledger and the tree disagree: an unrecorded spec, a record with no spec, or
#      a sha256 that no longer matches — i.e. an admitted spec was edited after the fact
#  10. a spec admitted on or after 2026-09-24 declares no flag table, or a flag in it has
#      no default and no `required` reason (platform service-conventions §9, ruled
#      2026-09-24: every flag ships with a default; only what cannot be defaulted is
#      required at selection, and it says why)
#
# GOTCHA (rule 10, why it keys on the ledger's admitted date): an admitted spec is
# immutable (rule 9), so a rule added later cannot bind what was admitted earlier without
# making every older admission red forever. The ledger's fourth column is the admission
# date; the rule binds admissions from the day it was ruled (2026-09-24), so a spec admitted
# earlier is exempt until its next version.
#
# GOTCHA (rule 10, the table shape): a machine cannot find "the flags" in prose, so the
# rule fixes a shape: a markdown table whose header has a `Flag` column and a `Default`
# column. Every data row's Default cell is non-empty; a cell that opens with `required`
# must carry a reason after a colon or in parentheses, so `required` alone is a violation.
# The other columns are the author's.
#
# GOTCHA (rule 9, and the whole reason for the ledger): "admitted verbatim" is a claim
# about TIME, and a gate cannot see time. Recomputing a digest against a record that
# lives in the same commit as the file proves nothing about the original — what it does
# prove is that nobody has touched the file SINCE, which is the property that actually
# rots.
#
# GOTCHA (rule 5, why the binding is checked at all): nothing else makes the directory
# name mean anything. Without it, specs/admitted/orders/1.0.0.md may declare
# `service: billing, spec_version: 2.0.0` and every consumer that resolves a spec by
# path silently reads the wrong document — a failure with no symptom until something is
# built from it.
#
# GOTCHA (rule 8, titles carry suffixes): the real spec's section 7 is
# "## 7. Non-functional requirements (right-sized; 0.1 §2 verdicts in force)". The
# canonical title is a PREFIX test, not equality, or the format would reject a spec for
# being more specific than the template. A suffix must start at a word boundary, so
# "Eventsourcing" is not "Events".
#
# GOTCHA (empty tree): no specs found is exit 2, not exit 0. A gate over an empty tree
# emits byte-identical green to a gate over a clean one, and "the intake layer is green"
# would then be true of a repo that has admitted nothing. Loud beats quiet.
#
# Usage:  scripts/spec-intake-check.sh [--root DIR]
# Exit:   0 clean · 1 violations found · 2 could not run
# Deps:   bash, awk, grep, find, sed, sort, and shasum OR sha256sum. No language
#         runtime, no network, no credential, no git.

set -uo pipefail

ROOT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; [ -n "$ROOT" ] || { printf -- '--root needs a directory\n' >&2; exit 2; }; shift 2 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -d "$ROOT" ] || { printf 'root is not a directory: %s\n' "$ROOT" >&2; exit 2; }
cd "$ROOT" || exit 2

if [ -t 1 ]; then RED=$'\033[31m'; GREEN=$'\033[32m'; RST=$'\033[0m'
else RED=""; GREEN=""; RST=""; fi

SPECS="specs/admitted"
LEDGER="specs/ledger"
REQUIRED_KEYS="service spec_version date status"
STATUS_TOKENS="draft proposed in-review approved accepted superseded withdrawn rejected"
RULE10_FROM="2026-09-24"   # admissions from this date must declare flags with defaults

violations=0
v() { printf '%s  %s%s\n' "$RED" "$1" "$RST"; violations=$((violations + 1)); }

# --- preconditions (exit 2, never a quiet pass) --------------------------------
if command -v shasum >/dev/null 2>&1;      then sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
elif command -v sha256sum >/dev/null 2>&1; then sha256() { sha256sum "$1"    | awk '{print $1}'; }
else printf 'neither shasum nor sha256sum is available; rule 9 cannot run\n' >&2; exit 2
fi

[ -d "$SPECS" ]  || { printf '%s does not exist — there is no intake tree to check\n' "$SPECS" >&2; exit 2; }
[ -f "$LEDGER" ] || { printf '%s does not exist — admitted specs are not held immutable by anything\n' "$LEDGER" >&2; exit 2; }

specs="$(find "$SPECS" -type f -name '*.md' 2>/dev/null | sed 's|^\./||' | sort)"
[ -n "$specs" ] || { printf 'no specs found under %s — refusing to report green over an empty tree\n' "$SPECS" >&2; exit 2; }

# --- the ten canonical sections ------------------------------------------------
canonical_title() {
  case "$1" in
    1)  echo "Purpose and boundary" ;;
    2)  echo "Decomposition and rationale" ;;
    3)  echo "Functional requirements" ;;
    4)  echo "Data ownership and schema sketch" ;;
    5)  echo "Synchronous interfaces" ;;
    6)  echo "Events" ;;
    7)  echo "Non-functional requirements" ;;
    8)  echo "Human-only actions" ;;
    9)  echo "Open decisions" ;;
    10) echo "Source ledger" ;;
    *)  echo "" ;;
  esac
}

# --- frontmatter helpers ---------------------------------------------------------
fm_block() {
  awk 'NR==1 && $0 != "---" { exit }
       NR==1 { infm=1; next }
       infm && $0 == "---" { exit }
       infm { print }' "$1"
}

fm_get() {
  printf '%s\n' "$2" | awk -v k="$1" '
    $0 ~ "^" k ":" {
      sub("^" k ":[[:space:]]*", "")
      gsub(/^["'"'"']|["'"'"']$/, "")
      sub(/[[:space:]]+$/, "")
      print; exit
    }'
}

# A real calendar date, not just four-two-two digits: 2026-13-40 is not a date.
iso_date_ok() {
  case "$1" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) : ;;
    *) return 1 ;;
  esac
  local y="${1%%-*}" rest="${1#*-}" m d
  m="${rest%%-*}"; d="${rest#*-}"
  [ "$m" -ge 1 ] 2>/dev/null && [ "$m" -le 12 ] || return 1
  [ "$d" -ge 1 ] 2>/dev/null && [ "$d" -le 31 ] || return 1
  [ "$y" -ge 2000 ] 2>/dev/null || return 1
  return 0
}

nspecs=0
seen_paths=""

while IFS= read -r f; do
  [ -n "$f" ] || continue
  nspecs=$((nspecs + 1))
  seen_paths="${seen_paths}${f}"$'\n'

  block="$(fm_block "$f")"

  # ── rule 1 ──────────────────────────────────────────────────────────────────
  if [ -z "$block" ]; then
    v "RULE 1  $f: no YAML frontmatter block at all (needs: $REQUIRED_KEYS)"
    fm_service=""; fm_version=""; fm_date=""; fm_status=""
  else
    fm_service="$(fm_get service "$block")"
    fm_version="$(fm_get spec_version "$block")"
    fm_date="$(fm_get date "$block")"
    fm_status="$(fm_get status "$block")"
    missing=""
    for k in $REQUIRED_KEYS; do
      [ -n "$(fm_get "$k" "$block")" ] || missing="$missing $k"
    done
    [ -n "$missing" ] && v "RULE 1  $f: missing required key(s):$missing"
  fi

  # Rules 2-4 check a key's VALUE, so they only apply when the key is present —
  # otherwise one missing key would trip two rules and no fixture could isolate either.

  # ── rule 2 ──────────────────────────────────────────────────────────────────
  if [ -n "$fm_version" ] && ! printf '%s' "$fm_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    v "RULE 2  $f: spec_version '$fm_version' is not semver MAJOR.MINOR.PATCH"
  fi

  # ── rule 3 ──────────────────────────────────────────────────────────────────
  if [ -n "$fm_date" ] && ! iso_date_ok "$fm_date"; then
    v "RULE 3  $f: date '$fm_date' is not an ISO 8601 calendar date (YYYY-MM-DD)"
  fi

  # ── rule 4 ──────────────────────────────────────────────────────────────────
  # The token is the first word; everything after it is the author's prose and is
  # deliberately unconstrained (specs/README.md, "The format").
  if [ -n "$fm_status" ]; then
    token="$(printf '%s' "$fm_status" | awk '{print tolower($1)}' | sed 's/[,;:.]*$//')"
    if ! printf '%s\n' $STATUS_TOKENS | grep -qxF -- "$token"; then
      v "RULE 4  $f: status opens with '$token', which is not a state token (allowed: $STATUS_TOKENS)"
    fi
  fi

  # ── rule 5: the path↔frontmatter binding ────────────────────────────────────
  rel="${f#"$SPECS"/}"
  case "$rel" in
    */*/*) v "RULE 5  $f: is nested too deeply — the shape is $SPECS/<service>/<spec_version>.md" ;;
    */*)
      path_service="${rel%%/*}"
      path_version="${rel#*/}"; path_version="${path_version%.md}"
      if [ -n "$fm_service" ] && [ "$fm_service" != "$path_service" ]; then
        v "RULE 5  $f: directory says service '$path_service', frontmatter says '$fm_service'"
      fi
      if [ -n "$fm_version" ] && [ "$fm_version" != "$path_version" ]; then
        v "RULE 5  $f: filename says spec_version '$path_version', frontmatter says '$fm_version'"
      fi ;;
    *) v "RULE 5  $f: sits directly in $SPECS — the shape is $SPECS/<service>/<spec_version>.md" ;;
  esac

  # ── rules 6, 7, 8: the ten sections ─────────────────────────────────────────
  # A numbered section is `## N. Title` at heading level two exactly; `### N.M` is a
  # subsection and `# ` is the document title, so neither is collected here.
  headings="$(grep -nE '^## [0-9]+\.[[:space:]]' "$f" || true)"

  numbers=""
  if [ -n "$headings" ]; then
    while IFS= read -r h; do
      [ -n "$h" ] || continue
      lno="${h%%:*}"
      text="${h#*:}"
      num="$(printf '%s' "$text" | sed -E 's/^## ([0-9]+)\..*/\1/')"
      title="$(printf '%s' "$text" | sed -E 's/^## [0-9]+\.[[:space:]]*//')"

      # Section 0 is an optional preface and has no canonical title.
      [ "$num" = "0" ] && continue
      numbers="${numbers}${num} "

      want="$(canonical_title "$num")"
      if [ -z "$want" ]; then
        v "RULE 6  $f:$lno: section $num is outside the ten-section structure (1-10, plus an optional section 0)"
        continue
      fi
      # Rule 8 — prefix test at a word boundary, so a suffix is fine and a longer word
      # is not. Case-insensitive: a title is prose, not an identifier.
      lt="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]')"
      lw="$(printf '%s' "$want"  | tr '[:upper:]' '[:lower:]')"
      case "$lt" in
        "$lw") : ;;
        "$lw"[!a-z0-9]*) : ;;
        *) v "RULE 8  $f:$lno: section $num is titled '$title'; the canonical title is '$want'" ;;
      esac
    done <<< "$headings"
  fi

  # Rule 6 — presence, by NUMBER, so a retitled section (rule 8) does not also read as
  # a missing one. Rule 7 — order, over the numbers actually present, so a missing
  # section does not also read as disordered.
  absent=""
  for n in 1 2 3 4 5 6 7 8 9 10; do
    case " $numbers " in
      *" $n "*) : ;;
      *) absent="$absent $n" ;;
    esac
  done
  if [ -n "$absent" ]; then
    for n in $absent; do
      v "RULE 6  $f: required section $n is missing ($(canonical_title "$n"))"
    done
  fi

  prev=0; disordered=""
  for n in $numbers; do
    if [ "$n" -le "$prev" ]; then disordered="$disordered $prev>$n"; fi
    prev="$n"
  done
  [ -n "$disordered" ] && v "RULE 7  $f: numbered sections are not in ascending order ($(printf '%s' "$numbers" | sed 's/[[:space:]]*$//')) — at:$disordered"

  # ── rule 9: verbatim, against the declared record ───────────────────────────
  # Keyed on the PATH, not on frontmatter: the path is the slot a consumer resolves,
  # and keying on a field rule 5 may already have found wrong would report one defect
  # twice and stop each fixture tripping exactly one rule.
  key_service="${rel%%/*}"
  key_version="${rel#*/}"; key_version="${key_version%.md}"
  recorded="$(sed 's/#.*//' "$LEDGER" | awk -F'|' -v s="$key_service" -v vv="$key_version" '
    NF >= 3 {
      a=$1; b=$2; c=$3
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", a)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", b)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", c)
      if (a == s && b == vv) { print c; exit }
    }')"
  actual="$(sha256 "$f")"
  if [ -z "$recorded" ]; then
    v "RULE 9  $f: admitted but not recorded in $LEDGER ($key_service | $key_version) — an unrecorded spec is held verbatim by nothing (sha256: $actual)"
  elif [ "$recorded" != "$actual" ]; then
    v "RULE 9  $f: edited after admission — $LEDGER records $recorded, the file hashes to $actual"
  fi

  # ── rule 10: every flag ships with a default ────────────────────────────────
  # Binds admissions from RULE10_FROM by the ledger's `admitted` column (fourth field);
  # an older admission is immutable evidence and is left alone. A spec with no ledger
  # record has already tripped rule 9 and is skipped here so each fixture trips one rule.
  admitted_on="$(sed 's/#.*//' "$LEDGER" | awk -F'|' -v s="$key_service" -v vv="$key_version" '
    NF >= 4 {
      a=$1; b=$2; d=$4
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", a)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", b)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", d)
      if (a == s && b == vv) { print d; exit }
    }')"
  if [ -n "$admitted_on" ] && { [ "$admitted_on" \> "$RULE10_FROM" ] || [ "$admitted_on" = "$RULE10_FROM" ]; }; then
    # The flag table: the first table whose header row has a `Flag` cell. Its Default
    # column index is found on the same row. Rows continue until a non-table line.
    r10="$(awk '
      function trim(x) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", x); return x }
      BEGIN { intab=0; found=0; fcol=0; dcol=0; row=0 }
      /^\|/ {
        n = split($0, c, "|")
        if (!intab) {
          fc=0; dc=0
          for (i=2; i<n; i++) { h=tolower(trim(c[i])); if (h=="flag") fc=i; if (h=="default") dc=i }
          if (fc) { intab=1; found=1; fcol=fc; dcol=dc; row=0
                    if (!dcol) { print "NODEFAULTCOL"; exit } }
          next
        }
        row++
        if (row==1 && $0 !~ /[A-Za-z0-9]/) next
        flag=trim(c[fcol]); gsub(/`/, "", flag)
        def=trim(c[dcol])
        if (def=="") { printf "EMPTY %s\n", flag; next }
        if (tolower(def) ~ /^`?required`?/) {
          rest=def; sub(/^`?[Rr]equired`?/, "", rest); rest=trim(rest)
          if (rest !~ /^[:(].*[A-Za-z]/) printf "BAREREQ %s\n", flag
        }
        next
      }
      intab { intab=0 }
      END { if (!found) print "NOTABLE" }' "$f")"
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      case "$line" in
        NOTABLE)      v "RULE 10  $f: admitted $admitted_on but declares no flag table (a header with a Flag column and a Default column) — every unit declares its flags, and every flag ships with a default (§9)" ;;
        NODEFAULTCOL) v "RULE 10  $f: the flag table has no Default column — every flag ships with a default (§9)" ;;
        EMPTY\ *)     v "RULE 10  $f: flag '${line#EMPTY }' has no default — give it one, or mark it 'required: <why it cannot be defaulted>'" ;;
        BAREREQ\ *)   v "RULE 10  $f: flag '${line#BAREREQ }' is required with no reason — a required flag says why it cannot be defaulted" ;;
      esac
    done <<< "$r10"
  fi
done <<< "$specs"

# The inverse direction, which rots silently: a record whose spec is gone. Deleting the
# file does not withdraw the admission, it just removes the evidence.
while IFS= read -r rec; do
  [ -n "$rec" ] || continue
  ls="$(printf '%s' "$rec" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1}')"
  lv="$(printf '%s' "$rec" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')"
  [ -n "$ls" ] && [ -n "$lv" ] || continue
  case "$seen_paths" in
    *"$SPECS/$ls/$lv.md"$'\n'*) : ;;
    *) v "RULE 9  $LEDGER: records $ls | $lv, but $SPECS/$ls/$lv.md does not exist — a deleted spec is not an un-admitted one" ;;
  esac
done <<< "$(sed 's/#.*//' "$LEDGER" | awk -F'|' 'NF >= 3')"

# --- report --------------------------------------------------------------------
if [ "$violations" -ne 0 ]; then
  printf '\n%s::error::spec-intake-check found %s violation(s)%s\n' "$RED" "$violations" "$RST"
  exit 1
fi
printf '  %sspec-intake clean%s — %s admitted spec(s) checked: frontmatter (4 keys), the ten sections in order, the path binding, sha256 against %s, and flag defaults on admissions from %s\n' \
  "$GREEN" "$RST" "$nspecs" "$LEDGER" "$RULE10_FROM"
exit 0
