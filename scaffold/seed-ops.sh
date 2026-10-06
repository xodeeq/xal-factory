#!/usr/bin/env bash
#
# seed-ops.sh: create the factory's ops repo, once, with its gate already working.
#
# The ops repo is where the factory keeps what outlives any one service: admitted specs and
# their digests, the operating status and its weekday nudge, the spend ledger every driver and
# reader run appends to, the idea inbox, and the agents that plan and judge. Service repos
# (scaffold/seed-service.sh) name it in .xal/factory.conf as factory.ops_repo.
#
# It arrives with its gate, like a service does: scripts/check.sh, the declared inputs, the
# CI that supplies them, and fixtures proving each gate can fail.
#
# Usage:
#   scaffold/seed-ops.sh --name <factory name> --dest <dir>
#
#   --name   what the factory is called; fills the status title and CLAUDE.md
#   --dest   where to create the repo. Must not already exist
#
# Exit: 0 seeded · 1 a step failed · 2 called wrongly
# Deps: bash, tar, sed, find, git. No toolchain, no network.

set -uo pipefail

PROCESS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCAFFOLD="$PROCESS/scaffold"

if [ -t 1 ]; then BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YEL=$'\033[33m'; RST=$'\033[0m'
else BOLD=""; RED=""; GREEN=""; YEL=""; RST=""; fi
die()  { printf '%s%s%s\n' "$RED" "$1" "$RST" >&2; exit "${2:-1}"; }
step() { printf '\n%s━━ %s%s\n' "$BOLD" "$1" "$RST"; }
note() { printf '   %s\n' "$1"; }
usage() { printf 'usage: scaffold/seed-ops.sh --name <factory name> --dest <dir>\n' >&2; }

NAME=""; DEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="${2:-}"; shift 2 ;;
    --dest) DEST="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf '%sunknown argument: %s%s\n' "$RED" "$1" "$RST" >&2; usage; exit 2 ;;
  esac
done
[ -n "$NAME" ] || { printf '%s--name is required%s\n' "$RED" "$RST" >&2; usage; exit 2; }
[ -n "$DEST" ] || { printf '%s--dest is required%s\n' "$RED" "$RST" >&2; usage; exit 2; }
[ -e "$DEST" ] && die "destination already exists: $DEST (refusing to seed over it)" 2
[ -d "$SCAFFOLD/ops" ] || die "scaffold/ops/ is missing: this is not a factory checkout" 2
[ -f "$PROCESS/.xal/check-gate-inputs.sh" ] || die ".xal/check-gate-inputs.sh is missing from this checkout" 2

printf '\n%sSeeding the ops repo for %s into %s%s\n' "$BOLD" "$NAME" "$DEST" "$RST"
mkdir -p "$DEST" || die "could not create $DEST"
DEST="$(cd "$DEST" && pwd)"

step "copying scaffold/ops/"
( cd "$SCAFFOLD/ops" && tar -cf - . ) | ( cd "$DEST" && tar -xf - ) || die "copying ops/ failed"
cp "$PROCESS/.xal/check-gate-inputs.sh" "$DEST/.xal/check-gate-inputs.sh" || die "copying the gate-input checker failed"
# The plugin, so /idea, /begin-session and /wrap-session work here too.
mkdir -p "$DEST/.claude"
cp "$SCAFFOLD/common/.claude/settings.json" "$DEST/.claude/settings.json" || die "copying .claude/settings.json failed"
note "$(find "$DEST" -type f | wc -l | tr -d ' ') files"

step "writing the factory profile"
# The ops repo's conf is the factory profile: ops options, and the service options every new
# service starts from. `xal-factory init` fills it; seeded by hand it holds only comments.
# shellcheck source=../factory/lib.sh
FACTORY_ROOT="$PROCESS" . "$PROCESS/factory/lib.sh" || die "factory/lib.sh is missing from this checkout" 2
opt_write_defaults "service ops" "$(cat "$PROCESS/VERSION")" "$DEST/.xal/factory.defaults"
{
  printf '# .xal/factory.conf: the factory profile. key = value, one per line.\n'
  printf '# Ops options apply to this repo; service options set here are the starting values\n'
  printf '# for every service seeded with `xal-factory seed`. Defaults: .xal/factory.defaults.\n'
} > "$DEST/.xal/factory.conf"
note "defaults for $(grep -vc '^#' "$DEST/.xal/factory.defaults") option(s); profile in .xal/factory.conf"

step "filling placeholders"
while IFS= read -r t; do
  [ -n "$t" ] || continue
  mv "$t" "${t%.template}" || die "renaming $t failed"
done <<< "$(find "$DEST" -type f -name '*.template' | sed '/^$/d')"
TODAY="$(date -u +%Y-%m-%d)"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -qE '<FACTORY>|<DATE>' "$f" 2>/dev/null || continue
  sed "s|<FACTORY>|$NAME|g; s|<DATE>|$TODAY|g" "$f" > "$f.seedtmp" && mv "$f.seedtmp" "$f" || die "substituting in $f failed"
done <<< "$(find "$DEST" -type f ! -path '*/.git/*' ! -path '*/gates/fixtures/*')"
chmod +x "$DEST/scripts/"*.sh "$DEST/gates/"*.sh "$DEST/.xal/"*.sh 2>/dev/null
note "<FACTORY> -> $NAME, <DATE> -> $TODAY"

step "git init + first commit"
(
  cd "$DEST" || exit 1
  git init -q -b main && git add -A && \
  git -c commit.gpgsign=false commit -q -m "chore: seed the $NAME ops repo from the xal-factory scaffold

Seeded by xal-factory/scaffold/seed-ops.sh at process $(cat "$PROCESS/VERSION"). The repo
arrives with its gate: spec intake, the plan critic's mechanical half, the status render,
declared inputs, and fixtures proving each can fail."
) || die "git init/commit failed"
note "$(cd "$DEST" && git rev-parse --short HEAD) on main"

cat <<MSG

${GREEN}${BOLD}Seeded.${RST} ${DEST}

${BOLD}Next, reversible${RST}:
  cd "$DEST" && ./scripts/check.sh
  gh repo create <owner>/<name> --private --source "$DEST" --remote origin --push

${YEL}${BOLD}Human-only${RST}:
  1. Open the idea inbox: an issue labelled \`ideas\`, pinned. \`/idea <text>\` posts to it.
       gh label create ideas && gh issue create --title "Idea inbox" --label ideas --body "One idea per comment."
  2. Run the nudge once by hand so you have seen it fire: gh workflow run nudge.yml
  3. Name this repo in every service's .xal/factory.conf (factory.ops_repo = <owner>/<name>),
     and give the services' FACTORY_READ_TOKEN read on it and FACTORY_WRITE_TOKEN contents
     write on it (the spend ledger).

  Then the first track: research and write the first spec, admit it (specs/README.md), and
  seed its service with scaffold/seed-service.sh --ops-repo <owner>/<name>.
MSG
