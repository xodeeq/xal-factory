#!/usr/bin/env bash
#
# seed-service.sh — create a new service repo that arrives with its gate already working.
#
# WHY THIS EXISTS -------------------------------------------------------------------------
#
# The whole process rests on a gate script whose exit code decides pass. A repo created
# without one does not fail loudly — it emits green from a gate that is not there, which is
# indistinguishable from a passing build. Before this script, "every new repo begins with a
# gate" was left to whoever remembered. See adr/0002-repo-seeding.md.
#
# WHAT IT DOES ----------------------------------------------------------------------------
#
#   1. copies scaffold/common/ (everything language-agnostic — including the pipeline: the
#      driver, chain, merge and reader workflows, scripts/driver/, and their fixture suite)
#   2. overlays scaffold/lang/<lang>/ (the gate script, CI, the toolchain action, Dockerfile,
#      fixtures, .xal/protected-paths)
#   3. copies this repo's .xal/check-gate-inputs.sh (gate 0's checker)
#   4. renames *.template and the SERVICE path placeholder; substitutes <SERVICE> and <MODULE>
#   5. vendors the process spec via sync/process-sync.sh and pins the VERSION
#   6. writes .xal/seed.config recording the language, its deciding ADR, and the pin
#   7. git init + one commit, so the tree is pushable
#   8. prints the human-only actions that remain — and stops
#
# IT TAKES NO INPUTS OF ITS OWN beyond this process checkout: bash, tar, sed, find, git.
# Same discipline as process-sync.sh, and for the same reason — a seeding step that can need
# a toolchain is a seeding step that can be missing one.
#
# Usage:
#   scaffold/seed-service.sh --name <service> --lang <language> --dest <dir> [--module <path>] [--adr <path>] [--ops-repo <owner/name>] [--profile <conf>]
#
#   --name    the service name; becomes the repo name, the binary, and every <SERVICE> in
#             the seeded files
#   --lang    the language overlay to apply, from scaffold/lang/. NO DEFAULT — see below
#   --dest    where to create the repo. Must not already exist
#   --module  the module/package path for languages that need one (Go: the go.mod module).
#             Defaults to example.com/<name>; pass the real one so imports are right from
#             commit one
#   --adr     the path, inside the new repo, of the ADR that decided --lang. Recorded in
#             .xal/seed.config. Defaults to docs/adr/0001-stack-selection.md
#   --profile a factory profile (the ops repo's .xal/factory.conf): every service-scope option
#             it sets is copied into this repo's .xal/factory.conf. `xal-factory seed` passes it
#   --ops-repo the owner/name of the factory's ops repo (admitted specs, the spend ledger).
#             Written to .xal/factory.conf as factory.ops_repo. Optional here because a repo
#             can be seeded before its ops repo exists, but the driver refuses to run
#             without it, so the seeder prints it as a human-only step when it is absent
#
# THERE IS NO DEFAULT LANGUAGE, DELIBERATELY. A default language is a stack decision taken by
# a script. Stack selection is a human-gated, per-service decision recorded as that service's
# first ADR, chosen on that service's workload — so this script refuses to guess and exits 2.
#
# Exit: 0 seeded · 1 a step failed · 2 called wrongly (bad or missing arguments)

set -uo pipefail

PROCESS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAFFOLD="$PROCESS/scaffold"

if [ -t 1 ]; then BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YEL=$'\033[33m'; RST=$'\033[0m'
else BOLD=""; RED=""; GREEN=""; YEL=""; RST=""; fi

die()  { printf '%s%s%s\n' "$RED" "$1" "$RST" >&2; exit "${2:-1}"; }
step() { printf '\n%s━━ %s%s\n' "$BOLD" "$1" "$RST"; }
note() { printf '   %s\n' "$1"; }

languages() { find "$SCAFFOLD/lang" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort; }

usage() {
  cat >&2 <<EOF
usage: scaffold/seed-service.sh --name <service> --lang <language> --dest <dir> [--module <path>] [--adr <path>] [--ops-repo <owner/name>] [--profile <conf>]

  --lang has no default. Stack selection is a per-service, human-gated decision recorded as
  that service's first ADR; a script must not make it.

  languages available in scaffold/lang/:
$(languages | sed 's/^/    /')
EOF
}

NAME=""; LANG_ID=""; DEST=""; MODULE=""; ADR="docs/adr/0001-stack-selection.md"; OPS_REPO=""; PROFILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name)   NAME="${2:-}"; shift 2 ;;
    --lang)   LANG_ID="${2:-}"; shift 2 ;;
    --dest)   DEST="${2:-}"; shift 2 ;;
    --module) MODULE="${2:-}"; shift 2 ;;
    --adr)    ADR="${2:-}";  shift 2 ;;
    --ops-repo) OPS_REPO="${2:-}"; shift 2 ;;
    --profile)  PROFILE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf '%sunknown argument: %s%s\n' "$RED" "$1" "$RST" >&2; usage; exit 2 ;;
  esac
done

# --- argument validation; every failure here is exit 2, "called wrongly" ---------------
[ -n "$NAME" ] || { printf '%s--name is required%s\n' "$RED" "$RST" >&2; usage; exit 2; }
[ -n "$DEST" ] || { printf '%s--dest is required%s\n' "$RED" "$RST" >&2; usage; exit 2; }

if [ -z "$LANG_ID" ]; then
  printf '%s--lang is required and has NO DEFAULT.%s\n' "$RED" "$RST" >&2
  printf 'A default language would be a stack decision taken by a script. Stack selection is\n' >&2
  printf 'the per-service, human-gated decision recorded as that service ADR-0001 — pass the\n' >&2
  printf 'language that ADR chose.\n\n' >&2
  usage
  exit 2
fi

if [ ! -d "$SCAFFOLD/lang/$LANG_ID" ]; then
  printf '%sno language overlay at scaffold/lang/%s%s\n' "$RED" "$LANG_ID" "$RST" >&2
  printf 'available:\n' >&2
  languages | sed 's/^/  /' >&2
  printf '\nAdding a language is a PR that adds scaffold/lang/<name>/ with the full artifact\n' >&2
  printf 'set; scripts/check-seed-set.sh refuses a partial one.\n' >&2
  exit 2
fi

[ -e "$DEST" ] && die "destination already exists: $DEST (refusing to seed over it)" 2
[ -d "$SCAFFOLD/common" ] || die "scaffold/common/ is missing — this is not a process-repo checkout" 2
[ -f "$PROCESS/.xal/check-gate-inputs.sh" ] || die ".xal/check-gate-inputs.sh is missing from this checkout" 2
[ -x "$PROCESS/sync/process-sync.sh" ] || die "sync/process-sync.sh is missing or not executable" 2

[ -n "$MODULE" ] || MODULE="example.com/$NAME"
case "$OPS_REPO" in
  ""|*/*) : ;;
  *) printf '%s--ops-repo must be <owner>/<name>, got %s%s\n' "$RED" "$OPS_REPO" "$RST" >&2; exit 2 ;;
esac
VERSION="$(cat "$PROCESS/VERSION")"
[ -z "$PROFILE" ] || [ -f "$PROFILE" ] || { printf '%s--profile names no file: %s%s\n' "$RED" "$PROFILE" "$RST" >&2; exit 2; }
# shellcheck source=../factory/lib.sh
FACTORY_ROOT="$PROCESS" . "$PROCESS/factory/lib.sh" || die "factory/lib.sh is missing from this checkout" 2

printf '\n%sSeeding %s (%s) into %s%s\n' "$BOLD" "$NAME" "$LANG_ID" "$DEST" "$RST"

mkdir -p "$DEST" || die "could not create $DEST"
DEST="$(cd "$DEST" && pwd)"

# --- 1 + 2: the common tree, then the language overlay -----------------------------------
# tar rather than cp -r because it copies dotfiles predictably on both GNU and BSD, which
# matters: .claude/, .github/ and .xal/ are most of what a seeded repo is.
step "copying scaffold/common/, then scaffold/lang/$LANG_ID/"
( cd "$SCAFFOLD/common" && tar -cf - . ) | ( cd "$DEST" && tar -xf - ) || die "copying common/ failed"
( cd "$SCAFFOLD/lang/$LANG_ID" && tar -cf - . ) | ( cd "$DEST" && tar -xf - ) || die "copying lang/$LANG_ID/ failed"
note "$(find "$DEST" -type f | wc -l | tr -d ' ') files"

# --- 3: gate 0's checker -----------------------------------------------------------------
# Seeded from THIS repo's own copy rather than from a second copy kept in the scaffold, so
# there is one copy per repo and no extra replica pair to keep identical.
step "seeding .xal/check-gate-inputs.sh (gate 0's checker)"
mkdir -p "$DEST/.xal"
cp "$PROCESS/.xal/check-gate-inputs.sh" "$DEST/.xal/check-gate-inputs.sh" || die "copying the gate-input checker failed"
chmod +x "$DEST/.xal/check-gate-inputs.sh"
note "from $PROCESS/.xal/"

# --- 4: placeholders ----------------------------------------------------------------------
step "filling placeholders"

# Path placeholder first: a literal `SERVICE` path component becomes the service name, so
# cmd/SERVICE/ becomes cmd/<name>/. Deepest paths first, or renaming a parent invalidates the
# child paths still queued behind it.
while IFS= read -r p; do
  [ -n "$p" ] || continue
  mv "$p" "$(dirname "$p")/$NAME" || die "renaming $p failed"
done <<< "$(find "$DEST" -depth -name 'SERVICE' | sed '/^$/d')"

# *.template -> the real filename. `.gitignore.template` -> `.gitignore` falls out of the
# same rule, which is why it is named that way in the scaffold rather than `gitignore.template`.
while IFS= read -r t; do
  [ -n "$t" ] || continue
  mv "$t" "${t%.template}" || die "renaming $t failed"
done <<< "$(find "$DEST" -type f -name '*.template' | sed '/^$/d')"

# <SERVICE> -> the service name, <MODULE> -> the module path and <VERSION> -> the process
# version (the reader's pinned plugin tag defaults to it), in every text file.
#
# GOTCHA: `sed -i` differs between GNU and BSD (BSD requires an argument to -i, GNU must not
# have one). Writing to a temp file and moving it back works identically on both, and this
# script runs on a developer's macOS as often as on a runner.
subst=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -qE '<SERVICE>|<MODULE>|<VERSION>' "$f" 2>/dev/null || continue
  sed "s|<SERVICE>|$NAME|g; s|<MODULE>|$MODULE|g; s|<VERSION>|$VERSION|g" "$f" > "$f.seedtmp" && mv "$f.seedtmp" "$f" || die "substituting in $f failed"
  subst=$((subst + 1))
done <<< "$(find "$DEST" -type f ! -path '*/.git/*')"
note "<SERVICE> -> $NAME, <MODULE> -> $MODULE, <VERSION> -> $VERSION in $subst file(s)"

chmod +x "$DEST/scripts/"*.sh "$DEST/scripts/driver/"*.sh 2>/dev/null
chmod +x "$DEST/gates/"*.sh "$DEST/.xal/"*.sh 2>/dev/null

# --- 5: vendor the process spec -----------------------------------------------------------
step "vendoring the process spec into docs/process/"
( cd "$DEST" && "$PROCESS/sync/process-sync.sh" "$PROCESS" ) || die "process-sync.sh failed"
note "pinned $(cat "$PROCESS/VERSION")"

# --- 6: the seed record ---------------------------------------------------------------------
step "writing .xal/seed.config"
cat > "$DEST/.xal/seed.config" <<EOF
# .xal/seed.config — how this repo was created. Written once, by
# xal-factory/scaffold/seed-service.sh; see that repo's adr/0002-repo-seeding.md.
#
# SEED_LANG is not a preference and not a default. It is the language this service's first
# ADR chose, on this service's workload. SEED_ADR is where that decision is recorded, so
# "why is this repo $LANG_ID?" resolves to a decision record in this repo rather than to
# whoever remembers.
#
# This file records the seed. It does not track drift: the gate script is a starting point
# this service now OWNS, unlike docs/process/, which is a vendored contract the drift gate
# keeps current. Improvements to the scaffold do not flow back here.
SEED_SERVICE=$NAME
SEED_LANG=$LANG_ID
SEED_MODULE=$MODULE
SEED_ADR=$ADR
SEED_PROCESS_VERSION=$(cat "$PROCESS/VERSION")
SEED_DATE=$(date -u +%Y-%m-%d)
EOF
note "language $LANG_ID, decided in $ADR"

# --- 6b: the factory configuration --------------------------------------------------------
# Only what differs from scripts/driver/config.sh's defaults is written, so the file reads as
# the list of decisions this repo has made. `config.sh --list` shows the rest.
step "writing .xal/factory.conf"
{
  printf '# .xal/factory.conf: this repo'"'"'s factory configuration. key = value, one per line.\n'
  printf '# Every key has a default in scripts/driver/config.sh; set only what differs.\n'
  printf '# `scripts/driver/config.sh --list` shows every key and where its value comes from.\n'
  printf '# This file is under .xal/, a protected path: a driven session cannot change it.\n\n'
  if [ -n "$OPS_REPO" ]; then printf 'factory.ops_repo = %s\n' "$OPS_REPO"
  else printf '# factory.ops_repo = <owner>/<name>   REQUIRED before the first driver run\n'; fi
} > "$DEST/.xal/factory.conf"
[ -n "$PROFILE" ] && opt_apply_profile "$PROFILE" service "$DEST/.xal/factory.conf"
opt_write_defaults service "$VERSION" "$DEST/.xal/factory.defaults"
note "defaults for $(grep -vc '^#' "$DEST/.xal/factory.defaults") option(s) in .xal/factory.defaults"
note "factory.ops_repo = ${OPS_REPO:-<unset, a human-only step below>}"

# --- 7: git ---------------------------------------------------------------------------------
step "git init + first commit"
(
  cd "$DEST" || exit 1
  git init -q -b main || exit 1
  git add -A || exit 1
  git -c commit.gpgsign=false commit -q -m "chore: seed $NAME from the xal-factory scaffold ($LANG_ID)

Seeded by xal-factory/scaffold/seed-service.sh per its ADR-0002.
Language $LANG_ID, chosen in $ADR. Process spec pinned at $(cat "$PROCESS/VERSION").

The repo arrives with its gate: scripts/check.sh in the process's gate order,
.xal/gate-inputs declaring every input, ci.yml supplying them, and committed
fixtures in gates/ proving the chain can fail and can pass — and with the
pipeline: driver.yml, chain.yml, merge.yml and reader.yml, scripts/driver/,
and gates/driver.test.sh proving the driver refuses and says why." || exit 1
) || die "git init/commit failed"
note "$(cd "$DEST" && git rev-parse --short HEAD) on main"

# --- 8: stop, and say what only a person can do ----------------------------------------------
cat <<EOF

${GREEN}${BOLD}Seeded.${RST} ${DEST}

${BOLD}Next, reversible, so nothing waits on anyone${RST}:
  cd "$DEST" && ./scripts/check.sh          # the gate, locally (some gates skip without their tool)
  gh repo create <owner>/$NAME --private --source "$DEST" --remote origin --push
  then open the first PR and let CI run — it will prove the gate can fail and can pass.
EOF
[ "$MODULE" = "example.com/$NAME" ] && cat <<EOF

${YEL}The module path defaulted to example.com/$NAME.${RST} Pass --module next time, or fix it now
  (a rename touches every import, so do it before the first real commit).
EOF
cat <<EOF

${YEL}${BOLD}Human-only, and neither CI nor the pipeline is live until these are done${RST}:
  1. Write docs/adr/0001-stack-selection.md, the decision this seed cites ($ADR).
  2. Install the Claude GitHub App on <owner>/$NAME. Granting a third party access to a repo
     is a forge UI grant, not a script's.
  3. Set three repository secrets. \`gh secret set\` exists; minting a credential does not.
       CLAUDE_CODE_OAUTH_TOKEN   runs the driver, the reader, @claude and the review bot
       FACTORY_READ_TOKEN        reads the ops repo (the admitted spec) for the driver and reader
       FACTORY_WRITE_TOKEN       opens and merges session PRs, dispatches the chain, appends to
                                 the spend ledger in the ops repo
  4. Write each secret's REAL expiry into .xal/gate-inputs, replacing every
     REPLACE-WITH-THE-TOKEN-EXPIRY. Gate 0 refuses the placeholder until you do, deliberately.
EOF
[ -z "$OPS_REPO" ] && cat <<EOF
  5. Name the ops repo in .xal/factory.conf (factory.ops_repo = <owner>/<name>). The driver
     and the reader refuse to run without it: it is where admitted specs and the ledger live.
EOF
cat <<EOF

  Optional: set the XAL_RUNNER repository variable to a self-hosted runner's label. Every
  workflow runs on \${{ vars.XAL_RUNNER || 'ubuntu-latest' }}, so unset means GitHub-hosted
  minutes, which is a spend decision rather than a correctness one.

  .github/workflows/claude.yml, claude-code-review.yml, driver.yml, chain.yml, merge.yml and
  reader.yml are committed already, so each grant has something to activate. Until it
  happens they are inert, which is the point: an inert workflow waiting on a grant, not a
  missing file waiting on someone remembering. To keep any of them off, disable it
  (\`gh workflow disable chain.yml\`) rather than deleting it, so turning it on later is one
  command and its fixtures keep running.

  Then, before the first dispatch: admit the spec in the ops repo and point
  docs/spec/service.md at it, run the planner and the plan critic, and merge the approved plan
  to main. The driver refuses to read a plan from any other ref. \`/run-session <SID>\` is the
  first dispatch; chain.yml and merge.yml take it from there, within the plan's autonomy level.

  Deploying additionally needs a provisioned target; deploy.yml is dispatch-only until
  then, and says so at the top.
EOF
