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
# RULE 2, ADDED 2026-10-18: AN EXIT CODE CAPTURED WHERE `bash -e` HAS ALREADY KILLED THE STEP.
# A `run:` step with no `shell:` runs as `bash -e {0}`, and `set -uo pipefail` at its top does
# NOT turn -e off. So in
#
#   decision="$(./scripts/driver/merge-decision.sh …)"; rc=$?
#
# a non-zero exit ends the step at the assignment, and `rc=$?` never runs. merge.yml was
# written as if there were no -e ("a refusal's exit 3 must be caught, not fatal"), so a
# designed refusal turned the job RED with exit 3, posted nothing on the PR, set no label and
# put nothing on the board, instead of the designed GREEN stop. Measured in the source estate,
# run 39105618864. chain.yml's "plan complete" exit 4 had the same shape. Every gate said yes,
# for the same reason as rule 1: no gate reads what a workflow step will DO.
#
# The only capture -e does not act on is the right-hand side of `||`:
#
#   rc=0; decision="$(…)" || rc=$?
#
# so any `name=$?` that is not directly after `||` is refused, whatever the shell. That is
# stricter than needed for a step with an explicit `shell: bash {0}`, and deliberately so: the
# `||` form is correct under either shell, and it keeps -e as the safety net for every command
# the step did not check by hand. Comment lines are ignored, so the explanation can stay.
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

# --- rule 2: an exit code captured after -e has already acted -----------------------------
# Textual on purpose, like rule 1. Comment lines are skipped; on every other line, each
# `|| name=$?` is removed first, and any `name=$?` left over is one -e reaches before it does.
killed="$(awk '
  /^[[:space:]]*#/ { next }
  /[A-Za-z_][A-Za-z0-9_]*=\$\?/ {
    line = $0
    gsub(/\|\|[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=\$\?/, "", line)
    if (line ~ /[A-Za-z_][A-Za-z0-9_]*=\$\?/) {
      txt = $0
      sub(/^[[:space:]]+/, "", txt)
      printf("%d\t%s\n", NR, txt)
    }
  }
' "$WF")"

if [ -n "$killed" ]; then
  printf 'REFUSED: %s captures an exit code that bash -e never lets it see.\n' "$WF" >&2
  printf '%s\n' "$killed" | while IFS="$(printf '\t')" read -r n txt; do
    printf '         line %s: %s\n' "$n" "$txt" >&2
  done
  printf '\n' >&2
  printf '         A run: step with no shell: is `bash -e {0}`; `set -uo pipefail` does not undo\n' >&2
  printf '         the -e. A non-zero exit ends the step BEFORE `name=$?` runs, so a designed\n' >&2
  printf '         refusal (exit 3) or completion (exit 4) becomes a red job and every line\n' >&2
  printf '         meant to handle it is skipped. Measured 2026-10-18, source-estate run\n' >&2
  printf '         39105618864: merge.yml went red instead of stopping for a person.\n' >&2
  printf '         Capture it where -e does not act:  rc=0; out="$(cmd)" || rc=$?\n' >&2
  printf '::error title=Workflow exit code::%s captures an exit code after bash -e has acted\n' "$WF" >&2
  exit 3
fi

printf 'no step-only context in any job-level env block of %s, and no exit code captured after bash -e has acted\n' "$WF"
exit 0
