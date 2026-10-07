#!/usr/bin/env bash
#
# scripts/check.sh: the single source of truth for "the gates" in the factory's ops repo.
#
# CI (.github/workflows/gates.yml) invokes this exact script, so "green locally" equals
# "green in CI". To change a gate, change this script, not the workflow. The only thing a
# workflow may add is an INPUT a gate needs, declared in .xal/gate-inputs, which gate 0
# checks against every caller.
#
# THE SCRIPT IS THE LIST: read the gate names off the `gate` calls at the bottom.
#
# Usage:  scripts/check.sh     (from anywhere; it cd's to the repo root)
# Exit:   0 all gates passed · 1 a gate failed

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [ -t 1 ]; then BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YEL=$'\033[33m'; RST=$'\033[0m'
else BOLD=""; RED=""; GREEN=""; YEL=""; RST=""; fi

PASSED=()
FAILED=""

banner() { printf '\n%s━━ %s%s\n' "$BOLD" "$1" "$RST"; }
summary() {
  printf '\n%s──────── gate summary ────────%s\n' "$BOLD" "$RST"
  for p in "${PASSED[@]:-}"; do [ -n "$p" ] && printf '  %s✔%s %s\n' "$GREEN" "$RST" "$p"; done
  if [ -n "$FAILED" ]; then
    printf '  %s✗%s %s\n\n%sCHECK FAILED%s at: %s\n' "$RED" "$RST" "$FAILED" "$RED$BOLD" "$RST" "$FAILED"
  else
    printf '\n%sALL GATES PASSED%s\n' "$GREEN$BOLD" "$RST"
  fi
}
gate() {
  local name="$1"; shift
  banner "$name"
  if "$@"; then PASSED+=("$name"); printf '%s✔ %s%s\n' "$GREEN" "$name" "$RST"
  else FAILED="$name"; printf '%s✗ %s — FAILED%s\n' "$RED" "$name" "$RST"; summary; exit 1; fi
}

# --- gate 0: every input declared, every caller wired ----------------------------------
gate_inputs_step() {
  [ -f .xal/check-gate-inputs.sh ] || { printf '%s  .xal/check-gate-inputs.sh is missing%s\n' "$RED" "$RST"; return 1; }
  bash .xal/check-gate-inputs.sh
}

# --- spec intake -------------------------------------------------------------------------
# The fixtures run first, so "the rule is broken" is never mistaken for "a spec is broken".
spec_intake_fixtures_step() { bash gates/spec-intake.test.sh; }

# spec-intake-check refuses an EMPTY intake tree (exit 2), because a gate over nothing must
# not report green. A new ops repo has admitted nothing, and that state is consistent, not
# broken: no spec and no ledger record. So this step says so, loudly, and passes ONLY in that
# exact state. A spec with no record, or a record with no spec, still runs the real check and
# fails it.
spec_intake_step() {
  local specs records
  specs="$(find specs/admitted -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  records="$(grep -vE '^[[:space:]]*(#|$)' specs/ledger 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$specs" = 0 ] && [ "$records" = 0 ]; then
    printf '%s  nothing admitted yet: no spec under specs/admitted/ and no ledger record.%s\n' "$YEL" "$RST"
    printf '%s  This gate begins with the first admission (specs/README.md).%s\n' "$YEL" "$RST"
    return 0
  fi
  bash scripts/spec-intake-check.sh
}

# --- the plan critic's mechanical half ---------------------------------------------------
# Plans live in service repos; this repo holds the critic. Its fixtures prove every rule can
# fire, alone, and that a clean plan passes. The planner and plan-critic agents run it.
plan_critic_fixtures_step() { bash gates/plan-critic.test.sh; }

# --- the weekday nudge's input renders ---------------------------------------------------
# A commit that empties next_action would otherwise be green on its PR and fail only when
# the nudge fires. python3 is the one input (status-render.sh parses with it).
status_render_step() {
  if ! command -v python3 >/dev/null 2>&1; then
    if [ "${CI:-}" = "true" ]; then printf '%spython3 is required in CI for the status render.%s\n' "$RED" "$RST"; return 1; fi
    printf '%s⚠ python3 unavailable: SKIPPING the status-render gate (mandatory in CI).%s\n' "$YEL" "$RST"
    return 0
  fi
  bash gates/status-render.test.sh
}

gate "gate inputs declared + every caller wired"           gate_inputs_step
gate "spec-intake fixtures (proven able to fail)"          spec_intake_fixtures_step
gate "spec-intake (every admitted spec, verbatim)"         spec_intake_step
gate "plan-critic fixtures (per-rule proof)"               plan_critic_fixtures_step
gate "status renders (the weekday nudge's input)"          status_render_step

summary
