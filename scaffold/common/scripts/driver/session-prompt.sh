#!/usr/bin/env bash
#
# session-prompt.sh — compose the headless prompt for ONE session, from the plan.
#
# WHY THIS IS A SCRIPT AND NOT A HEREDOC IN driver.yml -----------------------------------
#
# Two reasons, and the second is the one that matters. First, workflow YAML cannot be run
# locally, so a prompt built there is a prompt nobody can read before it is sent. Second,
# and load-bearing: THE AGENT MUST NOT CHOOSE ITS OWN SCOPE. If the driver handed over the
# whole plan and said "run session S1", the session's boundaries would be whatever the
# model decided they were on the day. Everything below is extracted verbatim from the
# approved plan — the scope, the artifacts, the gate, the must_not clauses — so the brief
# the agent receives is the artifact the owner approved, not a paraphrase of it.
#
# WHAT IS ADDED ON TOP OF THE PLAN, AND WHY EACH LINE EARNS ITS PLACE --------------------
#
# The plan's own `prompt:` block assumes a reader who has this repo's CLAUDE.md in context.
# A headless run in a fresh checkout does not, reliably, so the standing laws that would
# otherwise be silently dropped are restated: strict TDD, the read-only platform spec, the
# coverage ratchet, spec H-15, and "commit artifacts as proof; self-report is not evidence".
# Nothing here grants anything the plan does not already grant.
#
# THE SPEC. `--spec` names a file the DRIVER has already fetched and verified against the
# digest in the plan (scripts/driver/fetch-spec.sh). Without it the prompt says plainly
# that the spec is unavailable rather than citing clauses the session cannot open — which
# is exactly what plan S1 did, and it is why this argument exists.
#
# Usage:  session-prompt.sh --session S1 [--plan docs/plan/plan.md] [--spec PATH]
# Exit:   0 composed · 2 the plan or the session could not be read
# Deps:   bash, and scripts/driver/plan-read.sh.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
READER="$HERE/plan-read.sh"

PLAN="docs/plan/plan.md"
SID=""
SPEC=""

while [ $# -gt 0 ]; do
  case "$1" in
    --plan)    PLAN="$2"; shift 2 ;;
    --session) SID="$2";  shift 2 ;;
    --spec)    SPEC="$2"; shift 2 ;;
    *) printf 'session-prompt.sh: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

cannot_run() { printf 'CANNOT RUN: %s\n' "$1" >&2; exit 2; }

[ -n "$SID" ]  || cannot_run "--session is required"
[ -f "$PLAN" ] || cannot_run "plan not found: $PLAN"
[ -x "$READER" ] || cannot_run "plan-read.sh is missing at $READER"

# Same subshell trap preflight.sh documents: the assignment happens in THIS shell so the
# failure branch can exit the script rather than a subshell nobody is watching.
rd() { REPLY="$("$READER" --plan "$PLAN" "$@" 2>&1)" || cannot_run "plan-read.sh failed — $REPLY"; }

rd --sessions
printf '%s\n' "$REPLY" | grep -qx -- "$SID" || cannot_run "no session '$SID' in $PLAN"

rd --fm plan_id;   PLAN_ID="$REPLY"
rd --fm service;   SERVICE="$REPLY"
rd --session "$SID" --field risk_class;  RISK="$REPLY"
rd --session "$SID" --field scope_in;    SCOPE_IN="$REPLY"
rd --session "$SID" --field scope_out;   SCOPE_OUT="$REPLY"
rd --session "$SID" --field gate.command; GATE_CMD="$REPLY"
rd --session "$SID" --field gate.must_not; MUST_NOT="$REPLY"
rd --session "$SID" --field artifact;    ARTIFACTS="$REPLY"
rd --session "$SID" --prompt;            BODY="$REPLY"

[ -n "$GATE_CMD" ]  || cannot_run "$SID declares no gate command — refusing to brief a session with no done-criterion"
[ -n "$BODY" ]      || cannot_run "$SID declares no prompt — refusing to brief a session with no instructions"
[ -n "$ARTIFACTS" ] || cannot_run "$SID declares no artifacts — refusing to brief a session with nothing to produce"

if [ -n "$SPEC" ] && [ -f "$SPEC" ]; then
  rd --fm spec_service; sp_svc="$REPLY"
  rd --fm spec_version; sp_ver="$REPLY"
  rd --fm spec_sha256;  sp_sha="$REPLY"
  SPEC_BLOCK="## The spec

The admitted spec \`$sp_svc\` $sp_ver is at **\`$SPEC\`** in this workspace. **Read the
clauses your brief cites.** The driver fetched it and verified its sha256 against the
digest in the plan ($sp_sha), so it is the exact document this plan was written against —
not a copy, not a later revision.

It is READ-ONLY and is not part of this repository: it is fetched per run and never
committed. Do not edit it, and do not add it to a commit."
else
  # Say it, rather than cite clauses the session cannot open. Plan S1 was built this way
  # without anyone noticing until the session logged it itself.
  SPEC_BLOCK="## The spec is NOT available to you in this run

Your brief below cites spec clauses by number. **You cannot read them** — the admitted
spec is in a private repository and was not fetched for this run. Work from
\`docs/adr/0001-stack-selection.md\` and the vendored \`docs/process/\` conventions,
and **say explicitly in your summary which cited clauses you could not read**, so that the
gap is visible to the person reviewing this rather than invisible in green tests."
fi

cat <<PROMPT
You are running session $SID of the approved multi-session plan \`$PLAN_ID\` for the
\`$SERVICE\` service, headless, in a fresh checkout of this repository on a branch that has
already been created for you. Do the work of this session and nothing else.

Read \`CLAUDE.md\` at the repository root first. It is this service's standing law and it
outranks anything convenient.

${SPEC_BLOCK}

## Session $SID — risk class: $RISK

### In scope
$SCOPE_IN

### Out of scope — do not touch these, even if they look wrong
$SCOPE_OUT

### Artifacts that must exist when you are done (exact paths)
$(printf '%s\n' "$ARTIFACTS" | sed 's/^/- /')

### The gate — its exit code decides whether this session passed
\`\`\`
$GATE_CMD
\`\`\`

### Boundary conditions the gate also checks (must_not)
$MUST_NOT

### The session brief, verbatim from the approved plan
$BODY

## Standing laws that apply to every session in this repository

- **Strict TDD, always.** RED → GREEN → REFACTOR. The failing test precedes the code that
  satisfies it. This is a law, not a preference.
- **A coverage floor is a ratchet.** Set each new package's floor from the MEASURED
  percentage of a green build, and never lower an existing one.
- **Never edit anything under \`docs/process/\`.** It is vendored read-only; a local edit
  makes the drift gate permanently red and cannot be "fixed" here.
- **No secrets in code** — names only, read from the environment.
- **Agents never seed real data.** No account, organization, membership, record or
  credential is created outside a test fixture; every such act in a real deployment is a
  person's (the ops repo's CLAUDE.md P6, and this service's spec where it says so).
- **Do not edit \`docs/plan/plan.md\`.** The driver writes this session's status and
  evidence after the gate runs; a session that writes its own result is reporting on
  itself.
- **Do not open, merge or close a pull request, and do not push.** The driver does both.
- **Commit artifacts as proof; self-report is not evidence.** Leave your work in the
  working tree. Your summary decides nothing: the driver runs the gate above and the gate's
  exit code is what is recorded.

Run the gate yourself before you finish, and fix what it reports. If you cannot make it
green, stop and say exactly which gate fired and why — do not weaken the gate, lower a
floor, delete a test, or narrow the scope of an assertion to get past it.
PROMPT
exit 0
