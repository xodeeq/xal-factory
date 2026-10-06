#!/usr/bin/env bash
#
# factory/lib.sh: reading the options registry (factory/options.tsv), shared by the seeders
# and bin/xal-factory so the registry is parsed one way. Source it; it defines functions only.
#
# The registry is tab-separated with a header row; `#` lines are comments. Columns:
#   1 key  2 default  3 choices  4 scope  5 apply  6 ask  7 what  8 later

FACTORY_ROOT="${FACTORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
OPTIONS="$FACTORY_ROOT/factory/options.tsv"

# Every option row, header and comments removed.
opt_rows() { awk -F'\t' '!/^#/ && NF && $1 != "key"' "$OPTIONS"; }

# One column of one key's row (column numbers above). Empty when the key is unknown.
opt_field() { awk -F'\t' -v k="$1" -v c="$2" '!/^#/ && $1 == k { print $c; exit }' "$OPTIONS"; }

opt_known() { [ -n "$(opt_field "$1" 1)" ]; }

# Is <value> allowed for <key>? Closed sets, positive integers, or free text.
opt_valid() {
  local choices; choices="$(opt_field "$1" 3)"
  case "$choices" in
    '*') [ -n "$2" ] ;;
    int) printf '%s' "$2" | grep -qE '^[1-9][0-9]*$' ;;
    *)   printf '|%s|' "$choices" | grep -qF "|$2|" ;;
  esac
}

# Write the defaults file a seeded repo reads (scripts/driver/config.sh): key<TAB>default for
# every option in the given scopes, with <VERSION> filled in. Usage: opt_write_defaults
# <scopes, e.g. "service" or "service ops"> <version> <out-file>
opt_write_defaults() {
  local scopes="$1" version="$2" out="$3"
  {
    printf '# .xal/factory.defaults: the default for every factory option this repo knows,\n'
    printf '# written by the seeder from factory/options.tsv at process %s. Do not edit:\n' "$version"
    printf '# set a value in .xal/factory.conf instead. `xal-factory config explain <key>`.\n'
    opt_rows | awk -F'\t' -v s=" $scopes " -v v="$version" \
      'index(s, " " $4 " ") { d = $2; gsub(/<VERSION>/, v, d); print $1 "\t" d }'
  } > "$out"
}

# Copy into <conf> every key of <scope> that <profile> sets, as `key = value` lines. The ops
# repo's conf is the factory profile; a new service starts from it.
opt_apply_profile() {
  local profile="$1" scope="$2" conf="$3" k v
  [ -f "$profile" ] || return 0
  sed 's/#.*//' "$profile" | awk -F= 'NF > 1 { k = $1; v = substr($0, index($0, "=") + 1); gsub(/^[ \t]+|[ \t]+$/, "", k); gsub(/^[ \t]+|[ \t]+$/, "", v); if (v != "") print k "\t" v }' \
    | while IFS=$'\t' read -r k v; do
        [ "$(opt_field "$k" 4)" = "$scope" ] || continue
        [ "$k" = factory.ops_repo ] && continue
        printf '%s = %s\n' "$k" "$v" >> "$conf"
      done
}
