#!/usr/bin/env bash
#
# install.sh: install the Xal Software Factory's command line, `xal-factory`.
#
#   curl -fsSL https://factory.getxal.com/install.sh | bash
#   ./install.sh                      from a clone: links this clone instead of cloning
#
# What it does, in order, and nothing else:
#   1. checks the tools the factory uses and says how to get any that are missing
#   2. puts the factory at $XAL_FACTORY_HOME (default ~/.local/share/xal-factory): a clone of
#      xodeeq/xal-factory at --ref, or this checkout when run from one
#   3. links $XAL_FACTORY_BIN/xal-factory (default ~/.local/bin) to the CLI
#   4. offers to install the Claude Code plugin (local to your machine)
#   5. offers to run `xal-factory init`, the onboarding
#
# Options: --ref <tag|branch> (default main) · --yes (take every default) · --no-init
#          --no-plugin
# It never uses sudo and never writes outside the two directories above, your Claude Code
# plugin list (only if you say yes), and the git checkout it clones.

set -uo pipefail

REPO_URL="${XAL_FACTORY_REPO:-https://github.com/xodeeq/xal-factory.git}"
HOME_DIR="${XAL_FACTORY_HOME:-$HOME/.local/share/xal-factory}"
BIN_DIR="${XAL_FACTORY_BIN:-$HOME/.local/bin}"
REF="main"; YES=0; INIT=1; PLUGIN=1

while [ $# -gt 0 ]; do
  case "$1" in
    --ref) REF="${2:-}"; shift 2 ;;
    --yes|-y) YES=1; shift ;;
    --no-init) INIT=0; shift ;;
    --no-plugin) PLUGIN=0; shift ;;
    -h|--help) sed -n '3,20p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ -t 1 ]; then BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YEL=$'\033[33m'; RST=$'\033[0m'
else BOLD=""; DIM=""; RED=""; GREEN=""; YEL=""; RST=""; fi
ok()   { printf '  %s✔%s %s\n' "$GREEN" "$RST" "$1"; }
warn() { printf '  %s·%s %s\n' "$YEL" "$RST" "$1"; }
die()  { printf '%s%s%s\n' "$RED" "$1" "$RST" >&2; exit 1; }

# Under `curl | bash` stdin is the script, so questions read from the terminal.
TTY=""
if [ "$YES" = 0 ] && [ -r /dev/tty ] && { : < /dev/tty; } 2>/dev/null; then TTY=/dev/tty; fi
ask_yes() { # <question> <default y|n>
  local a
  [ -n "$TTY" ] || { [ "$2" = y ]; return; }
  printf '%s %s[%s]%s ' "$1" "$DIM" "$([ "$2" = y ] && printf 'Y/n' || printf 'y/N')" "$RST" > "$TTY"
  IFS= read -r a < "$TTY" || a=""
  case "${a:-$2}" in y|Y|yes) return 0 ;; *) return 1 ;; esac
}

hint() {
  local t="$1"
  if command -v brew >/dev/null 2>&1; then
    case "$t" in claude) printf 'npm install -g @anthropic-ai/claude-code' ;; *) printf 'brew install %s' "$t" ;; esac
  elif command -v apt-get >/dev/null 2>&1; then
    case "$t" in gh) printf 'see https://cli.github.com (apt)' ;; claude) printf 'npm install -g @anthropic-ai/claude-code' ;; gum) printf 'see https://github.com/charmbracelet/gum' ;; *) printf 'sudo apt-get install %s' "$t" ;; esac
  else printf 'install %s with your package manager' "$t"; fi
}

printf '\n%sXal Software Factory: install%s\n\n%sTools%s\n' "$BOLD" "$RST" "$BOLD" "$RST"
command -v git >/dev/null 2>&1 || die "git is required: $(hint git)"
missing=0
for t in git gh claude jq python3 curl; do
  if command -v "$t" >/dev/null 2>&1; then ok "$t"; else warn "$t is missing: $(hint "$t")"; missing=1; fi
done
command -v gum >/dev/null 2>&1 && ok "gum (nicer prompts)" || warn "gum is optional, for nicer prompts: $(hint gum)"
bash_major="${BASH_VERSINFO[0]:-0}"; ok "bash $bash_major (3.2 and later work)"

printf '\n%sThe factory%s\n' "$BOLD" "$RST"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$HERE" ] && [ -x "$HERE/bin/xal-factory" ] && [ -f "$HERE/factory/options.tsv" ]; then
  SRC="$HERE"; ok "using this checkout: $SRC"
else
  if [ -d "$HOME_DIR/.git" ]; then
    git -C "$HOME_DIR" fetch -q --tags origin && git -C "$HOME_DIR" checkout -q "$REF" && { git -C "$HOME_DIR" pull -q --ff-only origin "$REF" 2>/dev/null || true; } \
      || die "could not update $HOME_DIR to $REF"
    ok "updated $HOME_DIR to $REF"
  else
    mkdir -p "$(dirname "$HOME_DIR")" || die "cannot create $(dirname "$HOME_DIR")"
    git clone -q "$REPO_URL" "$HOME_DIR" && git -C "$HOME_DIR" checkout -q "$REF" || die "could not clone $REPO_URL at $REF"
    ok "cloned $REPO_URL at $REF into $HOME_DIR"
  fi
  SRC="$HOME_DIR"
fi

mkdir -p "$BIN_DIR" || die "cannot create $BIN_DIR"
ln -sf "$SRC/bin/xal-factory" "$BIN_DIR/xal-factory" || die "cannot link $BIN_DIR/xal-factory"
ok "linked $BIN_DIR/xal-factory ($("$BIN_DIR/xal-factory" version))"
case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) warn "$BIN_DIR is not on your PATH. Add this to your shell profile:"
     printf '      export PATH="%s:$PATH"\n' "$BIN_DIR" ;;
esac

if [ "$PLUGIN" = 1 ] && command -v claude >/dev/null 2>&1; then
  printf '\n%sClaude Code plugin%s\n' "$BOLD" "$RST"
  if claude plugin list 2>/dev/null | grep -q 'xal-factory'; then ok "xal-factory is installed"
  elif ask_yes "  Install the xal-factory plugin (/run-session, /idea, the reader)?" y; then
    if claude plugin marketplace add xodeeq/xal-factory >/dev/null 2>&1 && claude plugin install xal-factory@xal-factory >/dev/null 2>&1; then ok "installed xal-factory"
    else warn "could not install it; run: claude plugin marketplace add xodeeq/xal-factory && claude plugin install xal-factory@xal-factory"; fi
  else warn "skipped; later: claude plugin marketplace add xodeeq/xal-factory && claude plugin install xal-factory@xal-factory"; fi
fi

printf '\n'
[ "$missing" = 1 ] && warn "Some tools are missing (above). \`xal-factory doctor\` re-checks at any time."
if [ "$INIT" = 1 ] && [ -n "$TTY" ] && ask_yes "Set up your factory now (xal-factory init)?" y; then
  exec "$BIN_DIR/xal-factory" init < "$TTY"
fi
printf '%sInstalled.%s Next: %sxal-factory init%s  (or %sxal-factory help%s)\n' "$GREEN" "$RST" "$BOLD" "$RST" "$BOLD" "$RST"
