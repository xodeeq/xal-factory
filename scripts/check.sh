#!/usr/bin/env bash
#
# scripts/check.sh — the single source of truth for "the gates" (the process repo).
#
# CI (.github/workflows/ci.yml) invokes this exact script, so "green locally" equals "green
# in CI" byte for byte. To change a gate, change this script, not the workflow. The only
# thing a workflow may add is an INPUT a gate needs, and every such input is declared in
# .xal/gate-inputs, which gate 0 checks against every caller. See spec/gate-discipline.md.
#
# This repo is docs/tooling/process — there is no application, no compiler and no TDD gate.
# Its quality bar is the clauses CLAUDE.md names, turned into checks. THE SCRIPT IS THE LIST:
# read the gate names off the `gate` calls at the bottom, never off a prose tally.
#
# GOTCHA (gate 2, the rule that pays for this script): a file in sync/manifest is copied
# VERBATIM into a consumer's docs/process/. Its links travel with it but its neighbours do
# not — inside a consumer, `../` resolves to that repo's docs/, not to this repo's root. So a
# link can be correct here and broken in every consumer at once, and it looks fine to anyone
# reviewing it here. That is not hypothetical: three such links shipped and reached a
# consumer before a link check caught them. Gate 2 checks the VENDORED context, not just
# local resolution.
#
# GOTCHA (gate 1, deciding what counts as a citation): CLAUDE.md's prime directive allows a
# language-specific token in the spec ONLY inside a labelled reference citation. "Inside a
# citation" has to be mechanically decidable or the gate is a fuzzy heuristic, so three
# markers are canonical:
#   - "**Reference:**" / "**Reference.**" start a citation region, which runs to the end of
#     that bullet (indented continuations) or, for the paragraph form, to the next blank line;
#   - "<!-- reference -->" anywhere in a blank-line-delimited paragraph exempts that whole
#     paragraph — the escape hatch for an illustration that legitimately sits inside
#     normative prose (a multi-language example list, a gotcha naming the tool that hit it);
#   - "<!-- informative" in the first ten lines of a file exempts the whole FILE. This is
#     for the lifecycle guide, which names tools per language by design. It is reviewable
#     (it sits at the top of the file) and it is printed by the gate whenever it applies.
# A hit outside all three is a leak and fails the gate.
#
# GOTCHA (gate 3, the scaffold's forward references): the scaffold links into
# docs/process/<file> for files that do NOT exist in the scaffold — its docs/process/ is an
# empty landing dir until a seeded repo runs its first sync. Those links are correct by
# design, so they are validated against sync/manifest rather than against the filesystem.
# That is STRICTER than a file check: it also catches a scaffold link to a spec file nobody
# vendors, which would dangle forever in every real consumer.
#
# Usage:  scripts/check.sh        (from anywhere; it cd's to the repo root)
# Exit:   0 all gates passed · 1 a gate failed
# Deps:   bash, awk, grep, diff, mktemp — deliberately no language runtime, in a repo
#         whose entire purpose is to stay language-agnostic. Gate 5 additionally needs the
#         `claude` CLI, declared in .xal/gate-inputs.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MANIFEST="sync/manifest"
SYNC="sync/process-sync.sh"

# The leak pattern: tokens that name one language's tooling. A hit in normative spec prose
# means a rule has been stated in one language's terms, which is not a process rule yet.
# This is the ONE place the pattern lives; CLAUDE.md points here rather than restating it.
# Add to it when a leak slips past it; each alternative is a token that has actually leaked
# somewhere or plausibly would.
LEAK_RE='\bdotnet\b|\.csproj|\bNuGet\b|\bxUnit\b|\bnpm\b|\bnode_modules\b|package\.json|\bpip\b|\bpytest\b|requirements\.txt|\bgofmt\b|\bgo\.mod\b|golangci|\bcargo\b|Cargo\.toml|\bmaven\b|pom\.xml|\bgradle\b|\bGemfile\b|composer\.json'

# --- pretty output -----------------------------------------------------------
if [ -t 1 ]; then BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YEL=$'\033[33m'; RST=$'\033[0m'
else BOLD=""; RED=""; GREEN=""; YEL=""; RST=""; fi

PASSED=()
FAILED=""

banner() { printf '\n%s━━ %s%s\n' "$BOLD" "$1" "$RST"; }

gate() {
  local name="$1"; shift
  banner "$name"
  if "$@"; then
    PASSED+=("$name")
    printf '%s✔ %s%s\n' "$GREEN" "$name" "$RST"
  else
    FAILED="$name"
    printf '%s✗ %s — FAILED%s\n' "$RED" "$name" "$RST"
    summary
    exit 1
  fi
}

summary() {
  printf '\n%s──────── gate summary ────────%s\n' "$BOLD" "$RST"
  for p in "${PASSED[@]:-}"; do
    [ -n "$p" ] && printf '  %s✔%s %s\n' "$GREEN" "$RST" "$p"
  done
  if [ -n "$FAILED" ]; then
    printf '  %s✗%s %s\n' "$RED" "$RST" "$FAILED"
    printf '\n%sCHECK FAILED%s at: %s\n' "$RED$BOLD" "$RST" "$FAILED"
  else
    printf '\n%sALL GATES PASSED%s\n' "$GREEN$BOLD" "$RST"
  fi
}

# --- shared helpers ----------------------------------------------------------

# The vendored set: the files sync/manifest names (comments/blanks stripped).
manifest_files() {
  sed 's/#.*//' "$MANIFEST" | tr -d '[:blank:]' | grep -v '^$'
}

# Every markdown-ish file in the repo, excluding .git and the fixture trees under gates/.
# CLAUDE.md.template is included because it is real content that ships in the scaffold.
# The fixture trees are excluded because their whole purpose is to be broken: a fixture
# that reintroduces a dangling link must not fail the real gate 2.
md_files() {
  find . -path ./.git -prune -o -path ./gates/fixtures -prune -o \
       \( -name '*.md' -o -name '*.md.template' \) -print \
    | sed 's|^\./||' | sort
}

# Split by scaffold membership. These exist as functions rather than inline `case`
# filters because a `)` in a case pattern closes an enclosing <( … ) substitution.
scaffold_md_files()     { md_files | grep '^scaffold/'    || true; }
non_scaffold_md_files() { md_files | grep -v '^scaffold/' || true; }

# Emit "file<TAB>line<TAB>target" for every markdown inline link in $1.
# Anchors and absolute URLs are dropped here; callers only see path-ish targets.
extract_links() {
  awk -v F="$1" '
    {
      line = $0
      while (match(line, /\]\([^)]+\)/)) {
        tgt = substr(line, RSTART + 2, RLENGTH - 3)
        line = substr(line, RSTART + RLENGTH)
        sub(/#.*$/, "", tgt)                  # strip anchor
        sub(/[[:space:]].*$/, "", tgt)        # strip a title after the path
        if (tgt == "") continue
        if (tgt ~ /^(https?|mailto):/) continue
        printf "%s\t%d\t%s\n", F, NR, tgt
      }
    }' "$1"
}

# --- gate 1: language-agnostic spec ------------------------------------------
# Every LEAK_RE hit in spec/ must sit inside a citation region, an escaped paragraph, or an
# informative file (see GOTCHA above). Anything else is a language-specific rule.
spec_language_agnostic_step() {
  local fail=0 f out hits allowed scanned=0 informative=""
  for f in $(manifest_files); do
    if head -10 "spec/$f" | grep -q '<!-- informative'; then
      informative="${informative}${f} "
      continue
    fi
    scanned=$((scanned + 1))
    # GOTCHA: LEAK_RE uses \b, which grep -E supports and awk does NOT (POSIX awk reads \b
    # as backspace, so `\bdotnet\b` silently matches nothing). So grep finds the hits and awk
    # only computes which lines are excused; keeping one pattern, evaluated by the one engine
    # that understands it.
    hits="$(grep -nE "$LEAK_RE" "spec/$f" | cut -d: -f1)"
    [ -z "$hits" ] && continue
    allowed="$(awk '
      { L[NR] = $0 }
      END {
        # Pass 1 — mark citation regions.
        inregion = 0; shapeB = 0
        for (i = 1; i <= NR; i++) {
          l = L[i]
          if (l ~ /^[[:space:]]*([-*][[:space:]]+)?\*\*Reference[:.]\*\*/) {
            inregion = 1; shapeB = (l ~ /^\*\*/); cite[i] = 1; continue
          }
          if (!inregion) continue
          if (l ~ /^[[:space:]]*$/) {
            # A blank ends a paragraph-form region; for the bullet form, keep going
            # only if the next non-blank line is still an indented continuation.
            if (shapeB) { inregion = 0; continue }
            j = i + 1
            while (j <= NR && L[j] ~ /^[[:space:]]*$/) j++
            if (j <= NR && L[j] ~ /^[[:space:]][[:space:]]+[^[:space:]]/) { cite[i] = 1; continue }
            inregion = 0; continue
          }
          # Paragraph form: the region runs to the next blank line, whatever the lines
          # look like — wrapped prose at column 0, or a bullet list under the marker. The
          # clean fixture caught the earlier version ending the region at the first
          # wrapped line, which contradicted the documented rule above.
          if (shapeB) { cite[i] = 1; continue }
          # Bullet form: only indented continuations of that bullet stay in the region.
          if (l ~ /^[[:space:]][[:space:]]+[^[:space:]]/) { cite[i] = 1; continue }
          inregion = 0
        }
        # Pass 2 — mark paragraphs carrying the explicit escape comment.
        start = 1
        for (i = 1; i <= NR + 1; i++) {
          if (i > NR || L[i] ~ /^[[:space:]]*$/) {
            esc = 0
            for (j = start; j < i; j++) if (L[j] ~ /<!--[[:space:]]*reference[[:space:]]*-->/) esc = 1
            if (esc) for (j = start; j < i; j++) exempt[j] = 1
            start = i + 1
          }
        }
        # Pass 3 — emit the line numbers that are excused.
        for (i = 1; i <= NR; i++) if (cite[i] || exempt[i]) print i
      }' "spec/$f")"

    # A hit that is not in the excused set is a leak. Set difference via grep -vxF, not
    # comm: comm assumes LEXICALLY sorted input, and line numbers sort differently
    # numerically ("127" < "30" lexically) — feeding it `sort -n` silently mis-pairs.
    # Guard the empty case: an empty pattern list would make grep -vxF drop everything.
    if [ -z "$allowed" ]; then
      out="$(printf '%s\n' $hits)"
    else
      out="$(printf '%s\n' $hits | grep -vxF -f <(printf '%s\n' $allowed) || true)"
    fi
    out="$(printf '%s\n' $out | sort -n -u | while read -r n; do
               [ -n "$n" ] && printf '    spec/%s:%s: %s\n' "$f" "$n" \
                 "$(sed -n "${n}p" "spec/$f" | cut -c1-100)"
             done)"
    if [ -n "$out" ]; then
      printf '%s  LEAK — language-specific token outside a reference citation:%s\n' "$RED" "$RST"
      printf '%s\n' "$out"
      fail=1
    fi
  done
  if [ "$scanned" -eq 0 ]; then
    printf '%s  every manifest file is marked informative — refusing to report green over nothing%s\n' "$RED" "$RST"
    return 1
  fi
  if [ "$fail" -ne 0 ]; then
    printf '\n%s::error::spec/ states a language-specific token as a process rule%s\n' "$RED" "$RST"
    printf '  Fix: move it into a "**Reference:**" / "**Reference.**" citation, or mark the\n'
    printf '  paragraph with <!-- reference --> if it is an illustration in prose.\n'
    return 1
  fi
  printf '  no language-specific tokens outside a reference citation (%s normative file(s) scanned' "$scanned"
  [ -n "$informative" ] && printf '; informative, skipped: %s' "$(printf '%s' "$informative" | sed 's/ $//')"
  printf ')\n'
  return 0
}

# --- gate 2: links resolve + the vendored-set rule ----------------------------
# (a) every relative link outside the scaffold resolves to a real path;
# (b) a manifest file may only link relatively to another file in the vendored set.
links_resolve_step() {
  local fail=0 f line tgt dir vendored vset
  vendored="$(manifest_files)"
  # Space-delimited one-liner so membership is a bash `case` glob, not a grep fork.
  # These loops run once per link, so anything forking inside them costs real time.
  vset=" $(printf '%s ' $vendored)"

  # (a) resolution — scaffold is gate 3's job (its forward references are legitimate).
  while IFS=$'\t' read -r f line tgt; do
    [ -z "${f:-}" ] && continue
    dir="${f%/*}"; [ "$dir" = "$f" ] && dir="."
    if [ ! -e "$dir/$tgt" ]; then
      printf '%s  UNRESOLVED  %s:%s -> %s%s\n' "$RED" "$f" "$line" "$tgt" "$RST"
      fail=1
    fi
  done < <(for f in $(non_scaffold_md_files); do extract_links "$f"; done)

  # (b) the vendored-set rule — the check that would have caught the original bug.
  for f in $vendored; do
    while IFS=$'\t' read -r sf line tgt; do
      [ -z "${sf:-}" ] && continue
      # Legal iff it is a bare sibling naming another vendored file: the whole set
      # lands flat in the consumer's docs/process/.
      case "$tgt" in
        */*)        : ;;                                  # any path segment escapes
        *) case "$vset" in *" $tgt "*) continue ;; esac ;; # a vendored sibling: fine
      esac
      printf '%s  ESCAPES VENDORED SET  spec/%s:%s -> %s%s\n' "$RED" "$f" "$line" "$tgt" "$RST"
      fail=1
    done < <(extract_links "spec/$f")
  done

  if [ "$fail" -ne 0 ]; then
    printf '\n%s::error::a link is broken, or a vendored file links outside the vendored set%s\n' "$RED" "$RST"
    printf '  A manifest file is copied verbatim into a consumer, where ../ means that\n'
    printf '  repo'"'"'s docs/. Use an absolute https://github.com/xodeeq/xal-engineering-process/...\n'
    printf '  URL instead. See sync/SYNC.md "What'"'"'s in scope to sync".\n'
    return 1
  fi
  printf '  all relative links resolve; no vendored file links outside the vendored set\n'
  return 0
}

# --- gate 3: scaffold self-consistency ----------------------------------------
# The scaffold is the seed for every new repo, so a broken link there is inherited by every
# future repo. Its docs/process/ links are forward references validated against the
# manifest (see GOTCHA above).
scaffold_consistency_step() {
  local fail=0 f line tgt dir base vendored
  vendored="$(manifest_files)"

  # (a) every file the manifest names actually exists in spec/.
  for f in $vendored; do
    if [ ! -f "spec/$f" ]; then
      printf '%s  MANIFEST NAMES A MISSING FILE  spec/%s%s\n' "$RED" "$f" "$RST"
      fail=1
    fi
  done

  # (b) scaffold links: real files, or forward references into docs/process/.
  while IFS=$'\t' read -r f line tgt; do
    [ -z "${f:-}" ] && continue
    dir="$(dirname "$f")"
    [ -e "$dir/$tgt" ] && continue
    # Forward reference? Resolve it and see if it lands on docs/process/<vendored>.
    case "$tgt" in
      */docs/process/*|docs/process/*|*/process/*)
        base="$(basename "$tgt")"
        if printf '%s\n' $vendored | grep -qx -- "$base"; then continue; fi
        printf '%s  SCAFFOLD LINKS A FILE THAT IS NEVER VENDORED  %s:%s -> %s%s\n' \
          "$RED" "$f" "$line" "$tgt" "$RST"
        printf '    (%s is not in sync/manifest, so it will dangle in every seeded repo)\n' "$base"
        fail=1
        continue ;;
    esac
    printf '%s  UNRESOLVED  %s:%s -> %s%s\n' "$RED" "$f" "$line" "$tgt" "$RST"
    fail=1
  done < <(for f in $(scaffold_md_files); do extract_links "$f"; done)

  if [ "$fail" -ne 0 ]; then
    printf '\n%s::error::the scaffold is not self-consistent — every new repo inherits this%s\n' "$RED" "$RST"
    return 1
  fi
  printf '  manifest ⊆ spec/; scaffold links resolve (docs/process/ ones checked against the manifest)\n'
  return 0
}

# --- gate 4: sync round-trip ---------------------------------------------------
# Prove the mechanism itself still works: vendor into a throwaway consumer, then assert
# --check reports no drift against it. Catches a broken process-sync.sh, a manifest naming
# a missing file, and a --check that has stopped actually comparing anything.
sync_roundtrip_step() {
  local tmp rc
  [ -x "$SYNC" ] || { printf '%s  %s is missing or not executable%s\n' "$RED" "$SYNC" "$RST"; return 1; }
  tmp="$(mktemp -d)" || return 1
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  ( cd "$tmp" && "$ROOT/$SYNC" "$ROOT" ) || {
    printf '%s  sync into a throwaway consumer FAILED%s\n' "$RED" "$RST"; return 1; }

  ( cd "$tmp" && "$ROOT/$SYNC" "$ROOT" --check ); rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '%s  --check reports drift immediately after a clean sync (exit %s)%s\n' "$RED" "$rc" "$RST"
    return 1
  fi

  # A sync that copies nothing would pass --check vacuously; assert it produced files.
  local want got
  want="$(manifest_files | wc -l | tr -d ' ')"
  got="$(find "$tmp/docs/process" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$want" != "$got" ]; then
    printf '%s  round-trip vendored %s file(s), manifest names %s%s\n' "$RED" "$got" "$want" "$RST"
    return 1
  fi
  printf '  sync → --check round-trip clean (%s files vendored, pinned %s)\n' "$got" "$(cat VERSION)"
  return 0
}

# --- gate 5: plugin manifests -----------------------------------------------------
# This repo is a plugin MARKETPLACE as well as a spec source: `.claude-plugin/
# marketplace.json` plus one plugin per directory under `plugins/`. A malformed manifest
# does not fail loudly — the runtime skips what it cannot parse — so a consuming repo would
# simply not get the commands and skills, silently, and nothing would say why.
#
# GOTCHA: the published schema reference and the validator have DISAGREED, and the
# validator is what actually loads the plugin. So validate with the tool, never against the
# documentation. `--strict` turns warnings into failures, which is what a gate wants — an
# ignored field is a silently missing feature.
#
# Skipped (with a warning) when the `claude` CLI is unavailable: mandatory under CI=true,
# courteous locally (spec/gate-discipline.md §3).
plugin_manifests_step() {
  if ! command -v claude >/dev/null 2>&1; then
    if [ "${CI:-}" = "true" ]; then
      printf '%sThe claude CLI is required in CI to validate plugin manifests.%s\n' "$RED" "$RST"
      return 1
    fi
    printf '%s⚠ claude CLI unavailable — SKIPPING plugin manifest validation.%s\n' "$YEL" "$RST"
    printf '%s  (This gate is mandatory in CI.)%s\n' "$YEL" "$RST"
    return 0
  fi

  local rc=0 target n=0
  # The marketplace manifest itself.
  if claude plugin validate . --strict >/dev/null 2>&1; then
    printf '  %s✔%s marketplace manifest\n' "$GREEN" "$RST"
  else
    printf '  %s✗%s marketplace manifest\n' "$RED" "$RST"
    claude plugin validate . --strict 2>&1 | sed 's/^/      /'
    rc=1
  fi
  # Every plugin in the catalogue. Zero plugins is a failure: a marketplace with nothing in
  # it is not a marketplace, and an empty loop would pass vacuously.
  for target in plugins/*/; do
    [ -d "$target" ] || continue
    n=$((n + 1))
    if claude plugin validate "$target" --strict >/dev/null 2>&1; then
      printf '  %s✔%s %s\n' "$GREEN" "$RST" "${target%/}"
    else
      printf '  %s✗%s %s\n' "$RED" "$RST" "${target%/}"
      claude plugin validate "$target" --strict 2>&1 | sed 's/^/      /'
      rc=1
    fi
  done
  if [ "$n" -eq 0 ]; then
    printf '  %s✗%s plugins/ holds no plugin — refusing to report green over nothing\n' "$RED" "$RST"
    rc=1
  fi
  return "$rc"
}

# --- gate 0: gate inputs are declared and every caller supplies them --------------
# The meta-gate. Gate 5 above needs the `claude` CLI, which is NOT in this repo — and the
# first time such a gate was added, the workflow was not updated to install it, so the gate
# failed on its first CI run. Days earlier the identical shape had blocked production
# deploys elsewhere for hours. Both times because a gate script declares an input in code
# but nowhere as data, and cannot see its own callers.
#
# .xal/gate-inputs declares them; .xal/check-gate-inputs.sh derives what this script
# actually needs, asserts it is declared, and asserts every workflow invoking this script
# supplies it. Running FIRST and needing NO inputs of its own is deliberate: a check that
# catches missing inputs must not be able to have one missing.
gate_inputs_step() {
  [ -f .xal/check-gate-inputs.sh ] || {
    printf '%s  .xal/check-gate-inputs.sh is missing%s\n' "$RED" "$RST"; return 1; }
  bash .xal/check-gate-inputs.sh
}

# --- gates 6 + 7: the scaffold actually seeds a working gate ----------------------------
# ADR-0002 makes scaffold/ the mechanism by which a new repo arrives with its gate. That
# turns "the scaffold ships a gate script" from a sentence into a property, and gate 3 above
# does not cover it: gate 3 checks that the scaffold's LINKS resolve, not that a language
# overlay is complete enough to produce a repo whose CI runs anything.
#
# A missing file in an overlay is silent in the worst way — the seeded repo still builds and
# still goes green, it simply enforces less than everyone believes. check-seed-set.sh
# enumerates what an overlay must ship, and asserts by EXECUTION that the seeder refuses to
# default a language, because a default would put a stack decision in a script.
#
# Paired with its fixture harness, in that order: the fixtures run FIRST, so "the rule is
# broken" is never mistaken for "the scaffold is broken".
seed_fixtures_step() { bash gates/seed.test.sh; }
seed_set_step()      { bash scripts/check-seed-set.sh; }

# --- run the gates -------------------------------------------------------------
gate "gate inputs declared + every caller wired"            gate_inputs_step
gate "plugin manifests (claude plugin validate --strict)"   plugin_manifests_step
gate "language-agnostic spec (no language-specifics as rules)" spec_language_agnostic_step
gate "links resolve (+ vendored-set rule)"                  links_resolve_step
gate "scaffold self-consistency"                            scaffold_consistency_step
gate "seed-set fixtures (proven able to fail)"              seed_fixtures_step
gate "seed sets complete (every language seeds a gate)"     seed_set_step
gate "sync round-trip"                                      sync_roundtrip_step

summary
