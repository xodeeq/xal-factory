#!/usr/bin/env bash
#
# gates/driver.test.sh — proof that the driver refuses, that it says WHY, and that a
# refusal is not a crash.
#
# THE STANDING RULE THIS SATISFIES: "Every new gate ships with committed failing fixtures.
# A gate that has never been seen to fail has not been tested — a rule matching nothing and
# a rule finding nothing emit byte-identical green." One committed fixture per refusal,
# asserting the exit code AND the reason text, because a refusal for the wrong reason looks
# identical from the exit code alone.
#
# THE THREE-CODE CONTRACT IS ITSELF UNDER TEST -------------------------------------------
#
#   0  may run · 3  REFUSED (deliberate) · 2  CANNOT RUN (unparseable)
#
# 1, 2 and 127 are what a crashing bash script exits, which is why a refusal is 3. The
# `cannot run` cases below are not decoration: they are the assertion that an unparseable
# plan does NOT come back as a refusal, so "the driver declined" can never be read off a
# file it simply failed to understand.
#
# THE LIVE ASSERTION, AND WHY IT ASSERTS AN INVARIANT RATHER THAN AN INSTANCE -------------
#
# The last section runs preflight against the REAL docs/plan/plan.md. Committed fixtures
# prove the rules fire; only the real plan proves the driver can read the artifact it will
# actually be pointed at. ADR-0005 in the factory's gate 4 deliberately cannot do this — it
# runs the critic's fixtures rather than any live plan, because reaching a real one needs an
# input that gate must not have. Here the plan is in the same repo, so there is no excuse.
#
# IT USED TO SAY "preflight clears S1", AND THAT WAS WRONG. That assertion was true exactly
# until S1 ran, and then it failed — on the pull request that merged S1's own work, with
# `REFUSED: S1 already carries status 'passed'`, which is preflight being CORRECT. An
# assertion that only holds before the system is used is not a regression net; it is a
# tripwire on success.
#
# The root cause is the one the branch-check lesson names: an INSTANCE was encoded where an
# INVARIANT was needed. The property actually wanted is "the driver can read the real plan
# and reach a decision about every session in it", and that is true for the whole life of
# the plan. So the three assertions below are:
#
#   * the real plan parses and declares the sessions its own frontmatter claims;
#   * EVERY session gets a decision — exit 0 (may run) or 3 (refused), never 2 (cannot run);
#   * and the plan is either still runnable or finished — at least one session clears, OR
#     every session is already `passed`. Without that third one, a preflight that refused
#     everything would satisfy the first two.
#
# Usage:  gates/driver.test.sh
# Exit:   0 every scenario behaved as specified · 1 at least one did not
# Deps:   bash, awk, diff, mktemp, jq (reader-verdict.sh parses the verdict file with it).
#         No network, no credential, no language toolchain.
#
# TWO HALVES. The fixture half runs in any repository seeded from the platform scaffold, from
# commit one, with no plan yet. The LIVE half — the last two sections — needs docs/plan/plan.md,
# which the planner emits later; until then it is reported as not yet applicable rather than as
# green, and it starts running the day the plan lands.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PREFLIGHT="scripts/driver/preflight.sh"
WRITER="scripts/driver/plan-write.sh"
READER="scripts/driver/plan-read.sh"
FIX="gates/_fixtures/driver"
REAL="docs/plan/plan.md"

if [ -t 1 ]; then BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YEL=$'\033[33m'; RST=$'\033[0m'
else BOLD=""; RED=""; GREEN=""; YEL=""; RST=""; fi

for f in "$PREFLIGHT" "$WRITER" "$READER" "scripts/driver/branch-check.sh" "scripts/driver/fetch-spec.sh" \
         "scripts/driver/merge-decision.sh" "scripts/driver/merge-check.sh" "scripts/driver/reader-verdict.sh" \
         "scripts/driver/run-session-id.sh" "scripts/driver/ci-verdict.sh"; do
  [ -f "$f" ] || { printf '%s%s not found — there is nothing to prove%s\n' "$RED" "$f" "$RST"; exit 2; }
done
[ -d "$FIX" ] || {
  printf '%sno fixtures at %s — refusing to report green over an empty suite%s\n' "$RED" "$FIX" "$RST"; exit 2; }

pass=0; fail=0

TMP="$(mktemp -d)" || { printf '%smktemp failed%s\n' "$RED" "$RST"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# check <label> <want_exit> <want_pattern> <desc> -- <command...>
check() {
  local label="$1" want_exit="$2" want_pat="$3" desc="$4"; shift 5   # the 5th is the literal --
  local out rc problem=""
  out="$("$@" 2>&1)"; rc=$?
  [ "$rc" = "$want_exit" ] || problem="exit $rc, wanted $want_exit"
  if [ -n "$want_pat" ] && ! printf '%s' "$out" | grep -qE -- "$want_pat"; then
    problem="${problem:+$problem; }output did not match /$want_pat/"
  fi
  if [ -z "$problem" ]; then
    printf '%s  ✔%s %-26s exit %s  %s\n' "$GREEN" "$RST" "$label" "$rc" "$desc"
    pass=$((pass + 1))
  else
    printf '%s  ✗%s %-26s %s  (%s)\n' "$RED" "$RST" "$label" "$problem" "$desc"
    printf '%s\n' "$out" | sed 's/^/      | /'
    fail=$((fail + 1))
  fi
}

printf '\n%s━━ preflight REFUSES (exit 3), and names the reason%s\n\n' "$BOLD" "$RST"

check not-approved      3 "REFUSED: plan status is 'proposed'" \
  'a plan that is not approved may not be executed (ADR-0008 decision 8)' \
  -- bash "$PREFLIGHT" --plan "$FIX/not-approved.md" --session S1

check approval-unsigned 3 "REFUSED: plan claims 'approved' but names approved_by" \
  'an approval with no person and no date is a word (rule 11, execution half)' \
  -- bash "$PREFLIGHT" --plan "$FIX/approval-unsigned.md" --session S1

check unknown-autonomy  3 "REFUSED: autonomy_level 'yolo'" \
  'an autonomy_level outside the vocabulary stops the run' \
  -- bash "$PREFLIGHT" --plan "$FIX/unknown-autonomy.md" --session S1

# ADR-0009 revisit trigger 3, discharged at pipeline S7: `unset` was acceptable to a driver
# that never merged and is not to one that can. No session starts whose plan has no ruling
# about what may land.
check autonomy-unset    3 "REFUSED: autonomy_level is 'unset'" \
  'a plan with no autonomy ruling runs no session, now that sessions can land unattended' \
  -- bash "$PREFLIGHT" --plan "$FIX/merge-unset.md" --session S1

check already-run       3 "REFUSED: S1 already carries status 'passed'" \
  'a session that has run may not be re-run over its own evidence' \
  -- bash "$PREFLIGHT" --plan "$FIX/already-run.md" --session S1

# Rule 7 discriminates rather than blanket-refusing, and these two are the halves that prove
# it. `ungated` and `failed` MUST re-run — every session declares retry_cap: 2, and a retry is
# a re-run, so a blanket refusal made that field unreachable. `escalated` must NOT: a person
# owns the decision and a driver resuming it unasked is the whole reason the word exists.
check status-ungated    0 'S1 may run' \
  'a session whose gate produced no verdict may be re-run — retry_cap depends on it' \
  -- bash "$PREFLIGHT" --plan "$FIX/status-ungated.md" --session S1

check status-escalated  3 "REFUSED: S1 is 'escalated'" \
  'a session a person owns is never resumed by the driver' \
  -- bash "$PREFLIGHT" --plan "$FIX/status-escalated.md" --session S1

check no-such-session   3 "REFUSED: no session 'S99'" \
  'a typo\x27d session id must not silently run nothing' \
  -- bash "$PREFLIGHT" --plan "$FIX/clean.md" --session S99

check human-action      3 "REFUSED: S3 declares human_only_actions_before" \
  'a session a person must unblock first does not start' \
  -- bash "$PREFLIGHT" --plan "$FIX/clean.md" --session S3

check dependency-open   3 "REFUSED: S2 depends on S1, whose status is" \
  'a dependency that has not passed stops the dependent session' \
  -- bash "$PREFLIGHT" --plan "$FIX/clean.md" --session S2

printf '\n%s━━ CANNOT RUN (exit 2) is not a refusal — an unparseable plan decides nothing%s\n\n' "$BOLD" "$RST"

check no-frontmatter    2 'no YAML frontmatter' \
  'a plan with no frontmatter is exit 2, never exit 3' \
  -- bash "$PREFLIGHT" --plan "$FIX/no-frontmatter.md" --session S1

check no-sessions       2 'no .## Session S<N>:. blocks' \
  'a plan with no session blocks is exit 2, never exit 3' \
  -- bash "$PREFLIGHT" --plan "$FIX/no-sessions.md" --session S1

check no-plan-file      2 'plan not found' \
  'a missing plan is exit 2, never exit 3' \
  -- bash "$PREFLIGHT" --plan "$FIX/does-not-exist.md" --session S1

printf '\n%s━━ and it can still say yes%s\n\n' "$BOLD" "$RST"

check clean-S1          0 'S1 may run' \
  'the clean fixture PASSES (guards against a preflight that always refuses)' \
  -- bash "$PREFLIGHT" --plan "$FIX/clean.md" --session S1

printf '\n%s━━ each failing fixture is the clean one broken in EXACTLY ONE line%s\n\n' "$BOLD" "$RST"

# Without this, a fixture could fail for a reason nobody intended and the suite above would
# still be green — the assertion is that the rule fired BECAUSE of the one thing changed.
for f in not-approved approval-unsigned unknown-autonomy merge-unset already-run no-gate-command; do
  n="$(diff "$FIX/clean.md" "$FIX/$f.md" | grep -cE '^[<>]' || true)"
  if [ "$n" = "2" ]; then
    printf '%s  ✔%s %-26s 1 line replaced\n' "$GREEN" "$RST" "$f"
    pass=$((pass + 1))
  else
    printf '%s  ✗%s %-26s %s diff line(s), wanted 2 (one replaced line)\n' "$RED" "$RST" "$f" "$n"
    diff "$FIX/clean.md" "$FIX/$f.md" | sed 's/^/      | /'
    fail=$((fail + 1))
  fi
done

printf '\n%s━━ plan-write writes the named block, and refuses what it does not understand%s\n\n' "$BOLD" "$RST"

cp "$FIX/clean.md" "$TMP/plan.md"

# `ungated` is the word run 35440579899 needed and did not have: its gate was CANCELLED, so
# no verdict existed, and `failed` asserted the work was bad when ci.yml later found it green.
# Both block a `depends_on` identically; the difference is what the next decision should be.
check write-ungated     0 'S1: status=ungated' \
  'a gate that produced no verdict is ungated, which is not the same as failed' \
  -- bash "$WRITER" --plan "$TMP/plan.md" --session S1 --status ungated --evidence 'gate: NO VERDICT'

check write-bad-status  3 'REFUSED: status .almost. is not one of' \
  'a status outside the vocabulary is refused, not written' \
  -- bash "$WRITER" --plan "$TMP/plan.md" --session S1 --status almost --evidence x

check write-no-session  2 "no '## Session S99:' block" \
  'writing to a session that does not exist is cannot-run, not a silent no-op' \
  -- bash "$WRITER" --plan "$TMP/plan.md" --session S99 --status passed --evidence x

check write-passed      0 'S1: status=passed' \
  'a real write succeeds' \
  -- bash "$WRITER" --plan "$TMP/plan.md" --session S1 --status passed \
       --evidence 'PR: https://example.invalid/pr/1 · CI: https://example.invalid/run/1'

# The write landed in S1 and NOWHERE else. A writer that updates every session's status at
# once passes every check above and destroys the plan.
s1="$(bash "$READER" --plan "$TMP/plan.md" --session S1 --field status)"
s2="$(bash "$READER" --plan "$TMP/plan.md" --session S2 --field status)"
s3="$(bash "$READER" --plan "$TMP/plan.md" --session S3 --field status)"
if [ "$s1" = "passed" ] && [ -z "$s2" ] && [ -z "$s3" ]; then
  printf '%s  ✔%s %-26s S1=passed, S2 and S3 untouched\n' "$GREEN" "$RST" "write-scope"
  pass=$((pass + 1))
else
  printf '%s  ✗%s %-26s S1=%s S2=%s S3=%s — the write escaped its block\n' \
    "$RED" "$RST" "write-scope" "$s1" "${s2:-<empty>}" "${s3:-<empty>}"
  fail=$((fail + 1))
fi

# Exactly two lines differ from the fixture it was copied from: status and evidence.
n="$(diff "$FIX/clean.md" "$TMP/plan.md" | grep -cE '^[<>]' || true)"
if [ "$n" = "4" ]; then
  printf '%s  ✔%s %-26s exactly 2 lines rewritten (status, evidence)\n' "$GREEN" "$RST" "write-minimal"
  pass=$((pass + 1))
else
  printf '%s  ✗%s %-26s %s diff line(s), wanted 4 (two replaced lines)\n' "$RED" "$RST" "write-minimal" "$n"
  diff "$FIX/clean.md" "$TMP/plan.md" | sed 's/^/      | /'
  fail=$((fail + 1))
fi

printf '\n%s━━ the remote must be able to HOLD the session branch%s\n\n' "$BOLD" "$RST"

# Found on the first real driver run. The positive cases are cheap; the SIBLING case is
# the one that earns this section — a rule that refuses `…/s1` because `…/s2` exists would
# stop pipeline S6 on its second session, and would look exactly as correct as this one
# from an exit code.
BC="scripts/driver/branch-check.sh"
RF="$FIX/refs"
B="plan/fixture-20260917/s1"

check branch-free           0 'is free on the remote' \
  'a clean remote permits the session branch' \
  -- bash "$BC" --branch "$B" --refs "$RF/clean.txt"

check branch-df-conflict    3 'a ref sits where this branch needs a directory' \
  'a plan branch left behind after merge makes the session branch impossible' \
  -- bash "$BC" --branch "$B" --refs "$RF/plan-branch-left-behind.txt"

check branch-exists         3 'the branch already exists' \
  'the exact branch already being there is refused' \
  -- bash "$BC" --branch "$B" --refs "$RF/exact-branch-exists.txt"

check branch-ref-below      3 'a branch sits below the one being created' \
  'a ref underneath the session branch is the same conflict, inverted' \
  -- bash "$BC" --branch "$B" --refs "$RF/ref-below-branch.txt"

# A RETRY MAY REUSE ITS OWN BRANCH, AND ONLY ITS OWN. Attempt 1 creates the session branch at
# step 5, so every retry of a real session met "the branch already exists" and was refused in
# seconds — retry_cap unreachable for the SECOND time, measured on S10 where three attempts
# died there in 53 seconds without an agent ever starting. `--retry` downgrades exactly that
# case; both D/F conflicts still refuse, because a ref and a directory cannot share a path and
# no amount of intent makes that possible.
check branch-retry-own      0 'this is a retry' \
  'a retry may reuse its OWN branch' \
  -- bash "$BC" --branch "$B" --refs "$RF/exact-branch-exists.txt" --retry

check branch-retry-df       3 'cannot hold' \
  'a retry may NOT reuse a branch across a D/F conflict — a different hazard' \
  -- bash "$BC" --branch "$B" --refs "$RF/plan-branch-left-behind.txt" --retry

check branch-sibling-ok     0 'is free on the remote' \
  'a SIBLING session branch must NOT block this one (pipeline S6 depends on it)' \
  -- bash "$BC" --branch "$B" --refs "$RF/sibling-session.txt"

printf '\n%s━━ the spec is fetched and VERIFIED, or the session does not start%s\n\n' "$BOLD" "$RST"

# The first driven session shipped without its spec: its brief cited three requirement ids and
# the session could not open a word of any of them. Ruled that the DRIVER fetches it, so the
# credential stays in the workflow and never reaches the agent. These fixtures are
# self-contained — clean.md cites the digest of spec/fixture-spec.md, not of any real
# admitted spec, so nothing here has to stay in step with another repo.
FS="scripts/driver/fetch-spec.sh"
SP="$FIX/spec"

check spec-verified       0 'matches the digest in the plan' \
  'a spec whose digest matches the plan is accepted' \
  -- bash "$FS" --plan "$FIX/clean.md" --out "$TMP/spec-ok.md" --from "$SP/fixture-spec.md"

check spec-wrong-digest   3 'is not the document this plan cites' \
  'a spec that is NOT what the plan cites stops the session' \
  -- bash "$FS" --plan "$FIX/clean.md" --out "$TMP/spec-bad.md" --from "$SP/wrong-digest.md"

# Fail closed: a refused fetch must not leave a half-trusted file for the session to read.
if [ -f "$TMP/spec-bad.md" ]; then
  printf '%s  ✗%s %-26s a refused fetch left its file behind\n' "$RED" "$RST" "spec-refused-no-file"
  fail=$((fail + 1))
else
  printf '%s  ✔%s %-26s a refused fetch leaves no file for the session to read\n' \
    "$GREEN" "$RST" "spec-refused-no-file"
  pass=$((pass + 1))
fi

check spec-missing-source 2 'names no file' \
  'a source that does not exist is cannot-run, not a digest refusal' \
  -- bash "$FS" --plan "$FIX/clean.md" --out "$TMP/spec-x.md" --from "$SP/does-not-exist.md"

printf '\n%s━━ the session prompt is the approved plan, not a paraphrase of it%s\n\n' "$BOLD" "$RST"

PROMPTER="scripts/driver/session-prompt.sh"

check prompt-no-gate    2 'declares no gate command' \
  'a session with no done-criterion is never briefed' \
  -- bash "$PROMPTER" --plan "$FIX/no-gate-command.md" --session S1

check prompt-no-session 2 "no session 'S99'" \
  'a session that does not exist is never briefed' \
  -- bash "$PROMPTER" --plan "$FIX/clean.md" --session S99

# The five things a session could be briefed WITHOUT, each of which would let the agent pick
# its own boundaries: the gate command, the must_not, the scope_out, an artifact path, and the
# standing law that it does not write its own status. Asserted against the fixture plan, whose
# S1 carries known values for all five; the live section at the end asserts the same shape
# against the REAL plan once one exists, because that is the text that will actually be sent.
prompt_carries() {  # prompt_carries <label> <plan> <session> <want>...
  local label="$1" plan="$2" sid="$3" p want; shift 3
  if p="$(bash "$PROMPTER" --plan "$plan" --session "$sid" 2>&1)"; then
    for want in "$@"; do
      if printf '%s' "$p" | grep -qF -- "$want"; then
        printf '%s  ✔%s %-26s carries: %.48s…\n' "$GREEN" "$RST" "$label" "$want"
        pass=$((pass + 1))
      else
        printf '%s  ✗%s %-26s MISSING: %s\n' "$RED" "$RST" "$label" "$want"
        fail=$((fail + 1))
      fi
    done
  else
    printf '%s  ✗%s %-26s could not compose the %s prompt from %s\n' "$RED" "$RST" "$label" "$sid" "$plan"
    printf '%s\n' "$p" | sed 's/^/      | /'
    fail=$((fail + 1))
  fi
}
prompt_carries prompt-content "$FIX/clean.md" S1 \
  './scripts/check.sh && ./gates/check.test.sh' \
  'no coverage floor lowered; no secret value committed, only names' \
  'everything else' \
  'internal/fixture/a.go' \
  'Do not edit `docs/plan/plan.md`'

printf '\n%s━━ the gate judges the tree the driver will PUSH, not the one it checked out%s\n\n' "$BOLD" "$RST"

# the first service's plan S2 defect: the toolchain was resolved before the agent, the agent edited the
# manifest it was resolved from, and the gate ran under the stale resolution — green in the
# driver, red in ci.yml at the audit gate, and `status: passed` written into the plan for a
# tree CI rejects. Survivable only because a person read every session PR, which stops being
# true under the chain.
#
# The rule is an ORDERING and not a presence. "driver.yml mentions the toolchain" was true
# throughout the defect; what has to hold is that the toolchain the gate runs under is
# established after the agent can no longer change its inputs. The rule names the language
# overlay's action (`./.github/actions/toolchain`) and nothing about the language.
SO="scripts/driver/step-order.sh"
SOF="gates/_fixtures/step-order"

check order-no-reresolve  3 'not re-established between the agent' \
  'the shape that shipped the S2 defect is REFUSED' \
  -- bash "$SO" --workflow "$SOF/no-reresolve.yml"

# The overlay's toolchain action is ONE unit that re-resolves and reinstalls; an inline
# re-resolve is refused because the rule cannot see whether the gate's tools were rebuilt, and
# here they were not — a linter and a scanner built by the previous compiler judging this tree.
check order-inline        3 'not re-established between the agent' \
  'an inline re-resolve that is not the toolchain action is REFUSED' \
  -- bash "$SO" --workflow "$SOF/inline-reresolve.yml"

check order-clean         0 'judged under the session' \
  'the corrected shape PASSES (guards against a rule that always refuses)' \
  -- bash "$SO" --workflow "$SOF/clean.yml"

check order-not-a-driver  2 'no agent step' \
  'a file that is not a driver is cannot-run, never a refusal' \
  -- bash "$SO" --workflow "$SOF/no-agent.yml"

# The precondition relation, measured on run 35437944054: the state write was `always()` and
# the credential it pushes with was restored only on success, so a $20.87 session that hit
# --max-turns left NO record in the plan. Under chaining that reads as "never attempted".
check order-restore-cond  3 'restored' \
  'a state write that always runs, behind a credential restored only on success, is REFUSED' \
  -- bash "$SO" --workflow "$SOF/restore-conditional.yml"

# A cancellation is not a failure, and `if: failure()` does not match one. Run 35440579899
# skipped its bundle and upload for exactly that reason, in the case the net exists for.
# The ledger is where `attempts` is counted from, so a run that records nothing is a run that
# never happened. Conditioning the record on a non-empty cost means a run cancelled mid-agent
# records NOTHING — `attempts` never rises and the chain re-dispatches forever. An unbounded
# loop that leaves no trace of itself is strictly worse than a ledger that undercounts.
check order-record-cond   3 'record NOTHING' \
  'a spend record conditioned on the cost is REFUSED — retry_cap could never fire' \
  -- bash "$SO" --workflow "$SOF/record-needs-cost.yml"

check order-bundle-cancel 3 'does not match a job killed' \
  'a failure net that does not cover a cancellation is REFUSED' \
  -- bash "$SO" --workflow "$SOF/bundle-not-cancelled.yml"

# The commit a merge takes must be one CI has judged. Measured on run 35472339107: the gated
# commit was green and the PR HEAD — the plan-status commit, pushed with GITHUB_TOKEN — was
# left `action_required`, never executed. S3's and S4's merged heads are on main that way.
# `action_required` is neither green nor red, so the merge gate the 2026-09-19 ruling requires
# has nothing to read: the `ungated` lesson one layer out.
check order-push-cred     3 'no CI verdict at all' \
  'a head pushed with a different credential than opened the PR is REFUSED' \
  -- bash "$SO" --workflow "$SOF/push-credential-mismatch.yml"

# The live half. The fixtures prove the rule can fire; this proves it is pointed at the
# workflow that actually runs sessions, which is the part a fixture cannot establish.
check order-real-driver   0 'judged under the session' \
  'the REAL driver.yml resolves its toolchain after the agent' \
  -- bash "$SO" --workflow ".github/workflows/driver.yml"

printf '\n%s━━ every workflow can actually be DISPATCHED — the gate chain had no opinion on this%s\n\n' "$BOLD" "$RST"

# Added 2026-09-22, the same day it was needed. `LEDGER: ${{ runner.temp }}/…` in a job-level
# env block is valid YAML, passed check.sh end to end, passed step-order, passed chain-check,
# passed CI and review, and MERGED — and the first dispatch after it returned HTTP 422
# "Unrecognized named-value: 'runner'". The driver sat on main unable to start while every
# gate this repo owns said yes. GitHub validates expressions at DISPATCH, not at push.
WC="scripts/driver/workflow-context.sh"
WCF="gates/_fixtures/workflow-context"

check wfctx-clean         0 'no step-only context' \
  'a job-level env using only pre-runner contexts PASSES' \
  -- bash "$WC" --workflow "$WCF/clean.yml"

check wfctx-runner        3 'cannot be dispatched' \
  'the exact shape that reached main on 2026-09-22 is REFUSED' \
  -- bash "$WC" --workflow "$WCF/runner-context-in-job-env.yml"

check wfctx-steps         3 'cannot be dispatched' \
  'the steps context in a job-level env is the same class, and REFUSED' \
  -- bash "$WC" --workflow "$WCF/steps-context-in-job-env.yml"

# The discrimination half. `${{ runner.temp }}` in a STEP is legal and common — driver.yml's
# own artifact upload uses it. A rule that refused both would be unusable and would be
# switched off, which is worse than not having it.
check wfctx-step-level    0 'no step-only context' \
  'the same context INSIDE a step is legal and must not be refused' \
  -- bash "$WC" --workflow "$WCF/step-level-is-fine.yml"

# The live half, and it is the one that protects: the defect can land in ANY workflow, so
# every one in this repo is judged rather than the two the driver happens to care about.
for _wf in .github/workflows/*.yml; do
  check "wfctx-$(basename "$_wf" .yml)" 0 'no step-only context' \
    "the real $(basename "$_wf") can be dispatched" \
    -- bash "$WC" --workflow "$_wf"
done

printf '\n%s━━ the chain has the shape it must have — every rule here fails SILENTLY if broken%s\n\n' "$BOLD" "$RST"

# chain.yml only acts when a real PR merges or a real driver run ends, so its behaviour is
# unreachable from a fixture. Its SHAPE is checkable, and every rule below guards a failure
# that is invisible while it happens: a chain that quietly never runs reads exactly like a
# plan with nothing left to do.
CC="scripts/driver/chain-check.sh"
CHF="gates/_fixtures/chain"   # a sibling of $FIX, like step-order's — these judge workflows, not plans

check chain-clean         0 'dispatches with a PAT' \
  'the corrected shape PASSES (guards against a rule that always refuses)' \
  -- bash "$CC" --workflow "$CHF/clean.yml"

check chain-checks-api    3 'through the Checks API' \
  'a main-verdict read a fine-grained token cannot make is refused' \
  -- bash "$CC" --workflow "$CHF/checks-api.yml"

# The silent one. GitHub refuses to let GITHUB_TOKEN trigger more work, so a dispatch under it
# is CREATED AND NEVER RUNS — no error, no annotation. Same family as the 2026-09-20 finding
# where a push attributed to github-actions[bot] left CI `action_required` and the head unjudged.
check chain-github-token  3 'never run' \
  'a dispatch under GITHUB_TOKEN is REFUSED — it would silently never run' \
  -- bash "$CC" --workflow "$CHF/github-token-dispatch.yml"

check chain-merges        3 'Merging is merge.yml' \
  'a chain that merges is REFUSED — merging is merge.yml\x27s, behind merge-decision.sh' \
  -- bash "$CC" --workflow "$CHF/merges.yml"

check chain-autonomy      3 'only merge-decision.sh may read' \
  'a chain reading autonomy_level is REFUSED — what may land is merge.yml\x27s question' \
  -- bash "$CC" --workflow "$CHF/reads-autonomy.yml"

# `main` can go red with nobody present, and preflight reads `passed` out of the PLAN — a
# statement about a session, not about the base. With no branch protection here, nothing else
# asks. Both halves: the check missing, and the check present but too late.
check chain-no-main       3 'never reads a gate verdict' \
  'a chain that never asks whether main is green is REFUSED' \
  -- bash "$CC" --workflow "$CHF/no-main-check.yml"

check chain-main-late     3 'judged at line' \
  'judging main AFTER dispatching onto it is REFUSED — ordering, not presence' \
  -- bash "$CC" --workflow "$CHF/main-check-after.yml"

# Presence and ordering were BOTH true of the version that shipped, and it was still a
# permanent no-op: it read the verdict once, at the instant CI on the merge commit started.
# "Refuse when unjudged" then refuses every time. Measured on run 35774727222.
check chain-main-no-wait  3 'read once' \
  'a verdict read with no retry is REFUSED — it would refuse every time' \
  -- bash "$CC" --workflow "$CHF/main-check-no-wait.yml"

check chain-esc-continues 3 'does not stop the chain' \
  'an escalation that does not halt is REFUSED (decision 5, ruled 2026-09-22)' \
  -- bash "$CC" --workflow "$CHF/escalation-continues.yml"

# Both found LIVE on 2026-09-22, hours apart, and both were unreachable-by-construction
# rather than merely untested — the retry path refused every run it was handed, and the
# amendment guard dispatched a session nobody asked for.
check chain-head-branch   3 'wrong field' \
  'recovering the session from head_branch is REFUSED — it is always `main`' \
  -- bash "$CC" --workflow "$CHF/session-from-head-branch.yml"

check chain-amendment     3 'amendment branch' \
  'deciding a session merge from the `plan/` prefix alone is REFUSED' \
  -- bash "$CC" --workflow "$CHF/amendment-branch-triggers.yml"

# The escalation decided correctly, wrote the plan, then died on `git push` with 403 --
# everything that makes an escalation useful is downstream of that push.
check chain-push-no-write 3 'cannot write' \
  'a push under contents: read is REFUSED — the escalation would die at 403' \
  -- bash "$CC" --workflow "$CHF/push-without-write.yml"

# A URL credential is not enough: actions/checkout's extraheader overrides it, so the push
# goes out as the read-only token and returns 403 quoting the remote rather than the URL it
# was given. Measured 2026-09-23, after the previous fix named the PAT in the URL and the
# escalation failed identically.
check chain-extraheader   3 'OVERRIDES it' \
  'a URL credential with the checkout header left in place is REFUSED' \
  -- bash "$CC" --workflow "$CHF/url-cred-but-extraheader.yml"

check chain-not-a-chain   2 'not a chain' \
  'a file that dispatches nothing is cannot-run, never a refusal' \
  -- bash "$CC" --workflow "$CHF/not-a-chain.yml"

# The live half, the same shape step-order.sh uses: fixtures prove the rules can fire, and this
# proves they are pointed at the workflow that will actually chain sessions.
check chain-real          0 'dispatches with a PAT' \
  'the REAL chain.yml holds every rule' \
  -- bash "$CC" --workflow ".github/workflows/chain.yml"

printf '\n%s━━ the chain picks the LOWEST-NUMBERED eligible session, and halts rather than stepping over%s\n\n' "$BOLD" "$RST"

# Ruled by the owner 2026-09-19 over critical-path-first and halt-on-ambiguity. The property that
# earned it is the one asserted here: it is deterministic, so ONE fixture pins it — which is
# what a rule selecting work nobody is watching has to be.
SEL="scripts/driver/select-next.sh"

# The load-bearing one. S1 passed makes BOTH S2 (depends_on [S1]) and S3 (depends_on [])
# eligible, so choosing S2 can only be the numbering rule — availability alone would permit
# either. A fixture where one session is eligible would have proven nothing.
check select-lowest       0 'selected S2' \
  'two sessions eligible, the lower-numbered one is chosen' \
  -- bash "$SEL" --plan "$FIX/select-lowest.md"

# The halt beats an available selection: S1 is eligible in this fixture and is NOT run.
# Chaining past an escalation would keep spending after a known failure and leave the
# escalation as a note nobody is obliged to read.
check select-escalated    3 'the chain stops' \
  'an escalated session halts the chain even though another is eligible' \
  -- bash "$SEL" --plan "$FIX/select-escalated.md"

# `failed` and `ungated` are invitations to run again — this is preflight rule 7's other half,
# and it is what makes retry_cap reachable at all.
check select-retry        0 'selected S1' \
  'a failed session is selected again, which is what retry_cap depends on' \
  -- bash "$SEL" --plan "$FIX/select-retry.md"

# A finished plan and a stuck one want opposite responses from whoever reads the log, so they
# are different codes: COMPLETE is 4 (the chain reads it as green), a stuck plan is REFUSED 3.
# Complete was 3 until pipeline S7, which made the chain run after the LAST merge read red.
check select-complete     4 'COMPLETE: every session' \
  'a fully passed plan is COMPLETE (exit 4), not a refusal' \
  -- bash "$SEL" --plan "$FIX/select-complete.md"

check select-blocked      3 'none is eligible' \
  'pending sessions all waiting on dependencies refuse, and say so differently' \
  -- bash "$SEL" --plan "$FIX/select-blocked.md"

check select-no-plan      2 'plan not found' \
  'a missing plan is cannot-run, never a refusal' \
  -- bash "$SEL" --plan "$FIX/does-not-exist.md"

printf '\n%s━━ the ceilings are read from the ledger, and an unreadable ledger is never green%s\n\n' "$BOLD" "$RST"

# Two ceilings, ruled 2026-09-19: spend_ceiling_usd 600 per plan and session_ceiling_usd 45
# per session. Neither can stop a run already going — cost is per token — so both refuse to
# START the next one. That is the bound that was missing when a failed attempt cost $20.87
# inside every limit that existed.
SPEND="scripts/driver/spend.sh"
SPF="$FIX/spend"

check spend-plan-total    0 '^37\.7500$' \
  'a plan total sums only its own plan (a second plan sits in the fixture at $999)' \
  -- bash "$SPEND" --file "$SPF/clean.jsonl" --plan-total --plan-id fixture-20260917

check spend-attempts      0 '^2$' \
  'attempts are counted per session — this is the retry counter' \
  -- bash "$SPEND" --file "$SPF/clean.jsonl" --attempts --plan-id fixture-20260917 --session S1

check spend-within        0 'within both ceilings' \
  'a run inside both bounds is permitted' \
  -- bash "$SPEND" --file "$SPF/clean.jsonl" --check --plan-id fixture-20260917 --session S1 \
     --plan-ceiling 600 --session-ceiling 45

check spend-session-over  3 'session_ceiling_usd' \
  'a session that has spent its own bound REFUSES another attempt' \
  -- bash "$SPEND" --file "$SPF/clean.jsonl" --check --plan-id fixture-20260917 --session S1 \
     --plan-ceiling 600 --session-ceiling 30

check spend-plan-over     3 'spend_ceiling_usd' \
  'a plan that has spent its budget REFUSES the next session' \
  -- bash "$SPEND" --file "$SPF/clean.jsonl" --check --plan-id fixture-20260917 --session S2 \
     --plan-ceiling 35 --session-ceiling 45

# The discrimination half: a ledger this script cannot sum must not report green. A ceiling
# that silently undercounts is worse than no ceiling, because it reports safe while the
# number it defends drifts.
check spend-unreadable    2 'no readable cost_usd' \
  'a record with an unreadable cost is cannot-run, never a silent skip' \
  -- bash "$SPEND" --file "$SPF/bad-cost.jsonl" --check --plan-id fixture-20260917 --session S1 \
     --plan-ceiling 600 --session-ceiling 45

# A reader run is SPEND and not an ATTEMPT (pipeline S7). with-reader.jsonl is clean.jsonl plus
# one $2.50 reader record for S1: the total must see it, the retry counter must not — or every
# session the reader read would reach retry_cap one attempt early.
check spend-reader-total  0 '^40\.2500$' \
  'a reader record counts toward the plan total' \
  -- bash "$SPEND" --file "$SPF/with-reader.jsonl" --plan-total --plan-id fixture-20260917

check spend-reader-no-try 0 '^2$' \
  'a reader record is NOT an attempt — retry_cap counts builds, not reads' \
  -- bash "$SPEND" --file "$SPF/with-reader.jsonl" --attempts --plan-id fixture-20260917 --session S1

# An absent ledger is not an error for a read: a plan that has spent nothing has spent
# nothing, and the first session of a new plan must not be refused because no file exists.
check spend-absent        0 'nothing has been spent' \
  'an absent ledger permits the first run, and is distinguishable from an unreadable one' \
  -- bash "$SPEND" --file "$SPF/not-created-yet.jsonl" --check --plan-id fixture-20260917 --session S1 \
     --plan-ceiling 600 --session-ceiling 45

printf '\n%s━━ a finished driver run names its session in exactly one place, and it is read once%s\n\n' "$BOLD" "$RST"

# chain.yml and merge.yml both need this answer. The first version read head_branch, which is
# `main` for every dispatched run — so it lives in one script, and both workflows call it.
RSI="scripts/driver/run-session-id.sh"

check sid-from-title      0 '^S2$' \
  'the session id is read from the run title driver.yml gives every run' \
  -- bash "$RSI" --plan "$FIX/clean.md" --title 'Driver — S2'

check sid-no-session      3 'names no session' \
  'a title with no session id is REFUSED — never guessed' \
  -- bash "$RSI" --plan "$FIX/clean.md" --title 'Driver'

check sid-not-in-plan     3 'is not a session of' \
  'a session the plan does not declare is REFUSED' \
  -- bash "$RSI" --plan "$FIX/clean.md" --title 'Driver — S99'

printf '\n%s━━ a session lands with no person present ONLY when every condition holds%s\n\n' "$BOLD" "$RST"

# Pipeline S7. The 2026-09-19 ruling allows a merge with no human push PROVIDED THE GATES ARE
# OBEYED, and with no branch protection here this script is the only thing that obeys them.
# Each refusal below is one condition failing on an otherwise mergeable PR, and each asserts
# WHICH condition fired. The heads are made the way the driver makes them — plan-write.sh on a
# copy of main's plan — so nothing here can drift from what a real session branch carries.
MD="scripts/driver/merge-decision.sh"
mk_head() {  # mk_head <main plan> <out> <session> <status>
  cp "$1" "$2" && bash "$WRITER" --plan "$2" --session "$3" --status "$4" \
    --evidence 'PR: https://example.invalid/pr/1 · driver run (gate): https://example.invalid/run/1' >/dev/null 2>&1
}
mk_head "$FIX/clean.md" "$TMP/head-s1.md" S1 passed
mk_head "$FIX/clean.md" "$TMP/head-s1-failed.md" S1 failed
mk_head "$FIX/clean.md" "$TMP/head-s3.md" S3 passed
mk_head "$FIX/merge-unset.md" "$TMP/head-unset.md" S1 passed
mk_head "$FIX/unknown-autonomy.md" "$TMP/head-yolo.md" S1 passed
# Tampering, both shapes: a branch that edits its own risk class (the stray-line rule), and one
# that writes a NEIGHBOUR's status (which the diff shape alone cannot see — both are status lines).
sed 's/^- risk_class: infra$/- risk_class: code-only/' "$TMP/head-s1.md" > "$TMP/head-relabel.md"
cp "$TMP/head-s1.md" "$TMP/head-neighbour.md"
bash "$WRITER" --plan "$TMP/head-neighbour.md" --session S2 --status passed --evidence x >/dev/null 2>&1

# What each PR changed. Ordinary code, then a gate file nobody declared, then the same gate
# file under a plan whose S1 DOES declare `gates/` — the approved exception.
printf 'internal/fixture/a.go\ncoverage-floors\n' > "$TMP/changed-code.txt"
printf 'internal/fixture/a.go\nscripts/check.sh\n' > "$TMP/changed-gate.txt"
printf 'internal/fixture/a.go\ngates/_fixtures/new/x.yml\n' > "$TMP/changed-gates-dir.txt"
: > "$TMP/changed-none.txt"
awk '{print} $0 == "  - internal/fixture/a.go" && !done {print "  - gates/"; done=1}' \
  "$FIX/clean.md" > "$TMP/main-declares-gates.md"
mk_head "$TMP/main-declares-gates.md" "$TMP/head-declares-gates.md" S1 passed

ok_args=(--main-plan "$FIX/clean.md" --head-plan "$TMP/head-s1.md" --session S1 --changed-files "$TMP/changed-code.txt")

check merge-clean         0 '^merge$' \
  'passed, admitted, CI green, reader clean, current — it MERGES (guards a rule that always refuses)' \
  -- bash "$MD" "${ok_args[@]}" --ci success --reader success --behind 0

# THE FIXTURE THE RULING NAMES: "the merge step needs a committed fixture proving it REFUSES a
# red PR". And its twin, because the verdict that has not arrived yet is the common case.
check merge-red-pr        3 "concluded 'failure' — a red pull request never merges" \
  'a RED pull request is REFUSED (the 2026-09-19 ruling, consequence 1)' \
  -- bash "$MD" "${ok_args[@]}" --ci failure --reader success --behind 0

check merge-unjudged      3 'no gate verdict on the head' \
  'a pull request CI has not judged is REFUSED — unjudged is not green' \
  -- bash "$MD" "${ok_args[@]}" --ci '' --reader success --behind 0

# ADR-0009 decision 10: an auto-merge must not race the reviewer. Three shapes of "not clean".
check merge-reader-found  3 "reader's verdict on the head is 'failure'" \
  'a reader FINDING stops the merge for the owner' \
  -- bash "$MD" "${ok_args[@]}" --ci success --reader failure --behind 0

check merge-reader-racing 3 'still reading the head' \
  'a reader still running is REFUSED — the merge does not race it' \
  -- bash "$MD" "${ok_args[@]}" --ci success --reader pending --behind 0

check merge-reader-absent 3 'reader has no verdict' \
  'no reader verdict at all is REFUSED' \
  -- bash "$MD" "${ok_args[@]}" --ci success --reader '' --behind 0

# No merge queue exists, so a head behind main is re-based and re-gated rather than merged —
# two individually-green sessions can be red combined.
check merge-behind        0 '^update$' \
  'a green head BEHIND main is re-gated (update), never merged as it stands' \
  -- bash "$MD" "${ok_args[@]}" --ci success --reader success --behind 3

# Red outranks stale: updating the branch must never be the route by which a red PR gets a
# second chance to look green.
check merge-red-and-stale 3 'a red pull request never merges' \
  'a RED head that is also behind is REFUSED, not updated' \
  -- bash "$MD" "${ok_args[@]}" --ci failure --reader success --behind 3

# CI runs the head's OWN check.sh, so a session that weakened its gate would be judged green by
# the gate it weakened. Unattended, nobody would read that before it landed.
check merge-gate-edited   3 'changes scripts/check.sh, a gate or pipeline path S1 does not declare' \
  'a PR that edits the gate without the plan declaring it is REFUSED' \
  -- bash "$MD" --main-plan "$FIX/clean.md" --head-plan "$TMP/head-s1.md" --session S1 \
       --changed-files "$TMP/changed-gate.txt" --ci success --reader success --behind 0

check merge-gate-declared 0 '^merge$' \
  'a gate change the APPROVED plan declares as an artifact (a directory, here) may land' \
  -- bash "$MD" --main-plan "$TMP/main-declares-gates.md" --head-plan "$TMP/head-declares-gates.md" --session S1 \
       --changed-files "$TMP/changed-gates-dir.txt" --ci success --reader success --behind 0

# The overlay's own protected paths, read from a file rather than compiled in — so the built-in
# set stays language-agnostic and a Go overlay can protect its linter config. Two halves: a
# listed path is refused, and the same change lands when the list does not name it.
printf 'lint.cfg\n' > "$TMP/protected-extra"
printf 'internal/fixture/a.go\nlint.cfg\n' > "$TMP/changed-extra.txt"
check merge-protected-extra 3 'changes lint.cfg, a gate or pipeline path S1 does not declare' \
  'a path listed in .xal/protected-paths is protected exactly like the built-in set' \
  -- bash "$MD" --main-plan "$FIX/clean.md" --head-plan "$TMP/head-s1.md" --session S1 \
       --changed-files "$TMP/changed-extra.txt" --protected "$TMP/protected-extra" \
       --ci success --reader success --behind 0

check merge-unlisted-extra  0 '^merge$' \
  'the same path with an empty list is ordinary code (guards a list that protects everything)' \
  -- bash "$MD" --main-plan "$FIX/clean.md" --head-plan "$TMP/head-s1.md" --session S1 \
       --changed-files "$TMP/changed-extra.txt" --protected "$TMP/does-not-exist" \
       --ci success --reader success --behind 0

check merge-no-changes    0 '^merge$' \
  'an empty change list is a list, not a refusal' \
  -- bash "$MD" --main-plan "$FIX/clean.md" --head-plan "$TMP/head-s1.md" --session S1 \
       --changed-files "$TMP/changed-none.txt" --ci success --reader success --behind 0

check merge-not-passed    3 "status on the head is 'failed'" \
  'a session the driver did not pass never lands' \
  -- bash "$MD" --main-plan "$FIX/clean.md" --head-plan "$TMP/head-s1-failed.md" --session S1 \
       --changed-files "$TMP/changed-code.txt" --ci success --reader success --behind 0

# R1's ruling, applied. S3 is `infra`: no autonomy level admits it, ever.
check merge-out-of-class  3 "risk_class 'infra', which autonomy_level" \
  'a session outside autonomy_level STOPS for the owner — the roadmap S7 gate, in a fixture' \
  -- bash "$MD" --main-plan "$FIX/clean.md" --head-plan "$TMP/head-s3.md" --session S3 \
       --changed-files "$TMP/changed-code.txt" --ci success --reader success --behind 0

check merge-unset         3 "autonomy_level is 'unset'" \
  'a plan with no autonomy ruling merges nothing (ADR-0009 revisit trigger 3)' \
  -- bash "$MD" --main-plan "$FIX/merge-unset.md" --head-plan "$TMP/head-unset.md" --session S1 \
       --changed-files "$TMP/changed-code.txt" --ci success --reader success --behind 0

check merge-unknown       3 "autonomy_level 'yolo' is not one of" \
  'an autonomy_level outside the vocabulary merges nothing' \
  -- bash "$MD" --main-plan "$FIX/unknown-autonomy.md" --head-plan "$TMP/head-yolo.md" --session S1 \
       --changed-files "$TMP/changed-code.txt" --ci success --reader success --behind 0

# A branch approving its own merge. Autonomy and risk class are read from MAIN, and the head may
# differ from main only in this session's status and evidence.
check merge-relabelled    3 'changes more than S1' \
  'a head that edits the plan beyond its own status line is REFUSED' \
  -- bash "$MD" --main-plan "$FIX/clean.md" --head-plan "$TMP/head-relabel.md" --session S1 \
       --changed-files "$TMP/changed-code.txt" --ci success --reader success --behind 0

check merge-neighbour     3 "changes S2's status" \
  'a head that writes ANOTHER session\x27s status is REFUSED' \
  -- bash "$MD" --main-plan "$FIX/clean.md" --head-plan "$TMP/head-neighbour.md" --session S1 \
       --changed-files "$TMP/changed-code.txt" --ci success --reader success --behind 0

check merge-cannot-run    2 'CANNOT RUN: --ci is required' \
  'a caller that forgot to pass the CI verdict is cannot-run, never a decision' \
  -- bash "$MD" "${ok_args[@]}" --reader success --behind 0

printf '\n%s━━ CI'"'"'s verdict is read through the Actions API, which a fine-grained token can reach%s\n\n' "$BOLD" "$RST"

# The Checks API has no fine-grained permission, so the first live proof's merge was a 403
# under a fine-grained FACTORY_WRITE_TOKEN. ci-verdict.sh reads the CI workflow's run for the
# commit, then its gate job. A stub `gh` stands in for the API: CIV_MODE picks its answer.
CIV="scripts/driver/ci-verdict.sh"
mkdir -p "$TMP/civ-stub"
cat > "$TMP/civ-stub/gh" <<'STUB'
#!/usr/bin/env bash
case "${CIV_MODE:-}:$2" in
  (denied:*)             printf 'Resource not accessible by personal access token (HTTP 403)\n'; exit 1 ;;
  (none:*/runs\?*)       printf '' ;;
  (*:*/runs\?*)          printf '4242' ;;
  (running:*/jobs*)      printf '' ;;
  (green:*/jobs*)        printf 'success' ;;
  (red:*/jobs*)          printf 'failure' ;;
esac
STUB
chmod +x "$TMP/civ-stub/gh"
civ() { env PATH="$TMP/civ-stub:$PATH" CIV_MODE="$1" bash "$CIV" --repo o/r --sha 0123456789abcdef; }

check civ-green           0 '^success$' \
  'a completed green gate job reads as success' -- civ green
check civ-red             0 '^failure$' \
  'a completed red gate job reads as failure, never as nothing' -- civ red
check civ-denied          4 'needs Actions: Read on o/r' \
  'a token that cannot read Actions ends the wait at once and names the permission' -- civ denied
if [ "$(civ denied 2>/dev/null)" = unreadable ]; then
  printf '%s  ✔%s %-26s stdout is `unreadable`: non-empty, and never success\n' "$GREEN" "$RST" "civ-denied-stdout"
  pass=$((pass + 1))
else
  printf '%s  ✗%s %-26s stdout was not `unreadable`\n' "$RED" "$RST" "civ-denied-stdout"
  fail=$((fail + 1))
fi
for mode in none running; do
  if [ -z "$(civ "$mode" 2>/dev/null)" ]; then
    printf '%s  ✔%s %-26s prints nothing, so the caller keeps waiting\n' "$GREEN" "$RST" "civ-$mode"
    pass=$((pass + 1))
  else
    printf '%s  ✗%s %-26s printed a verdict for CI that has not finished\n' "$RED" "$RST" "civ-$mode"
    fail=$((fail + 1))
  fi
done

printf '\n%s━━ merge.yml has the shape it must have — each rule guards a merge the decision never approved%s\n\n' "$BOLD" "$RST"

MC="scripts/driver/merge-check.sh"
MGF="gates/_fixtures/merge"

check mshape-clean        0 'lands once, pinned' \
  'the corrected shape PASSES (guards against a rule that always refuses)' \
  -- bash "$MC" --workflow "$MGF/clean.yml"

check mshape-checks-api   3 'through the Checks API' \
  'a CI read a fine-grained token cannot make (403, every session stops) is refused' \
  -- bash "$MC" --workflow "$MGF/checks-api.yml"

check mshape-two-merges   3 'more than one place' \
  'a second merge site is REFUSED — a path around the decision' \
  -- bash "$MC" --workflow "$MGF/two-merges.yml"

check mshape-unpinned     3 'does not pin --match-head-commit' \
  'a merge not pinned to the judged sha is REFUSED' \
  -- bash "$MC" --workflow "$MGF/no-match-head.yml"

check mshape-auto         3 'with --admin or --auto' \
  'a deferred or overriding merge is REFUSED' \
  -- bash "$MC" --workflow "$MGF/auto-merge.yml"

check mshape-no-decision  3 'never runs merge-decision.sh' \
  'a merge nothing decided is REFUSED' \
  -- bash "$MC" --workflow "$MGF/no-decision.yml"

check mshape-ci-once      3 'read once, with no retry' \
  'a CI verdict read once is REFUSED — it would stop every session (run 35774727222)' \
  -- bash "$MC" --workflow "$MGF/ci-read-once.yml"

check mshape-no-reader    3 'never reads the reader' \
  'a merge that races the reviewer is REFUSED (ADR-0009 decision 10)' \
  -- bash "$MC" --workflow "$MGF/no-reader.yml"

check mshape-token        3 'triggers no workflow' \
  'a GITHUB_TOKEN merge is REFUSED — the chain would never advance' \
  -- bash "$MC" --workflow "$MGF/github-token-merge.yml"

check mshape-any-run      3 'SUCCEEDED' \
  'a merge path reachable from a FAILED driver run is REFUSED' \
  -- bash "$MC" --workflow "$MGF/no-success-filter.yml"

check mshape-race         3 'no workflow-level concurrency' \
  'two merge decisions free to race is REFUSED' \
  -- bash "$MC" --workflow "$MGF/no-concurrency.yml"

check mshape-not-merge    2 'not a merge workflow' \
  'a file that merges nothing is cannot-run, never a refusal' \
  -- bash "$MC" --workflow "$MGF/not-a-merge.yml"

# Each failing fixture is the clean one changed in one place — two diff lines for a replaced
# line, one for an added or deleted one, three for the concurrency block removed whole.
for f in two-merges:1 no-match-head:2 auto-merge:2 no-decision:2 no-reader:2 github-token-merge:2 no-success-filter:2 no-concurrency:3; do
  name="${f%%:*}"; want="${f##*:}"
  n="$(diff "$MGF/clean.yml" "$MGF/$name.yml" | grep -cE '^[<>]' || true)"
  if [ "$n" = "$want" ]; then
    printf '%s  ✔%s %-26s one change from clean\n' "$GREEN" "$RST" "$name"
    pass=$((pass + 1))
  else
    printf '%s  ✗%s %-26s %s diff line(s), wanted %s\n' "$RED" "$RST" "$name" "$n" "$want"
    fail=$((fail + 1))
  fi
done

check mshape-real         0 'lands once, pinned' \
  'the REAL merge.yml holds every rule' \
  -- bash "$MC" --workflow ".github/workflows/merge.yml"

printf '\n%s━━ the reader'"'"'s verdict is read by a script, and nothing but a clean one is green%s\n\n' "$BOLD" "$RST"

# The judgement half is the xal-factory plugin's `reader` agent; this is the mechanical half, with the same
# split ADR-0008 made for the plan critic. The rule is one-way: `success` only for a well-formed
# file that says PASS twice and names nothing. A reader that crashed has not read the PR.
RV="scripts/driver/reader-verdict.sh"
RVF="gates/_fixtures/reader-verdict"

check verdict-clean       0 '^success' \
  'PASS on both axes with no findings is the ONLY green' \
  -- bash "$RV" --file "$RVF/clean.json"

check verdict-spec        0 '^failure' \
  'a Spec finding is a failure (the reader found a cited clause unrealised)' \
  -- bash "$RV" --file "$RVF/spec-finding.json"

check verdict-standards   0 '^failure' \
  'a Standards finding is a failure' \
  -- bash "$RV" --file "$RVF/standards-finding.json"

check verdict-missing     3 '^failure' \
  'NO verdict file is a failure, never a pass — a reader that crashed has not read the PR' \
  -- bash "$RV" --file "$RVF/does-not-exist.json"

check verdict-not-json    3 'not a JSON object' \
  'prose where a verdict should be is a failure' \
  -- bash "$RV" --file "$RVF/not-json.json"

check verdict-contradicts 3 'yet 1 finding' \
  'PASS with findings listed is a contradiction, and a failure' \
  -- bash "$RV" --file "$RVF/pass-with-findings.json"

check verdict-unnamed     3 'no finding is named' \
  'FINDINGS with nothing named is a failure — a finding nobody can read is not one' \
  -- bash "$RV" --file "$RVF/findings-unnamed.json"

check verdict-vocabulary  3 "is 'LGTM', not PASS or FINDINGS" \
  'a value outside the vocabulary is a failure' \
  -- bash "$RV" --file "$RVF/unknown-value.json"

printf '\n%s━━ the LIVE assertion: the driver can read the REAL plan, whatever state it is in%s\n\n' "$BOLD" "$RST"

if [ ! -f "$REAL" ]; then
  # A seeded repository has no plan until the planner has run, by design — docs/plan/README.md
  # says an empty plan.md is worse than none. So this is neither a pass nor a failure: it is
  # reported as not yet applicable, loudly, and the two live checks start the day a plan lands.
  # The fixture half above is what proves the driver in the meantime.
  printf '%s  ⚠%s %-26s no %s yet — the planner has not run; the live half is not applicable until it does\n' \
    "$YEL" "$RST" "real-plan" "$REAL"
else
  # 0. the real S1 prompt has the shape the fixture prompt was proven to have: the plan's own
  #    gate command, its first artifact, and the law that a session never writes its own status.
  prompt_carries real-plan-prompt "$REAL" S1 \
    "$(bash "$READER" --plan "$REAL" --session S1 --field gate.command)" \
    "$(bash "$READER" --plan "$REAL" --session S1 --field artifact | head -1)" \
    'Do not edit `docs/plan/plan.md`'

  # 1. it parses, and the block count agrees with the frontmatter's own claim.
  live_sessions="$(bash "$READER" --plan "$REAL" --sessions 2>&1)"; rc=$?
  declared="$(bash "$READER" --plan "$REAL" --fm sessions_total 2>/dev/null)"
  counted="$(printf '%s\n' "$live_sessions" | grep -c '^S[0-9]' || true)"
  if [ "$rc" -eq 0 ] && [ "$counted" = "$declared" ]; then
    printf '%s  ✔%s %-26s parses; %s session(s), matching sessions_total\n' \
      "$GREEN" "$RST" "real-plan-parses" "$counted"
    pass=$((pass + 1))
  else
    printf '%s  ✗%s %-26s exit %s, counted %s, sessions_total %s\n' \
      "$RED" "$RST" "real-plan-parses" "$rc" "$counted" "$declared"
    fail=$((fail + 1))
  fi

  # 2. every session gets a DECISION. Exit 2 means the driver could not understand its own
  #    plan, which is the only outcome that is never acceptable here.
  undecided=""; runnable=0; unfinished=0
  while IFS= read -r sid; do
    [ -n "$sid" ] || continue
    out="$(bash "$PREFLIGHT" --plan "$REAL" --session "$sid" 2>&1)"; rc=$?
    case "$rc" in
      0) runnable=$((runnable + 1)) ;;
      3) : ;;
      *) undecided="$undecided $sid(exit $rc)" ;;
    esac
    st="$(bash "$READER" --plan "$REAL" --session "$sid" --field status)"
    [ "$st" = "passed" ] || unfinished=$((unfinished + 1))
  done <<EOF
$live_sessions
EOF
  if [ -z "$undecided" ]; then
    printf '%s  ✔%s %-26s every session decided (0 or 3), none exit 2\n' \
      "$GREEN" "$RST" "real-plan-decidable"
    pass=$((pass + 1))
  else
    printf '%s  ✗%s %-26s undecidable:%s\n' "$RED" "$RST" "real-plan-decidable" "$undecided"
    fail=$((fail + 1))
  fi

  # 3. discrimination. A preflight that refuses everything passes 1 and 2 happily.
  if [ "$runnable" -gt 0 ] || [ "$unfinished" -eq 0 ]; then
    printf '%s  ✔%s %-26s %s runnable now, %s not yet passed — the plan can still move\n' \
      "$GREEN" "$RST" "real-plan-progresses" "$runnable" "$unfinished"
    pass=$((pass + 1))
  else
    printf '%s  ✗%s %-26s no session clears and %s are unfinished — the plan is stuck\n' \
      "$RED" "$RST" "real-plan-progresses" "$unfinished"
    fail=$((fail + 1))
  fi
fi

printf '\n%s──────── %s passed · %s failed ────────%s\n' "$BOLD" "$pass" "$fail" "$RST"
if [ "$fail" -ne 0 ]; then
  printf '%s::error::the driver did not behave as its fixtures specify%s\n' "$RED" "$RST"
  exit 1
fi
printf '%sthe driver is proven to refuse, to name why, and to distinguish a refusal from a crash.%s\n' \
  "$GREEN" "$RST"
exit 0
