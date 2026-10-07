#!/usr/bin/env bash
#
# gates/install.test.sh: the installer and the CLI, end to end, in a throwaway HOME.
#
# Proves: install.sh links the CLI; `init --yes` seeds an ops repo whose profile holds exactly
# the answers that differ from the defaults; a scripted non-default answer set (--set) lands;
# `seed` carries the profile's service options into a new service and its config.sh reads
# them; `config set` refuses an invalid value and an option of the other scope; `explain`
# knows every registry key. Nothing touches the network or GitHub.
#
# Exit: 0 every assertion held · 1 one did not · 2 cannot run
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)" || exit 2
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config"
export GIT_AUTHOR_NAME=gate GIT_AUTHOR_EMAIL=gate@example.invalid GIT_COMMITTER_NAME=gate GIT_COMMITTER_EMAIL=gate@example.invalid
mkdir -p "$HOME" "$T/ws"
pass=0; fail=0
check() { if eval "$2"; then printf '  ✔ %s\n' "$1"; pass=$((pass + 1)); else printf '  ✗ %s\n' "$1"; fail=$((fail + 1)); fi; }
CLI="$HOME/.local/bin/xal-factory"

bash "$ROOT/install.sh" --yes --no-plugin --no-init </dev/null >"$T/install.log" 2>&1
check "install.sh links the CLI" '[ -x "$CLI" ] && "$CLI" version | grep -q "xal-factory $(cat "$ROOT/VERSION")"'

( cd "$T/ws" && "$CLI" init --yes --name acme --owner acme --dir "$T/ws" \
    --set pipeline.chain=on --set plan.session_ceiling_usd=40 </dev/null >"$T/init.log" 2>&1 )
OPS="$T/ws/acme-ops"
check "init seeds the ops repo" '[ -f "$OPS/status/current.md" ] && [ -f "$OPS/.xal/factory.defaults" ]'
conf_keys() { sed 's/#.*//' "$1" | awk -F= 'NF > 1 { k = $1; gsub(/[ \t]/, "", k); print k }' | sort | tr '\n' ' '; }
check "the profile holds exactly the non-default answers and the ops repo" \
  '[ "$(conf_keys "$OPS/.xal/factory.conf")" = "factory.ops_repo pipeline.chain plan.session_ceiling_usd " ]'
check "init refuses an invalid --set" '! ( cd "$T/ws" && "$CLI" init --yes --name bad --dir "$T/ws" --set pipeline.auto_merge=yes </dev/null >/dev/null 2>&1 )'

( cd "$T/ws" && "$CLI" seed orders --module example.com/orders </dev/null >"$T/seed.log" 2>&1 )
SVC="$T/ws/orders"
check "seed creates the service from the profile" '[ -x "$SVC/scripts/driver/config.sh" ]'
check "the service's config reads the profile's values" \
  '[ "$(cd "$SVC" && ./scripts/driver/config.sh --get plan.session_ceiling_usd)" = 40 ] && [ "$(cd "$SVC" && ./scripts/driver/config.sh --get factory.ops_repo)" = acme/acme-ops ]'
check "and the defaults for everything else" '[ "$(cd "$SVC" && ./scripts/driver/config.sh --get pipeline.auto_merge)" = off ]'
check "seed pre-selects stack.default_lang and says the ADR still decides" 'grep -q "stack.default_lang" "$T/seed.log"'
check "config set refuses an invalid value" '! ( cd "$SVC" && "$CLI" config set pipeline.auto_merge yes >/dev/null 2>&1 )'
check "config set refuses an option of the other scope" '! ( cd "$SVC" && "$CLI" config set ops.idea_inbox off >/dev/null 2>&1 )'
check "config set writes a valid value" '( cd "$SVC" && "$CLI" config set deploy.target fly >/dev/null 2>&1 ) && [ "$(cd "$SVC" && ./scripts/driver/config.sh --get deploy.target)" = fly ]'
check "explain knows every registry key" '[ "$("$CLI" config explain | grep -c "^.*change later:")" = "$(awk -F"\t" "!/^#/ && NF && \$1 != \"key\"" "$ROOT/factory/options.tsv" | wc -l | tr -d " ")" ]'

printf '\n──────── %s passed · %s failed ────────\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || { printf 'init log:\n'; tail -20 "$T/init.log"; printf 'seed log:\n'; tail -20 "$T/seed.log"; exit 1; }
