#!/usr/bin/env bash
#
# config.sh: read this repo's factory configuration, with a default for every key.
#
# WHY A FILE IN THE REPO RATHER THAN REPOSITORY VARIABLES. A setting clicked into a forge's
# settings page is invisible to review, absent from history and lost with the repo. This
# file is reviewed like code, and the merge decision protects it like the gate (.xal/ is a
# protected path), so a session cannot widen its own autonomy. The two knobs a workflow needs
# before any step runs (`runs-on`, `timeout-minutes`) cannot read a file, and stay repository
# variables with inline defaults. They are the only exceptions.
#
# THE FORMAT. `.xal/factory.conf` holds `key = value` lines. `#` starts a comment, blank lines
# are ignored, and a key not in the table below is an error rather than a silent no-op: a
# misspelt key that falls back to its default reads as configured and is not.
#
# EVERY KEY HAS A DEFAULT, OR SAYS WHY IT CANNOT. A repo whose conf sets nothing runs the
# default profile. `factory.ops_repo` is the one required key: there is no repository a
# script could guess. The seeder writes it.
#
# Usage:
#   config.sh --get <key>       print one value (the conf's, else the default)
#   config.sh --emit            print FACTORY_<KEY>=<value> for every key, for $GITHUB_ENV
#                               (dots become underscores; a leading `factory.` is dropped)
#   config.sh --list            print `key = value  (default|set)` for every key
#   config.sh --keys            print every known key with its default, tab-separated
#   [--file <path>]             read this conf instead of .xal/factory.conf
# Exit: 0 ok · 2 cannot run (unknown key, malformed line, required key unset)

set -uo pipefail

FILE=".xal/factory.conf"
MODE=""
KEY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --file) FILE="${2:-}"; shift 2 ;;
    --get)  MODE=get; KEY="${2:-}"; shift 2 ;;
    --emit) MODE=emit; shift ;;
    --list) MODE=list; shift ;;
    --keys) MODE=keys; shift ;;
    *) printf 'config: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done
[ -n "$MODE" ] || { printf 'config: one of --get, --emit, --list, --keys is required\n' >&2; exit 2; }

# key | default. `required` means no default can exist; the reason is in the comment beside it.
# Kept in step with the factory's options registry; the factory's own gate diffs the two.
DEFAULTS='factory.ops_repo|required
factory.process_repo|xodeeq/xal-factory
factory.escalation_label|needs-human
models.driver|claude-opus-5-5
models.reader|claude-opus-5-5
budget.driver_max_turns|200
budget.reader_max_turns|80
reader.ref|xal-factory--v<VERSION>
ops.ledger_path|status/costs.jsonl'
# factory.ops_repo: the owner/name of the ops repo holding admitted specs and the spend
#   ledger. Required because no script can know which repository that is.

known() { printf '%s\n' "$DEFAULTS" | cut -d'|' -f1 | grep -qx -- "$1"; }
default_of() { printf '%s\n' "$DEFAULTS" | awk -F'|' -v k="$1" '$1 == k { print $2 }'; }

# The conf's value for a key, or nothing. A malformed line or an unknown key is fatal.
conf_value() {
  [ -f "$FILE" ] || return 0
  awk -v want="$1" -v file="$FILE" '
    { sub(/#.*/, ""); gsub(/^[ \t]+|[ \t]+$/, "") }
    $0 == "" { next }
    index($0, "=") == 0 { printf "config: %s:%d: not a key = value line\n", file, NR > "/dev/stderr"; bad = 1; next }
    {
      k = substr($0, 1, index($0, "=") - 1); v = substr($0, index($0, "=") + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", k); gsub(/^[ \t]+|[ \t]+$/, "", v)
      if (k == want) val = v
    }
    END { if (bad) exit 2; if (val != "") print val }' "$FILE"
}

# Every key the conf sets must be known.
check_conf_keys() {
  [ -f "$FILE" ] || return 0
  local k bad=0
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    known "$k" || { printf 'config: %s sets unknown key %s\n' "$FILE" "$k" >&2; bad=1; }
  done < <(sed 's/#.*//' "$FILE" | awk -F= 'NF > 1 { gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1 }')
  return "$bad"
}

value_of() {
  local v
  v="$(conf_value "$1")" || exit 2
  [ -n "$v" ] || v="$(default_of "$1")"
  if [ "$v" = "required" ]; then
    printf 'config: %s is required and %s does not set it\n' "$1" "$FILE" >&2
    return 2
  fi
  printf '%s\n' "$v"
}

check_conf_keys || exit 2

case "$MODE" in
  get)
    known "$KEY" || { printf 'config: unknown key %s\n' "$KEY" >&2; exit 2; }
    value_of "$KEY" || exit 2 ;;
  emit)
    while IFS='|' read -r k _; do
      v="$(value_of "$k")" || exit 2
      # factory.ops_repo becomes FACTORY_OPS_REPO, models.driver FACTORY_MODELS_DRIVER.
      printf 'FACTORY_%s=%s\n' "$(printf '%s' "${k#factory.}" | tr '[:lower:].' '[:upper:]_')" "$v"
    done <<< "$DEFAULTS" ;;
  list)
    while IFS='|' read -r k d; do
      v="$(conf_value "$k")" || exit 2
      if [ -n "$v" ]; then printf '%s = %s  (set)\n' "$k" "$v"
      else printf '%s = %s  (default)\n' "$k" "$d"; fi
    done <<< "$DEFAULTS" ;;
  keys)
    printf '%s\n' "$DEFAULTS" | tr '|' '\t' ;;
esac
