#!/usr/bin/env bash
#
# fetch-spec.sh — put the ADMITTED SPEC where the session can read it, and refuse if it is
# not the document the plan says it is.
#
# WHY THIS EXISTS. The first driven session shipped without its spec. Its brief cited three
# requirement ids, and the session could not open a word of any of them: the admitted spec lives in
# the ops repo, `docs/spec/service.md` here is only a pointer, and the `gh api` read
# CLAUDE.md prescribes was blocked by the driver's own --allowedTools allowlist. The session
# built from its stack ADR and the vendored conventions instead. That is very likely right,
# and **very likely is not the standard a spec citation sets** — and no gate can tell a
# clause satisfied from a clause never read. Ruled 2026-09-18.
#
# WHY THE DRIVER FETCHES IT AND NOT THE SESSION. The alternative was handing the agent the
# `gh api` read, which puts a credential in the AGENT's tool surface rather than in the
# workflow around it. The blast radius of that is every repo the token reaches, and it gets
# worse once sessions auto-merge. Here the
# credential never reaches the agent: the workflow fetches, verifies, and drops a plain
# file in the workspace, and the session just opens it.
#
# AND IT CLOSES A RESIDUAL THE DRIVER ADR NAMED. The first version of that decision said the driver would NOT
# reconcile the spec digest, because doing so needs a read of the ops repo — an
# input, in the one component that must not have one. That reasoning was about `preflight`,
# which must be able to run with nothing. This is a different step: it is allowed an input
# because it IS the input. So the digest in the plan frontmatter, which until now nothing
# ever checked, is now verified on every run. A plan citing a spec that has changed under it
# stops the session rather than building against the wrong document.
#
# Usage:
#   fetch-spec.sh --plan docs/plan/plan.md --out .xal-spec/service.md
#   fetch-spec.sh --plan P --out F --from <path>   # read a local file instead of the API
#
# `--from` is not a test-only hatch: it is also how a developer with the sibling repo
# checked out runs this without a token, the same shape as XAL_PROCESS_DIR for gate 9.
#
# Exit:  0 fetched and verified
#        3 REFUSED — the digest does not match what the plan cites
#        2 CANNOT RUN — no plan, no citation fields, or the fetch itself failed
# Deps:  bash, shasum (or sha256sum), and `gh` unless --from is given.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER="$HERE/plan-read.sh"
PLAN="docs/plan/plan.md"
OUT=""
FROM=""

while [ $# -gt 0 ]; do
  case "$1" in
    --plan) PLAN="$2"; shift 2 ;;
    --out)  OUT="$2";  shift 2 ;;
    --from) FROM="$2"; shift 2 ;;
    *) printf 'fetch-spec.sh: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then RED=$'\033[31m'; GREEN=$'\033[32m'; RST=$'\033[0m'
else RED=""; GREEN=""; RST=""; fi

cannot_run() { printf '%sCANNOT RUN: %s%s\n' "$RED" "$1" "$RST" >&2; exit 2; }
refuse() {
  printf '%sREFUSED: %s%s\n' "$RED" "$1" "$RST"
  printf '::error title=Driver refused::%s\n' "$1"
  exit 3
}

[ -n "$OUT" ]  || cannot_run "--out is required"
[ -f "$PLAN" ] || cannot_run "plan not found: $PLAN"
[ -x "$READER" ] || cannot_run "plan-read.sh is missing at $READER"

# Same subshell discipline as preflight.sh: the assignment happens in THIS shell so the
# failure branch can exit the script rather than a subshell nobody is watching.
rd() { REPLY="$("$READER" --plan "$PLAN" "$@" 2>&1)" || cannot_run "plan-read.sh failed — $REPLY"; }

rd --fm spec_admitted_at; ADMITTED="$REPLY"
rd --fm spec_sha256;      WANT="$REPLY"
rd --fm spec_service;     SERVICE="$REPLY"
rd --fm spec_version;     VERSION="$REPLY"

[ -n "$ADMITTED" ] || cannot_run "the plan declares no spec_admitted_at"
[ -n "$WANT" ]     || cannot_run "the plan declares no spec_sha256 — there is nothing to verify against"

# spec_admitted_at is `<repo>:<path>` (ADR-0008 decision 3), never a bare path: the whole
# point of the citation is that the spec is somewhere else.
case "$ADMITTED" in
  *:*) SPEC_REPO="${ADMITTED%%:*}"; SPEC_PATH="${ADMITTED#*:}" ;;
  *) cannot_run "spec_admitted_at is '$ADMITTED', expected <repo>:<path>" ;;
esac

mkdir -p "$(dirname "$OUT")" || cannot_run "cannot create $(dirname "$OUT")"

if [ -n "$FROM" ]; then
  [ -f "$FROM" ] || cannot_run "--from names no file: $FROM"
  cp "$FROM" "$OUT" || cannot_run "cannot copy $FROM to $OUT"
  origin="$FROM"
else
  command -v gh >/dev/null 2>&1 || cannot_run "gh is not on PATH and --from was not given"
  # --jq '.content' plus base64 -d rather than the raw media type, so the bytes hashed here
  # are the bytes the API stores, not something a proxy may have re-encoded.
  if ! gh api "repos/xodeeq/${SPEC_REPO}/contents/${SPEC_PATH}" --jq '.content' 2>/dev/null | base64 -d > "$OUT" 2>/dev/null; then
    rm -f "$OUT"
    cannot_run "could not read ${SPEC_REPO}:${SPEC_PATH} — is the token set and does it grant read on that private repo?"
  fi
fi

[ -s "$OUT" ] || { rm -f "$OUT"; cannot_run "fetched an empty file for ${SPEC_REPO}:${SPEC_PATH}"; }

if command -v shasum >/dev/null 2>&1; then GOT="$(shasum -a 256 "$OUT" | cut -d' ' -f1)"
elif command -v sha256sum >/dev/null 2>&1; then GOT="$(sha256sum "$OUT" | cut -d' ' -f1)"
else rm -f "$OUT"; cannot_run "neither shasum nor sha256sum is available"; fi

if [ "$GOT" != "$WANT" ]; then
  rm -f "$OUT"
  refuse "the spec at ${SPEC_REPO}:${SPEC_PATH} is not the document this plan cites — plan says ${WANT}, fetched ${GOT}. The plan is about a different version of the spec and must be re-emitted; building against this would be building against something nobody approved."
fi

printf '%s✔ spec verified%s  %s %s\n' "$GREEN" "$RST" "$SERVICE" "$VERSION"
printf '  from      %s:%s (%s)\n' "$SPEC_REPO" "$SPEC_PATH" "${origin:-gh api}"
printf '  sha256    %s — matches the digest in the plan\n' "$GOT"
printf '  written   %s\n' "$OUT"
exit 0
