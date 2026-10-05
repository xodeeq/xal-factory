#!/usr/bin/env bash
#
# workflow-context.sh — refuse a workflow that cannot be dispatched.
#
# WHY THIS EXISTS, and it is the only reason. On 2026-09-22 pipeline S6 put
# `LEDGER: ${{ runner.temp }}/spend/costs.jsonl` in a JOB-LEVEL `env:` block. The file was
# valid YAML. It passed `scripts/check.sh` end to end, passed `step-order.sh`, passed
# `chain-check.sh`, passed CI, passed review and was MERGED TO main. The first dispatch after
# that returned:
#
#   HTTP 422: failed to parse workflow: Unrecognized named-value: 'runner'
#
# So the driver sat on `main` unable to start at all, and every gate this repo owns had said
# yes. The `runner` context exists only inside a step; a job-level `env:` is evaluated before
# any runner is assigned. The same is true of `steps` and `job`.
#
# WHAT MAKES THIS CLASS WORTH A GATE rather than a lesson. GitHub validates the expression at
# DISPATCH, not at push — so the feedback arrives only when someone tries to run the thing,
# which for a driver is the moment it was needed. And the failure is total: not a step that
# misbehaves, a workflow that cannot be created. It is the mirror of the 2026-09-20 finding,
# where a run WAS created and silently never executed; here nothing is created at all and the
# error is loud, but both share the shape that the gate chain has no opinion about whether a
# workflow can actually run.
#
# the owner's 2026-09-19 ruling is what makes this mandatory rather than optional: a failure that
# gets past the gates must tighten an existing gate, or add a new one only if genuinely
# necessary. No existing gate reads workflow expressions, and no existing one could have been
# widened to — step-order and chain-check are about ordering and credentials in named files.
#
# THE RULE IS NARROW ON PURPOSE. It is not a workflow linter; a real one (actionlint) would be
# an undeclared gate input, which is the defect class this repo re-learns most often. It
# checks exactly the three contexts that do not exist at job level, in exactly the block where
# using them is fatal.
#
# Exit: 0 fine · 3 REFUSED, named · 2 the file could not be read.

set -uo pipefail

WF=""
while [ $# -gt 0 ]; do
  case "$1" in
    (--workflow) WF="${2:-}"; shift 2 ;;
    (*) printf 'workflow-context: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$WF" ] || { printf 'workflow-context: --workflow is required\n' >&2; exit 2; }
[ -f "$WF" ] || { printf 'workflow-context: workflow not found: %s\n' "$WF" >&2; exit 2; }
grep -q '^jobs:' "$WF" || { printf 'workflow-context: %s declares no jobs\n' "$WF" >&2; exit 2; }

# A job-level `env:` sits at four spaces in these files (jobs: / <job>: / env:). Its entries
# are more indented; the block ends at the first line indented four or less. Deliberately
# textual: a YAML parser would be a dependency, and this is the one shape being judged.
bad="$(awk '
  # Four-space `env:` opens a job-level block. Anything shallower closes it.
  /^    env:[[:space:]]*$/            { inenv = 1; next }
  inenv && /^[[:space:]]{0,4}[^[:space:]]/ { inenv = 0 }
  inenv {
    if ($0 ~ /\$\{\{[^}]*(runner|steps|job)\./) {
      ctx = $0
      sub(/^[[:space:]]+/, "", ctx)
      printf("%d\t%s\n", NR, ctx)
    }
  }
' "$WF")"

if [ -n "$bad" ]; then
  printf 'REFUSED: %s uses a step-only context in a job-level env block.\n' "$WF" >&2
  printf '%s\n' "$bad" | while IFS="$(printf '\t')" read -r n txt; do
    printf '         line %s: %s\n' "$n" "$txt" >&2
  done
  printf '\n' >&2
  printf '         `runner`, `steps` and `job` do not exist when a job-level env block is\n' >&2
  printf '         evaluated — no runner has been assigned yet. GitHub rejects this at\n' >&2
  printf '         DISPATCH, not at push, with HTTP 422 "Unrecognized named-value", so the\n' >&2
  printf '         workflow cannot be created at all and every gate here still says yes.\n' >&2
  printf '         Measured on 2026-09-22: the driver reached `main` undispatchable.\n' >&2
  printf '         Use the environment variable inside the step ($RUNNER_TEMP), or move the\n' >&2
  printf '         assignment to the step that needs it.\n' >&2
  printf '::error title=Workflow context::%s cannot be dispatched\n' "$WF" >&2
  exit 3
fi

printf 'no step-only context in any job-level env block of %s\n' "$WF"
exit 0
