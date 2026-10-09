#!/usr/bin/env bash
#
# ci-verdict.sh — the conclusion of CI's gate job on one commit, read through the Actions API.
#
# WHY NOT THE CHECKS API. merge.yml and chain.yml used to read
# `commits/<sha>/check-runs`. GitHub offers no Checks permission to fine-grained personal
# access tokens, so with a fine-grained FACTORY_WRITE_TOKEN that read was a 403 and merge
# refused every session (the factory's first live proof, 2026-10-08). The same verdict is
# reachable through Actions: the latest run of the CI workflow for the commit, then its gate
# job by name. That needs only Actions: Read, which a fine-grained token can hold.
#
# THE ONE-WAY RULE. Stdout is the gate job's conclusion (`success`, `failure`, `cancelled`, …)
# once that job has completed, and EMPTY while CI has not run or is still running, so a
# caller's wait loop keeps waiting. If the API cannot be read at all, stdout is `unreadable`:
# non-empty, so the wait ends at once rather than timing out on a permission, and never
# `success`, so the caller fails closed. The reason goes to stderr, for the run's log.
#
# EXIT CODES — the driver's convention:
#   0  read: a conclusion, or empty for not yet
#   4  unreadable: `unreadable` on stdout, the reason on stderr
#   2  CANNOT RUN — bad arguments, or gh is absent
#
# Usage: ci-verdict.sh --repo <owner>/<repo> --sha <sha> [--job "Gates (scripts/check.sh)"] [--workflow ci.yml]
# Deps: bash, gh (with GH_TOKEN holding Actions: Read on the repo).

set -uo pipefail

REPO="" SHA="" JOB="Gates (scripts/check.sh)" WORKFLOW="ci.yml"
while [ $# -gt 0 ]; do
  case "$1" in
    (--repo)     REPO="${2:-}"; shift 2 ;;
    (--sha)      SHA="${2:-}"; shift 2 ;;
    (--job)      JOB="${2:-}"; shift 2 ;;
    (--workflow) WORKFLOW="${2:-}"; shift 2 ;;
    (*) printf 'ci-verdict: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done
[ -n "$REPO" ] && [ -n "$SHA" ] || { printf 'ci-verdict: --repo and --sha are required\n' >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { printf 'ci-verdict: gh is not on PATH\n' >&2; exit 2; }

unreadable() {
  printf 'unreadable'
  printf 'ci-verdict: cannot read CI for %s at %s: %s\n' "$REPO" "${SHA:0:7}" "$1" >&2
  printf '            FACTORY_WRITE_TOKEN needs Actions: Read on %s (https://factory.getxal.com/credentials/)\n' "$REPO" >&2
  exit 4
}

# The newest run of the CI workflow for this commit. A re-run keeps its id and its jobs
# endpoint answers for the latest attempt, so "newest by creation" is the run that counts.
if ! run="$(gh api "repos/$REPO/actions/workflows/$WORKFLOW/runs?head_sha=$SHA&per_page=20" \
              --jq '.workflow_runs | sort_by(.created_at) | last | .id // empty' 2>&1)"; then
  unreadable "$run"
fi
[ -n "$run" ] || exit 0   # CI has not started on this commit yet

if ! concl="$(gh api "repos/$REPO/actions/runs/$run/jobs?per_page=100" \
                --jq "[.jobs[] | select(.name == \"$JOB\")] | last | select(.status == \"completed\") | .conclusion // empty" 2>&1)"; then
  unreadable "$concl"
fi
printf '%s' "$concl"
