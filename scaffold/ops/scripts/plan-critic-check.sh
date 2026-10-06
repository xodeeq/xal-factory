#!/usr/bin/env bash
#
# plan-critic-check.sh — the MECHANICAL half of the plan critic.
#
# WHAT THIS IS, AND WHAT IT DELIBERATELY IS NOT ------------------------------------
#
# The plan critic was first designed as "an agent". Half of it cannot be. A plan reaches the
# owner only after two different
# kinds of check, and they fail for different reasons:
#
#   * MECHANICAL — decidable from the plan file's text alone, with no judgement: is there a
#     gate command at all, is every artifact a path, do the dependencies resolve, is there a
#     cycle. That is this script. It is a gate, it ships with one committed failing fixture
#     per rule, and it says WHICH rule fired.
#   * JUDGEMENT — is this the right decomposition; is the gate command MEANINGFUL for the
#     scope or merely present; do the sessions cover the spec's requirements; is the risk
#     class honest. That is .claude/agents/plan-critic.md, and no script can do it.
#
# The split is not a preference. A gate is run by CI from a plain `run:` step, and a plugin
# is not resolvable from one; making CI resolve one would itself be a new gate input in every
# workflow in every repo, which is the bug declared gate inputs exist to prevent. So the
# mechanical half is a plain script in a repo, and the judgement half is an agent. See
# ADR-0005 in the factory (adr/0005-plan-format-and-critic.md).
#
# WHY RULE 2 IS NOT ENOUGH ON ITS OWN, STATED HERE SO NOBODY DELETES THE AGENT -----
#
# Rule 2 asserts a gate command EXISTS and is non-empty. It cannot assert the command proves
# anything: `true`, or a `go test -run` pattern matching no test, passes rule 2 and exits 0
# forever. That is the signature failure — "a rule matching nothing and a rule
# finding nothing emit byte-identical green" — and it is exactly the class this script is
# structurally unable to catch. The agent catches it. A plan that passes this script has not
# been reviewed; it has been made reviewable.
#
# THE RULES -----------------------------------------------------------------------
#
#   1. frontmatter: required keys, the spec citation triple, the explicitly-unset keys
#   2. every session declares a non-empty gate command      (done-criterion decidable)
#   3. every session declares non-empty gate must_not       (boundary conditions)
#   4. every artifact is a path, not prose
#   5. scope_in AND scope_out both present and non-empty
#   6. retry_cap is an integer and on_exhaustion is exactly `escalate`  (failure fallback)
#   7. sessions_total is consistent with the block count, and within budget if one exists
#   8. every depends_on id resolves to a declared session   (goal layered)
#   9. no cycle in the depends_on graph
#  10. the driver's state fields and the session's identity fields are present
#  11. a plan whose status is `approved` names its approver and its date
#
# Rules 2, 3, 6, 8/9 and 1 are loop-design-check's five-point framework, in order:
# done-criterion machine-verifiable; boundary conditions stated alongside; failure fallback
# with retry cap and escalation; goal layered; reconciliation over assertion (rule 1 makes
# the plan cite the spec by a digest the ledger can reconcile, not by a path it can only
# assert). Roadmap §4.3 names that framework; this table is it, rule by rule.
#
# WHY THE SPEC CITATION IS A DIGEST AND NOT A PATH ---------------------------------
#
# Roadmap §7.2's template carries `spec: docs/spec/service.md` and
# `spec_status_required: approved`. Both assumed §4.1's world, where the spec lived in the
# service repo with a draft/approved/superseded lifecycle. S1 built something else: specs
# are admitted to the ops repo under `specs/admitted/<service>/<version>.md` with a sha256 in
# `specs/ledger`, and the service repo holds a POINTER with no frontmatter and therefore no
# `status` field at all. A `spec_status_required: approved` check would be asserting a value
# against a key that does not exist — a check that reads as one and is none. CLAUDE.md
# already rules the replacement: "Cite a spec by the identity it carries, service +
# spec_version, not by a filename in prose."
#
# WHY `spec_max_sessions` MAY BE THE LITERAL `none-declared` -----------------------
#
# §4.3 says the critic rejects a plan exceeding "the budget declared in the spec". §7.1's
# service-spec template carried `budget.max_sessions` — and §7.1 never landed either. The
# intake format S1 actually built is four typed keys and ten sections, with no budget field,
# so an admitted spec CANNOT declare a cap today. Rule 7 therefore checks self-consistency
# unconditionally and the cap only when one exists, and the key is REQUIRED so that the
# absence is written on the page rather than being silent. A half-rule that is inert and
# looks enforced is the thing this repo forbids; a stated absence is not inert.
#
# Usage:  scripts/plan-critic-check.sh [--root DIR] [--plan FILE]
#           --root DIR   a tree containing docs/plan/plan.md  (default: .)
#           --plan FILE  check this file instead; overrides --root
# Exit:   0 clean · 1 violations found · 2 could not run
# Deps:   bash, awk, grep, sed. No language runtime, no network, no credential — this gate
#         reads one file and nothing else, deliberately.

set -uo pipefail

ROOT="."
PLAN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; [ -n "$ROOT" ] || { printf -- '--root needs a directory\n' >&2; exit 2; }; shift 2 ;;
    --plan) PLAN="${2:-}"; [ -n "$PLAN" ] || { printf -- '--plan needs a file\n' >&2; exit 2; }; shift 2 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$PLAN" ] || PLAN="$ROOT/docs/plan/plan.md"

if [ ! -f "$PLAN" ]; then
  printf 'no plan at %s — refusing to report green over a plan that does not exist\n' "$PLAN" >&2
  exit 2
fi

if [ -t 1 ]; then BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; RST=$'\033[0m'
else BOLD=""; RED=""; GREEN=""; RST=""; fi

violations=0
v() { printf '%s  %s%s\n' "$RED" "$1" "$RST"; violations=$((violations + 1)); }

US=$'\037'   # unit separator: the record separator for the parsed stream. Chosen because
             # a must_not clause or a prompt line may legitimately contain `|`, and a
             # separator that can appear in a value silently truncates the record.

# --- parse -------------------------------------------------------------------------
# Emits one record per field: SID <US> KEY <US> VALUE. Session ids come from the block
# headers; `artifact` records repeat, one per path; gate sub-keys arrive as `gate.command`
# and `gate.must_not`.
#
# GOTCHA: the prompt block is `prompt: |` followed by indented prose that may itself contain
# lines beginning with `- `. Those must not be read as fields of the session, so the parser
# leaves prompt mode only on a line that starts a new top-level field AT COLUMN 0 or a new
# `## ` heading — an indented `- ` inside the prompt stays prompt content.
parse() {
  awk -v US="$US" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function emit(k, val) { gsub(US, " ", val); print sid US k US val }

    /^## Session S[0-9]+:/ {
      insess = 1; inprompt = 0; ctx = ""
      sid = $0; sub(/^## Session /, "", sid); sub(/:.*$/, "", sid)
      print sid US "_block" US "1"
      next
    }
    /^## / { insess = 0; inprompt = 0; ctx = ""; next }
    insess != 1 { next }

    inprompt == 1 {
      if ($0 ~ /^-[ \t]/ || $0 ~ /^## /) { inprompt = 0; ctx = "" }
      else { if (trim($0) != "") emit("prompt_line", trim($0)); next }
    }

    /^-[ \t]+[a-z_]+:/ {
      ctx = ""
      line = $0; sub(/^-[ \t]+/, "", line)
      key = line; sub(/:.*$/, "", key)
      val = line; sub(/^[a-z_]+:[ \t]*/, "", val)
      val = trim(val)
      if (key == "prompt" && val == "|") { inprompt = 1; emit("prompt", ""); next }
      if (val == "") ctx = key
      emit(key, val)
      next
    }

    /^[ \t]+-[ \t]/ {
      line = $0; sub(/^[ \t]+-[ \t]+/, "", line)
      line = trim(line)
      if (ctx == "artifacts") { emit("artifact", line); next }
      if (ctx == "gate") {
        k = line; sub(/:.*$/, "", k)
        val2 = line; sub(/^[a-z_]+:[ \t]*/, "", val2)
        emit("gate." k, trim(val2))
        next
      }
      next
    }
  ' "$1"
}

# Frontmatter block: between the leading --- and the next ---. Same extraction the
# frontmatter checker uses, so a plan and a doc are read the same way.
fm_block() {
  awk 'NR==1 && $0 != "---" { exit }
       NR==1 { infm=1; next }
       infm && $0 == "---" { exit }
       infm { print }' "$1"
}

# Is a top-level frontmatter key PRESENT at all (whatever its value)?
fm_has() { printf '%s\n' "$2" | grep -qE "^$1:"; }

# Its trimmed value, quotes stripped. Empty for a present-but-blank key — which is a
# legitimate state for approved_by, approved_on and the per-session driver fields, and is
# exactly why presence and non-emptiness are checked separately below.
# GOTCHA: the plan template annotates values with inline comments
# (`status: proposed         # proposed | approved | ...`). A reader that does not strip
# them reads the whole annotation as the value, so `status` fails its own vocabulary check
# and `autonomy_level: unset  # ruled by R1` never compares equal to `unset` — the rule
# below it would then be skipped silently, which is the inert-rule failure this repo
# forbids. Strip from the first ` #` to end of line; a `#` with no leading space stays.
fm_get() {
  printf '%s\n' "$2" | awk -v k="$1" '
    $0 ~ "^" k ":" {
      sub("^" k ":[[:space:]]*", "")
      sub(/[[:space:]]+#.*$/, "")
      gsub(/^["'"'"']|["'"'"']$/, "")
      sub(/[[:space:]]+$/, "")
      print; exit
    }'
}

STREAM="$(parse "$PLAN")"
FM="$(fm_block "$PLAN")"

SESSIONS="$(printf '%s\n' "$STREAM" | awk -v US="$US" -F"$US" '$2 == "_block" { print $1 }')"
NSESS="$(printf '%s\n' "$SESSIONS" | grep -c '^S[0-9]' || true)"

# CANNOT RUN is not CLEAN. A plan with no session blocks is not a plan that needs nothing
# done; it is a file this gate did not understand, and reporting green over it is the
# failure every fixture suite in this repo exists to prevent.
if [ "$NSESS" -eq 0 ]; then
  printf 'no `## Session S<N>:` blocks in %s — refusing to report green over a plan with no sessions\n' "$PLAN" >&2
  exit 2
fi
if [ -z "$FM" ]; then
  printf 'no YAML frontmatter in %s — nothing to check rule 1 against\n' "$PLAN" >&2
  exit 2
fi

# field <sid> <key> -> value (first match)
field() {
  printf '%s\n' "$STREAM" | awk -v US="$US" -v s="$1" -v k="$2" -F"$US" \
    '$1 == s && $2 == k { print $3; exit }'
}
# has_field <sid> <key> -> 0 if the key line exists at all
has_field() {
  printf '%s\n' "$STREAM" | awk -v US="$US" -v s="$1" -v k="$2" -F"$US" \
    '$1 == s && $2 == k { found = 1 } END { exit !found }'
}
# values <sid> <key> -> every value for a repeating key
values() {
  printf '%s\n' "$STREAM" | awk -v US="$US" -v s="$1" -v k="$2" -F"$US" \
    '$1 == s && $2 == k { print $3 }'
}

# ── RULE 1 — frontmatter, the spec citation, and the explicitly-unset keys ─────────
FM_REQUIRED="type plan_id service spec_service spec_version spec_sha256 spec_admitted_at spec_max_sessions status autonomy_level spend_ceiling_usd sessions_total department"
missing=""
blank=""
for k in $FM_REQUIRED; do
  if ! fm_has "$k" "$FM"; then missing="$missing $k"
  elif [ -z "$(fm_get "$k" "$FM")" ]; then blank="$blank $k"; fi
done
[ -n "$missing" ] && v "RULE 1  frontmatter is missing required key(s):$missing"
[ -n "$blank" ]   && v "RULE 1  frontmatter key(s) present but empty:$blank — an empty key and an absent one must not mean the same thing"

fm_type="$(fm_get type "$FM")"
[ -n "$fm_type" ] && [ "$fm_type" != "service-plan" ] && \
  v "RULE 1  type is '$fm_type', not 'service-plan'"

fm_sha="$(fm_get spec_sha256 "$FM")"
if [ -n "$fm_sha" ] && ! printf '%s' "$fm_sha" | grep -qE '^[0-9a-f]{64}$'; then
  v "RULE 1  spec_sha256 '$fm_sha' is not a 64-character lowercase hex digest — the plan cites its spec by a digest the ledger can RECONCILE, not by a path it can only assert"
fi

fm_status="$(fm_get status "$FM")"
if [ -n "$fm_status" ] && ! printf '%s\n' proposed approved running completed halted | grep -qxF -- "$fm_status"; then
  v "RULE 1  status '$fm_status' is not one of: proposed approved running completed halted"
fi

fm_budget="$(fm_get spec_max_sessions "$FM")"
if [ -n "$fm_budget" ] && [ "$fm_budget" != "none-declared" ] && ! printf '%s' "$fm_budget" | grep -qE '^[0-9]+$'; then
  v "RULE 1  spec_max_sessions '$fm_budget' is neither an integer nor the literal 'none-declared' — the intake format carries no budget field, so the absence is stated, never silent"
fi

# The two fields R1 and R2 have not ruled. `unset` is a legitimate, MACHINE-ACTIONABLE
# value: the driver refuses to auto-merge or to run unattended while it reads one. An
# ABSENT key is not — it is indistinguishable from "not applicable", which is how a missing
# ruling becomes a silent default. Failure closed, not open.
for k in autonomy_level spend_ceiling_usd; do
  val="$(fm_get "$k" "$FM")"
  if [ -n "$val" ] && [ "$val" = "unset" ]; then
    if ! grep -qE "^$k:.*(R1|R2|S[0-9])" "$PLAN"; then
      v "RULE 1  $k is 'unset' but names no deciding session — an unset field must say who rules it and when"
    fi
  fi
done

# ── RULE 11 — an approval names its approver and its date ─────────────────────────
# Added because the gap was observed rather than imagined.
#
# The design said "Merge flips frontmatter status to approved. Only an approved plan on main
# may be executed." NOTHING PERFORMS THAT SENTENCE. The owner read the first plan and merged
# its PR (the pipeline's first live human gate, passed) and `main` still carried
# `status: proposed` with `approved_by` and `approved_on` empty, because the sentence is in
# the passive voice and names no actor. The approval existed in a merge commit and nowhere in
# the artifact the driver re-reads at every session boundary.
#
# Flipping the field by hand closes that instance and opens a worse one: a plan can then claim
# `status: approved` with no approver and no date, and before this rule existed that file
# exited 0 here. Verified by running the gate against exactly such a file, not assumed.
#
# So: an approval is a claim about a PERSON and a DATE, and a claim with neither is not an
# approval, it is a word. This rule is the gate half. The execution-time half — refusing to
# run a plan whose status is not `approved` — is the driver's, at pipeline S5, because only
# the driver knows it is about to execute something.
if [ "$fm_status" = "approved" ]; then
  for k in approved_by approved_on; do
    if ! fm_has "$k" "$FM"; then
      v "RULE 11 status is 'approved' but there is no '$k' key at all"
    elif [ -z "$(fm_get "$k" "$FM")" ]; then
      v "RULE 11 status is 'approved' but '$k' is empty — an approval with no approver or no date is a word, not a decision; §4.4's \"merge flips the status\" names no actor and nothing performs it"
    fi
  done
fi

# ── RULES 2, 3, 4, 5, 6, 10 — per session ─────────────────────────────────────────
RISK_CLASSES="code-only infra secrets public-surface data-migration billing delete"

while IFS= read -r s; do
  [ -n "$s" ] || continue

  # RULE 2 — a done-criterion that a machine can decide.
  cmd="$(field "$s" "gate.command")"
  if ! has_field "$s" "gate.command"; then
    v "RULE 2  $s: no gate command — a session with no machine-decidable done-criterion cannot be driven"
  elif [ -z "$cmd" ]; then
    v "RULE 2  $s: gate command is empty"
  fi

  # RULE 3 — the boundary conditions that travel WITH the done-criterion.
  if ! has_field "$s" "gate.must_not"; then
    v "RULE 3  $s: no gate must_not — a done-criterion without boundary conditions passes on work that did the right thing and broke something else"
  elif [ -z "$(field "$s" "gate.must_not")" ]; then
    v "RULE 3  $s: gate must_not is empty"
  fi

  # RULE 4 — artifacts are paths. A prose artifact cannot be checked for existence, which
  # is the entire point of listing it.
  #
  # GOTCHA: the test is the path CHARSET, not "contains a / or a .". A first draft of this
  # rule demanded a directory separator or an extension and rejected the clean fixture's
  # own `coverage-floors` — which is a real file at the root of every service repo in this
  # estate, as are `Dockerfile` and `openapi.yaml`'s neighbours. A bare filename at a repo
  # root IS a path. What actually separates a path from prose is whitespace, so that is
  # what is tested.
  arts="$(values "$s" artifact)"
  if [ -z "$arts" ]; then
    v "RULE 4  $s: no artifacts listed — a session whose output is not a path leaves nothing to verify"
  else
    while IFS= read -r a; do
      [ -n "$a" ] || continue
      if ! printf '%s' "$a" | grep -qE '^[A-Za-z0-9._][A-Za-z0-9._/-]*$'; then
        v "RULE 4  $s: artifact is not a path: '$a' — an artifact that cannot be tested for existence leaves nothing to verify, which is the whole reason it is listed"
      fi
    done <<< "$arts"
  fi

  # RULE 5 — both boundaries. scope_out is the half that is quietly dropped, and it is the
  # half that says what the session must leave alone.
  for k in scope_in scope_out; do
    if ! has_field "$s" "$k"; then
      v "RULE 5  $s: no $k"
    elif [ -z "$(field "$s" "$k")" ]; then
      v "RULE 5  $s: $k is empty"
    fi
  done

  # RULE 6 — the failure fallback: a bounded retry and an escalation that is never a
  # continuation.
  rc="$(field "$s" retry_cap)"
  if ! has_field "$s" retry_cap; then
    v "RULE 6  $s: no retry_cap — an unbounded retry is an unbounded spend surface"
  elif ! printf '%s' "$rc" | grep -qE '^[0-9]+$'; then
    v "RULE 6  $s: retry_cap '$rc' is not an integer"
  fi
  oe="$(field "$s" on_exhaustion)"
  if ! has_field "$s" on_exhaustion; then
    v "RULE 6  $s: no on_exhaustion"
  elif [ "$oe" != "escalate" ]; then
    v "RULE 6  $s: on_exhaustion is '$oe', not 'escalate' — a plan that continues past an exhausted retry cap has no stop condition"
  fi

  # RULE 10 — the fields that make the block executable and writable-back-to by the driver.
  rk="$(field "$s" risk_class)"
  if ! has_field "$s" risk_class; then
    v "RULE 10 $s: no risk_class — the autonomy ratchet (R1) keys on it"
  elif ! printf '%s\n' $RISK_CLASSES | grep -qxF -- "$rk"; then
    v "RULE 10 $s: risk_class '$rk' is not one of: $RISK_CLASSES"
  fi
  for k in status evidence depends_on human_only_actions_before; do
    has_field "$s" "$k" || \
      v "RULE 10 $s: no '$k' key — the driver writes status and evidence, and a missing human_only_actions_before is an H-item that silently stops gating"
  done
  if ! has_field "$s" prompt; then
    v "RULE 10 $s: no prompt"
  elif [ -z "$(values "$s" prompt_line)" ]; then
    v "RULE 10 $s: prompt is empty"
  fi
done <<< "$SESSIONS"

# ── RULE 7 — sessions_total is consistent, and within budget if one exists ─────────
fm_total="$(fm_get sessions_total "$FM")"
if [ -n "$fm_total" ]; then
  if ! printf '%s' "$fm_total" | grep -qE '^[1-9][0-9]*$'; then
    v "RULE 7  sessions_total '$fm_total' is not a positive integer"
  elif [ "$fm_total" -ne "$NSESS" ]; then
    v "RULE 7  sessions_total is $fm_total but the plan contains $NSESS session block(s)"
  elif [ -n "$fm_budget" ] && [ "$fm_budget" != "none-declared" ] && [ "$fm_total" -gt "$fm_budget" ]; then
    v "RULE 7  sessions_total $fm_total exceeds the declared budget spec_max_sessions=$fm_budget"
  fi
fi

# ── RULES 8 and 9 — the dependency graph ──────────────────────────────────────────
# Rule 9 is fed ONLY edges whose endpoints are both declared sessions. Without that guard a
# single typo'd dependency would trip 8 AND 9, and a fixture that fires two rules proves
# neither — the discrimination assertion in the suite is what forces this.
EDGES=""
while IFS= read -r s; do
  [ -n "$s" ] || continue
  deps="$(field "$s" depends_on)"
  deps="$(printf '%s' "$deps" | tr -d '[]' | tr ',' ' ')"
  for d in $deps; do
    [ -n "$d" ] || continue
    if ! printf '%s\n' "$SESSIONS" | grep -qxF -- "$d"; then
      v "RULE 8  $s: depends_on '$d', which is not a session declared in this plan"
    else
      EDGES="${EDGES}${s} ${d}"$'\n'
    fi
  done
done <<< "$SESSIONS"

if [ -n "$EDGES" ]; then
  cyc="$(printf '%s' "$EDGES" | awk '
    { dep[$1 SUBSEP $2] = 1; node[$1] = 1; node[$2] = 1 }
    END {
      total = 0
      for (n in node) total++
      changed = 1
      settled = 0
      while (changed) {
        changed = 0
        for (n in node) {
          if (done[n]) continue
          ok = 1
          for (m in node) if ((n SUBSEP m) in dep && !done[m]) { ok = 0; break }
          if (ok) { done[n] = 1; settled++; changed = 1 }
        }
      }
      if (settled < total) {
        s = ""
        for (n in node) if (!done[n]) s = s " " n
        print s
      }
    }')"
  if [ -n "$cyc" ]; then
    v "RULE 9  the depends_on graph has a cycle among:$cyc — a plan that cannot be topologically ordered cannot be run in any order"
  fi
fi

# ── verdict ───────────────────────────────────────────────────────────────────────
if [ "$violations" -ne 0 ]; then
  printf '\n%s::error::plan-critic (mechanical) found %s violation(s) in %s%s\n' "$RED" "$violations" "$PLAN" "$RST"
  printf '  This is the half a script can decide. Passing it is not review — see\n'
  printf '  .claude/agents/plan-critic.md for the half that is judgement.\n'
  exit 1
fi
printf '  %splan-critic clean%s — %s session(s) in %s: every gate command and must_not present,\n' \
  "$GREEN" "$RST" "$NSESS" "$PLAN"
printf '  every artifact a path, both scope boundaries set, retry capped and escalating,\n'
printf '  sessions_total consistent, dependencies resolved, no cycle, any approval signed and dated.\n'
printf '  %sMechanical only.%s Whether the decomposition is RIGHT is the agent'"'"'s call.\n' "$BOLD" "$RST"
exit 0
