#!/usr/bin/env bash
#
# plan-read.sh — read ONE session out of docs/plan/plan.md, and nothing else.
#
# WHAT THIS IS NOT, STATED FIRST ---------------------------------------------------------
#
# This is NOT plan-critic-check.sh and must never become a copy of it. That script lives in
# the ops repo, validates a WHOLE plan against eleven rules, and answers "is this plan fit to
# put in front of the owner". This one answers a much smaller question — "what does session S<n>
# say?" — and is the only plan reader the driver has. ADR-0005 in the factory rejected copying
# the critic into each service repo while there is one consumer; that reasoning binds here.
#
# THE RISK THIS CREATES, NAMED RATHER THAN HIDDEN ----------------------------------------
#
# Two independent parsers now read one format, and nothing diffs them. If the plan format
# changes, the critic and this reader can disagree, and the disagreement is silent: the
# critic would pass a plan this reader misreads. The mitigation is that both are written to
# the SAME conventions, deliberately, and the three that matter are copied here as rules
# rather than as code:
#
#   1. Session blocks are `## Session S<n>: <title>` at column 0. Any other `## ` heading
#      ends the block.
#   2. A `prompt: |` block is indented prose that may contain lines starting with `- `.
#      Prompt mode ends ONLY on a line beginning `- ` or `## ` AT COLUMN 0 — an indented
#      `- ` inside the prompt is prompt content, not a field.
#   3. Frontmatter values carry inline comments (`autonomy_level: unset  # ruled by R1`).
#      Strip from the first ` #` to end of line. A reader that does not strip them compares
#      the whole annotation and the rule beneath it is skipped in silence, which is the
#      inert-rule failure this estate forbids. (plan-critic-check.sh hit exactly this.)
#
# Usage:
#   plan-read.sh --plan P --sessions                 list every declared session id
#   plan-read.sh --plan P --fm KEY                   a frontmatter value, comment-stripped
#   plan-read.sh --plan P --session SID --field KEY  a session field; repeating keys print
#                                                    one per line. Gate sub-keys are
#                                                    `gate.command` and `gate.must_not`;
#                                                    artifact paths are `artifact`.
#   plan-read.sh --plan P --session SID --prompt     the prompt block, one line per line
#
# Exit:  0 read it (an absent field prints nothing and still exits 0 — presence is the
#          caller's question, and preflight.sh asks it explicitly)
#        2 CANNOT RUN: no plan file, no frontmatter, or no session blocks. Never 0: a file
#          this reader did not understand is not a plan with nothing in it.
# Deps:  bash, awk, sed, grep. No network, no credential, no language runtime.

set -uo pipefail

PLAN=""
MODE=""
SID=""
KEY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --plan)     PLAN="$2"; shift 2 ;;
    --sessions) MODE="sessions"; shift ;;
    --fm)       MODE="fm"; KEY="$2"; shift 2 ;;
    --session)  SID="$2"; shift 2 ;;
    --field)    MODE="field"; KEY="$2"; shift 2 ;;
    --prompt)   MODE="prompt"; shift ;;
    *) printf 'plan-read.sh: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$PLAN" ] || { printf 'plan-read.sh: --plan is required\n' >&2; exit 2; }
[ -f "$PLAN" ] || { printf 'plan-read.sh: plan not found: %s\n' "$PLAN" >&2; exit 2; }
[ -n "$MODE" ] || { printf 'plan-read.sh: one of --sessions/--fm/--field/--prompt is required\n' >&2; exit 2; }

US=$'\037'   # unit separator. Chosen for the same reason plan-critic-check.sh chose it: a
             # must_not clause or a prompt line may legitimately contain `|`, and a
             # separator that can occur in a value truncates the record without saying so.

# --- the frontmatter block ----------------------------------------------------
fm_block() {
  awk 'NR==1 && $0 != "---" { exit }
       NR==1 { infm=1; next }
       infm && $0 == "---" { exit }
       infm { print }' "$PLAN"
}

FM="$(fm_block)"

# --- the session stream -------------------------------------------------------
# One record per field: SID <US> KEY <US> VALUE. See rules 1 and 2 in the header.
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
  ' "$PLAN"
}

STREAM="$(parse)"
SESSIONS="$(printf '%s\n' "$STREAM" | awk -v US="$US" -F"$US" '$2 == "_block" { print $1 }')"
NSESS="$(printf '%s\n' "$SESSIONS" | grep -c '^S[0-9]' || true)"

# CANNOT RUN is not CLEAN. A file with no frontmatter or no session blocks is one this
# reader did not understand, and returning empty answers over it would let the driver make
# decisions from silence.
if [ -z "$FM" ]; then
  printf 'plan-read.sh: no YAML frontmatter in %s\n' "$PLAN" >&2
  exit 2
fi
if [ "$NSESS" -eq 0 ]; then
  printf 'plan-read.sh: no `## Session S<N>:` blocks in %s\n' "$PLAN" >&2
  exit 2
fi

case "$MODE" in
  sessions)
    printf '%s\n' "$SESSIONS" | grep '^S[0-9]'
    ;;
  fm)
    # Rule 3: strip the inline comment. A `#` with no leading space stays — it can be part
    # of a value, and only the annotated form uses ` #`.
    printf '%s\n' "$FM" | awk -v k="$KEY" '
      $0 ~ "^" k ":" {
        sub("^" k ":[[:space:]]*", "")
        sub(/[[:space:]]+#.*$/, "")
        gsub(/^["'"'"']|["'"'"']$/, "")
        sub(/[[:space:]]+$/, "")
        print; exit
      }'
    ;;
  field)
    [ -n "$SID" ] || { printf 'plan-read.sh: --field needs --session\n' >&2; exit 2; }
    printf '%s\n' "$STREAM" | awk -v US="$US" -v s="$SID" -v k="$KEY" -F"$US" \
      '$1 == s && $2 == k { print $3 }'
    ;;
  prompt)
    [ -n "$SID" ] || { printf 'plan-read.sh: --prompt needs --session\n' >&2; exit 2; }
    printf '%s\n' "$STREAM" | awk -v US="$US" -v s="$SID" -F"$US" \
      '$1 == s && $2 == "prompt_line" { print $3 }'
    ;;
esac
exit 0
