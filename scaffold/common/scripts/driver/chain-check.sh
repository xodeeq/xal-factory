#!/usr/bin/env bash
#
# chain-check.sh — the properties chain.yml must hold, asserted rather than trusted.
#
# WHY A STATIC CHECKER AND NOT A TEST. The chain only does anything when a real PR merges or a
# real driver run ends, so the interesting behaviour is unreachable from a fixture. What IS
# checkable is the shape, and every rule below is one whose violation fails SILENTLY — which
# is the class this estate keeps paying for. A chain that quietly never runs looks exactly
# like a plan with nothing left to do.
#
# THE RULES, and the failure each one prevents:
#
#   1. The dispatch uses a PAT, never GITHUB_TOKEN. GitHub's recursion guard means a workflow
#      dispatched with GITHUB_TOKEN is created and never runs. No error, no annotation: the
#      chain simply stops. This is the same family as the 2026-09-20 finding, where a push
#      attributed to github-actions[bot] left CI `action_required` and the head unjudged.
#
#   2. The chain never merges. Since pipeline S7 merging is merge.yml's, decided by
#      merge-decision.sh (ADR-0008 in the factory). A `gh pr merge` appearing here would be a
#      second merge site that none of merge.yml's conditions — CI green, the reader clean,
#      the head current, the risk class admitted — would ever be asked about.
#
#   3. The chain does not read `autonomy_level`. merge-decision.sh is its only reader. A
#      chain that read it would be answering "may this land?" — merge.yml's question — in
#      the one workflow that is supposed to ask only "what runs next?".
#
#   4. `main` is checked BEFORE the dispatch, as an ORDERING rather than a presence. "The file
#      reads the verdict" was true of every draft; what must hold is that the verdict is
#      read before anything is started on top of it. The read is scripts/driver/ci-verdict.sh,
#      and a read through the Checks API (`check-runs`) is refused: fine-grained tokens have
#      no Checks permission, so it is a 403 under one (the first live proof, 2026-10-08).
#
#   5. Escalation writes the plan AND stops. A chain that escalated and carried on would leave
#      the escalation as a note nobody has to read — decision 5's ruled shape is escalate and
#      halt, so a non-zero exit after the escalation is part of the contract.
#
# Exit codes follow the driver's convention: 0 fine · 3 REFUSED with a named reason · 2 the
# file could not be read. A crashing bash script exits 1/127, so a decision is never a crash.

set -uo pipefail

WF=""
while [ $# -gt 0 ]; do
  case "$1" in
    (--workflow) WF="${2:-}"; shift 2 ;;
    (*) printf 'chain-check: unknown argument %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$WF" ] || { printf 'chain-check: --workflow is required\n' >&2; exit 2; }
[ -f "$WF" ] || { printf 'chain-check: workflow not found: %s\n' "$WF" >&2; exit 2; }

# A file with no dispatch is not a chain, and judging one would be judging the wrong artifact.
if ! grep -q 'gh workflow run driver.yml' "$WF"; then
  printf 'chain-check: %s never dispatches driver.yml — this file is not a chain\n' "$WF" >&2
  exit 2
fi

line_of() { grep -n -- "$1" "$WF" 2>/dev/null | head -1 | cut -d: -f1; }

# --- 1. the dispatch credential ----------------------------------------------------------
# Read the env block that governs each dispatch by looking backwards from it for the nearest
# GH_TOKEN assignment. A dispatch with no GH_TOKEN in scope at all is the same defect.
while IFS=: read -r n _; do
  [ -n "$n" ] || continue
  tok="$(head -n "$n" "$WF" | grep -E 'GH_TOKEN:' | tail -1)"
  case "$tok" in
    (*FACTORY_WRITE_TOKEN*) ;;
    ("")
      printf 'REFUSED: the dispatch at line %s has no GH_TOKEN in scope.\n' "$n" >&2
      printf '::error title=Chain shape::dispatch at line %s has no credential\n' "$n" >&2
      exit 3 ;;
    (*)
      printf 'REFUSED: the dispatch at line %s runs under %s\n' "$n" "$(printf '%s' "$tok" | tr -s ' ')" >&2
      printf '         A workflow dispatched with GITHUB_TOKEN is created and NEVER RUNS —\n' >&2
      printf '         GitHub refuses to let a token trigger more work. There is no error and\n' >&2
      printf '         no annotation; the chain just stops. Dispatch with the PAT.\n' >&2
      printf '::error title=Chain shape::dispatch at line %s would silently never run\n' "$n" >&2
      exit 3 ;;
  esac
done < <(grep -n 'gh workflow run driver.yml' "$WF")

# CODE ONLY, NOT PROSE. The two content rules below read a comment-stripped view of the file.
# The first version of rule 3 fired on this workflow's own header — the paragraph explaining
# that `autonomy_level` stays unread until S7 contains the words `autonomy_level`. A rule that
# fires on the comment describing it is a rule whose cheapest fix is deleting the explanation,
# which is the opposite of what it is for. A line whose first non-space character is `#` is a
# comment; that is true of every line in these workflows and is the whole of the heuristic.
CODE="$(grep -vE '^[[:space:]]*#' "$WF")"

# --- 2. the chain never merges -----------------------------------------------------------
if printf '%s\n' "$CODE" | grep -qE 'gh pr merge|--auto|--merge\b'; then
  printf 'REFUSED: %s merges something. Merging is merge.yml'"'"'s (pipeline S7, ADR-0010), where\n' "$WF" >&2
  printf '         merge-decision.sh asks every condition a merge must meet; a merge here asks none.\n' >&2
  printf '::error title=Chain shape::the chain must not merge\n' >&2
  exit 3
fi

# --- 3. autonomy_level stays unread ------------------------------------------------------
if printf '%s\n' "$CODE" | grep -q 'autonomy_level'; then
  printf 'REFUSED: %s reads autonomy_level, which only merge-decision.sh may read.\n' "$WF" >&2
  printf '::error title=Chain shape::autonomy_level is merge.yml'"'"'s question, not the chain'"'"'s\n' >&2
  exit 3
fi

# --- 4. main is judged before anything is built on it ------------------------------------
CHECKS_API="$(grep -n -- 'check-runs' "$WF" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | head -1 | cut -d: -f1)"
if [ -n "$CHECKS_API" ]; then
  printf 'REFUSED: %s reads a gate verdict through the Checks API at line %s.\n' "$WF" "$CHECKS_API" >&2
  printf '         GitHub gives fine-grained tokens no Checks permission, so under a\n' >&2
  printf '         fine-grained FACTORY_WRITE_TOKEN it is a 403 and the chain never advances.\n' >&2
  printf '         Read it with scripts/driver/ci-verdict.sh (the Actions API).\n' >&2
  printf '::error title=Chain shape::gate verdict read through the Checks API\n' >&2
  exit 3
fi
GREEN_CHECK="$(line_of 'ci-verdict\.sh --')"
DISPATCH="$(line_of 'gh workflow run driver.yml')"
if [ -z "$GREEN_CHECK" ]; then
  printf 'REFUSED: %s never reads a gate verdict for main.\n' "$WF" >&2
  printf '         preflight reads `passed` out of the plan and has never asked whether the\n' >&2
  printf '         base is green; with no branch protection here, nothing else asks either.\n' >&2
  printf '::error title=Chain shape::no main-is-green check\n' >&2
  exit 3
fi
if [ "$GREEN_CHECK" -gt "$DISPATCH" ]; then
  printf 'REFUSED: main is judged at line %s but a session is dispatched at line %s.\n' \
    "$GREEN_CHECK" "$DISPATCH" >&2
  printf '         Reading the verdict after starting work on top of it is not a check.\n' >&2
  printf '::error title=Chain shape::main is judged after the dispatch\n' >&2
  exit 3
fi

# --- 6. the main-verdict check must WAIT, not read once ----------------------------------
#
# Rule 4 asserts the check EXISTS and precedes the dispatch. Both were true of the version
# that shipped on 2026-09-22, and it was still a permanent no-op: it read the verdict once,
# immediately after the merge that triggered it, while CI on that same commit was still
# starting. "Refuse when unjudged" then means refuse EVERY time.
#
# So presence and ordering are not enough — the read has to be able to outlast the CI run it
# is asking about. Checked as the presence of a bounded retry around the read, because that is
# the property; a single `gh api` call cannot be made correct by any amount of ordering.
GREEN_LINE="$(line_of 'ci-verdict\.sh --')"
if [ -n "$GREEN_LINE" ]; then
  window="$(awk -v s="$GREEN_LINE" 'NR >= s - 12 && NR <= s + 12' "$WF")"
  if ! printf '%s\n' "$window" | grep -qE 'for .*seq |while .*; do|until '; then
    printf 'REFUSED: the gate verdict at line %s is read once, with no retry around it.\n' "$GREEN_LINE" >&2
    printf '         The chain fires on a merge and CI on that merge commit starts at the same\n' >&2
    printf '         instant, so a single read finds no verdict and refuses EVERY time — the\n' >&2
    printf '         rule correct, the chain dead. Measured on run 35774727222.\n' >&2
    printf '::error title=Chain shape::the main-verdict check does not wait\n' >&2
    exit 3
  fi
fi

# --- 7. the session must not be recovered from head_branch -------------------------------
#
# A `workflow_run` event does not carry the inputs that started the run, and for a dispatched
# run `head_branch` is the ref it was dispatched ON — `main`, every time. A retry job reading
# it refuses every run it is handed, so retry and escalation are unreachable rather than
# untested. Measured on run 35777940382; the code carried a comment claiming it "reads a fact
# rather than a guess", which it did — the wrong fact, confidently and self-consistently.
if printf '%s\n' "$CODE" | grep -q 'workflow_run.head_branch'; then
  printf 'REFUSED: %s recovers the session from workflow_run.head_branch.\n' "$WF" >&2
  printf '         For a dispatched run that is `main`, never the session branch — so the\n' >&2
  printf '         retry path refuses every run and escalation can never be reached.\n' >&2
  printf '         The session survives a dispatch only through driver.yml`s run-name,\n' >&2
  printf '         which arrives as workflow_run.display_title.\n' >&2
  printf '::error title=Chain shape::session recovered from the wrong field\n' >&2
  exit 3
fi

# --- 8. a plan AMENDMENT must not look like a session merge ------------------------------
#
# Session branches are `plan/<plan-id>/s<N>`; plan amendments are branches like
# `plan/session-ceiling-70`. A guard testing only the `plan/` prefix matches both, and on
# 2026-09-22 merging the ceiling amendment dispatched a real session nobody asked for. A
# GitHub expression cannot express the precise test — no regex, and the plan id is not in
# scope — so it has to be a step that reads the plan.
if printf '%s\n' "$CODE" | grep -q "startsWith(github.event.pull_request.head.ref, 'plan/')"; then
  if ! printf '%s\n' "$CODE" | grep -qE 'plan/\$plan_id/s|plan/\$\{plan_id\}/s'; then
    printf 'REFUSED: %s decides a session merge from the `plan/` prefix alone.\n' "$WF" >&2
    printf '         That matches plan AMENDMENT branches too, and merging one then\n' >&2
    printf '         dispatches a session nobody asked for. Measured 2026-09-22 on\n' >&2
    printf '         a plan-amendment PR. Test against plan/<plan-id>/s<N> in a step that can\n' >&2
    printf '         read the plan id.\n' >&2
    printf '::error title=Chain shape::an amendment branch would trigger the chain\n' >&2
    exit 3
  fi
fi

# --- 9. a push under read-only permissions -----------------------------------------------
#
# The escalation on 2026-09-22 decided correctly, wrote `status: escalated` into the plan, and
# then died on `git push` with `403 Write access to repository not granted`. The workflow
# declares `permissions: contents: read`, so the credential actions/checkout leaves behind
# cannot write — and the branch, the pull request and the board item are all downstream of
# that push. The decision logic was right and the path was unreachable.
if printf '%s\n' "$CODE" | grep -qE '^[[:space:]]*contents:[[:space:]]*read'; then
  # Read the line from the SAME view it was found in. The first version grepped $CODE and
  # then read $WF by that number — two different files once comments are stripped, so it
  # refused the corrected workflow while naming a line that said something else entirely.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      # A URL credential is NOT enough on its own: actions/checkout's extraheader overrides
      # it. What must hold is that the header is cleared BEFORE the push, so the rule asks
      # for both rather than either. Measured 2026-09-23, when naming the PAT in the URL
      # changed nothing and the push returned 403 again.
      (*x-access-token*)
        if ! printf '%s\n' "$CODE" | grep -q 'unset-all http.https://github.com/.extraheader'; then
          printf 'REFUSED: this workflow pushes with a URL credential but never clears the\n' >&2
          printf '         checkout extraheader, which OVERRIDES it. The push goes out as the\n' >&2
          printf '         read-only token and returns 403, quoting the remote rather than the\n' >&2
          printf '         URL it was given. Measured 2026-09-23.\n' >&2
          printf '::error title=Chain shape::a URL credential the extraheader will override\n' >&2
          exit 3
        fi ;;
      (*extraheader*) ;;
      (*)
        printf 'REFUSED: this workflow pushes while declaring contents: read.\n' >&2
        printf '         at: %s\n' "$(printf '%s' "$line" | sed 's/^[[:space:]]*//')" >&2
        printf '         actions/checkout leaves a READ-ONLY credential, so the push returns\n' >&2
        printf '         403 and everything downstream of it — the branch, the pull request,\n' >&2
        printf '         the board item — never happens. Measured 2026-09-22.\n' >&2
        printf '         Name the writing credential at the push rather than widening the\n' >&2
        printf '         workflow token for every step.\n' >&2
        printf '::error title=Chain shape::a push that cannot write\n' >&2
        exit 3 ;;
    esac
  done < <(printf '%s\n' "$CODE" | grep 'git push')
fi

# --- 5. escalation halts ------------------------------------------------------------------
ESC="$(line_of 'status escalated')"
if [ -n "$ESC" ]; then
  if ! awk -v s="$ESC" 'NR > s && /exit 1/ { found = 1 } END { exit !found }' "$WF"; then
    printf 'REFUSED: the escalation at line %s does not stop the chain.\n' "$ESC" >&2
    printf '         Decision 5 (ruled 2026-09-22) is escalate AND halt: a session escalates\n' >&2
    printf '         for a reason, and the next one may depend on the work that just failed.\n' >&2
    printf '::error title=Chain shape::escalation does not halt\n' >&2
    exit 3
  fi
fi

printf 'the chain dispatches with a PAT (line %s), judges main first (line %s), merges nothing, and halts on escalation\n' \
  "$DISPATCH" "$GREEN_CHECK"
exit 0
