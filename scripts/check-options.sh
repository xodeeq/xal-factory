#!/usr/bin/env bash
#
# check-options.sh: the options registry (factory/options.tsv) is whole, valid, and in step
# with everything that reads it.
#
# WHY. The registry drives the onboarding, `xal-factory config`, the defaults every seeded
# repo reads and the docs. A key a workflow reads that the registry does not list has no
# default and no explanation, and fails the first run that needs it. A key the registry lists
# that nothing reads is an option that does nothing while reading as configured. Both are
# silent until they bite, which is what a gate is for.
#
# THE RULES
#   1. every row has eight tab-separated columns, and the header is the first non-comment line
#   2. keys are unique and dotted lower-case (a.b or a.b_c)
#   3. scope is service or ops; ask is yes or no; apply is conf, workflow:<file> or var:<NAME>
#   4. the default is one of the choices (or `required`, or a free-text/int value that fits)
#   5. a workflow:<file> names a workflow some scaffold ships
#   6. every option some script, workflow, agent or the CLI reads is in the registry
#      (`config.sh --get <key>`, `FACTORY_<KEY>` in a workflow, `opt_field/ans_get <key>`)
#   7. every option in the registry has a reader: a `conf` option is read by name or as its
#      FACTORY_ variable somewhere shipped; a workflow: or var: option is read by the CLI's apply
#
# Usage: scripts/check-options.sh [--root DIR]     Exit: 0 clean · 1 violations · 2 cannot run

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ "${1:-}" = --root ] && ROOT="$(cd "${2:-}" && pwd)"
REG="$ROOT/factory/options.tsv"
[ -f "$REG" ] || { printf 'check-options: no registry at %s\n' "$REG" >&2; exit 2; }

if [ -t 1 ]; then RED=$'\033[31m'; GREEN=$'\033[32m'; RST=$'\033[0m'; else RED=""; GREEN=""; RST=""; fi
n=0
v() { printf '%s  %s%s\n' "$RED" "$1" "$RST"; n=$((n + 1)); }

rows="$(awk '!/^#/ && NF' "$REG")"
[ "$(printf '%s\n' "$rows" | head -1 | cut -f1)" = key ] || v "RULE 1  the first non-comment line is not the header (key, default, …)"
body="$(printf '%s\n' "$rows" | tail -n +2)"
[ -n "$body" ] || { v "RULE 1  the registry lists no option: refusing to report green over nothing"; }

while IFS= read -r line; do
  [ -n "$line" ] || continue
  cols="$(printf '%s' "$line" | awk -F'\t' '{ print NF }')"
  k="$(printf '%s' "$line" | cut -f1)"
  [ "$cols" = 8 ] || { v "RULE 1  $k: $cols columns, expected 8"; continue; }
  d="$(printf '%s' "$line" | cut -f2)"; c="$(printf '%s' "$line" | cut -f3)"
  scope="$(printf '%s' "$line" | cut -f4)"; apply="$(printf '%s' "$line" | cut -f5)"; ask="$(printf '%s' "$line" | cut -f6)"
  printf '%s' "$k" | grep -qE '^[a-z]+\.[a-z][a-z0-9_]*$' || v "RULE 2  '$k' is not a dotted lower-case key"
  case "$scope" in service|ops) ;; *) v "RULE 3  $k: scope '$scope' is not service or ops" ;; esac
  case "$ask" in yes|no) ;; *) v "RULE 3  $k: ask '$ask' is not yes or no" ;; esac
  case "$apply" in conf|workflow:*.yml|var:[A-Z]*) ;; *) v "RULE 3  $k: apply '$apply' is not conf, workflow:<file>.yml or var:<NAME>" ;; esac
  if [ "$d" != required ]; then
    case "$c" in
      '*') [ -n "$d" ] || v "RULE 4  $k: empty default" ;;
      int) printf '%s' "$d" | grep -qE '^[1-9][0-9]*$' || v "RULE 4  $k: default '$d' is not a positive integer" ;;
      *)   printf '|%s|' "$c" | grep -qF "|$d|" || v "RULE 4  $k: default '$d' is not one of $c" ;;
    esac
  fi
  case "$apply" in workflow:*)
    wf="${apply#workflow:}"
    find "$ROOT/scaffold" -path "*/.github/workflows/$wf" | grep -q . || v "RULE 5  $k: no scaffold ships .github/workflows/$wf" ;;
  esac
done <<< "$body"

dups="$(printf '%s\n' "$body" | cut -f1 | sort | uniq -d)"
[ -z "$dups" ] || v "RULE 2  duplicate key(s): $(printf '%s' "$dups" | tr '\n' ' ')"

keys="$(printf '%s\n' "$body" | cut -f1)"
envname() { printf 'FACTORY_%s' "$(printf '%s' "${1#factory.}" | tr '[:lower:].' '[:upper:]_')"; }

# Where readers live: everything shipped except the registry itself and the fixtures.
shipped() {
  find "$ROOT/scaffold" "$ROOT/bin" "$ROOT/plugins" "$ROOT/install.sh" -type f \
    ! -path '*/gates/_fixtures/*' ! -path '*/gates/fixtures/*' 2>/dev/null
}

# RULE 6: every key read is registered.
read_keys="$(shipped | xargs grep -hoE 'config\.sh --get [a-z]+\.[a-z0-9_]+|(opt_field|ans_get|repo_value) [a-z]+\.[a-z0-9_]+' 2>/dev/null | awk '{ print $NF }' | sort -u)"
while IFS= read -r k; do
  [ -n "$k" ] || continue
  printf '%s\n' "$keys" | grep -qxF "$k" || v "RULE 6  '$k' is read but not in the registry: it has no default and no explanation"
done <<< "$read_keys"
envs="$(find "$ROOT/scaffold" -path '*/.github/workflows/*.yml' ! -path '*/_fixtures/*' -exec grep -hoE '\$\{?FACTORY_[A-Z_]+' {} + 2>/dev/null | tr -d '${' | sort -u)"
while IFS= read -r e; do
  [ -n "$e" ] || continue
  found=""
  while IFS= read -r k; do [ "$(envname "$k")" = "$e" ] && found=1; done <<< "$keys"
  [ -n "$found" ] || v "RULE 6  a workflow reads \$$e, which no registry key produces"
done <<< "$envs"

# RULE 7: every registered key has a reader.
corpus="$(shipped | xargs cat 2>/dev/null)"
while IFS= read -r line; do
  [ -n "$line" ] || continue
  k="$(printf '%s' "$line" | cut -f1)"; apply="$(printf '%s' "$line" | cut -f5)"
  [ "$apply" != conf ] && continue
  # Here-strings, not `printf | grep -q`: grep -q exits at the first match, printf then dies
  # of SIGPIPE, and under pipefail a found key reads as missing.
  grep -qF -- "$k" <<< "$corpus" && continue
  grep -qF -- "$(envname "$k")" <<< "$corpus" && continue
  v "RULE 7  $k is in the registry and nothing shipped reads it: an option that does nothing"
done <<< "$body"

if [ "$n" -gt 0 ]; then
  printf '\n%s::error::check-options found %s violation(s)%s\n' "$RED" "$n" "$RST"; exit 1
fi
printf '  %soptions registry clean%s: %s option(s), every one valid, read, and registered\n' "$GREEN" "$RST" "$(printf '%s\n' "$keys" | grep -c .)"
