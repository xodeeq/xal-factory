#!/usr/bin/env bash
#
# scripts/smoke.sh: the post-deploy gate. A deploy is done when the live URL proves it,
# not when the host says the machine started.
#
# What every service proves, from the service conventions:
#   - liveness answers 200                                    (§2)
#   - readiness answers 200, so the hard dependencies answer  (§2)
#   - an unknown route answers 404 as an RFC 9457 problem document with code `not_found`,
#     served as application/problem+json                      (§10)
#
# What only this service can prove (its token lifecycle, its round trip) goes in
# scripts/smoke.d/*.sh, each run with the base URL as $1 and failing on a non-zero exit.
# A smoke that proves only health is a smoke that a broken service passes, so the first
# session that ships a real route adds its round trip there.
#
# Usage: scripts/smoke.sh <base-url>     Exit: 0 every check passed · 1 one failed · 2 cannot run
# Deps:  curl

set -uo pipefail
BASE="${1:-}"; [ -n "$BASE" ] || { echo "usage: $0 <base-url>" >&2; exit 2; }
BASE="${BASE%/}"
command -v curl >/dev/null 2>&1 || { echo "missing required dependency: curl" >&2; exit 2; }

if [ -t 1 ]; then RED=$'\033[31m'; GREEN=$'\033[32m'; RST=$'\033[0m'; else RED=""; GREEN=""; RST=""; fi
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); printf '  %s✔%s %s\n' "$GREEN" "$RST" "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  %s✗ %s%s\n' "$RED" "$1" "$RST"; }

code_of() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$BASE$1"; }

printf 'smoke: %s\n' "$BASE"
c="$(code_of /health/live)";  [ "$c" = 200 ] && ok "GET /health/live -> $c"  || bad "GET /health/live -> $c (expected 200)"
c="$(code_of /health/ready)"; [ "$c" = 200 ] && ok "GET /health/ready -> $c" || bad "GET /health/ready -> $c (expected 200)"

probe="/smoke-unknown-route-$$"
hdrs="$(mktemp)"; body="$(curl -s -D "$hdrs" --max-time 10 "$BASE$probe")"
c="$(awk 'toupper($1) ~ /^HTTP/ { code = $2 } END { print code }' "$hdrs")"
ct="$(awk 'tolower($1) == "content-type:" { print tolower($2) }' "$hdrs" | tr -d '\r;')"
rm -f "$hdrs"
[ "$c" = 404 ] && ok "GET $probe -> 404" || bad "GET $probe -> $c (expected 404)"
[ "$ct" = application/problem+json ] && ok "404 is application/problem+json" || bad "404 content type is '$ct' (expected application/problem+json)"
case "$body" in *':error:not_found"'*) ok "404 type ends :error:not_found" ;; *) bad "404 body does not carry a urn:<org>:<service>:error:not_found type" ;; esac

if [ -d scripts/smoke.d ]; then
  for s in scripts/smoke.d/*.sh; do
    [ -f "$s" ] || continue
    if bash "$s" "$BASE"; then ok "$s"; else bad "$s"; fi
  done
fi

printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
