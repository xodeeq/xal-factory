#!/usr/bin/env bash
# Render the weekday nudge from status/current.md frontmatter.
# Usage: scripts/status-render.sh [path-to-status-file]
# Exit 0 and print the nudge; exit 1 (with a reason on stderr) when the file
# cannot yield one: missing frontmatter, missing/empty next_action, or
# active_track missing. Only frontmatter is read; the prose is for people.
set -euo pipefail
FILE="${1:-status/current.md}"
python3 - "$FILE" <<'PY'
import re, sys
path = sys.argv[1]
try:
    text = open(path, encoding="utf-8").read()
except OSError as e:
    sys.exit(f"status-render: cannot read {path}: {e}")
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
if not m:
    sys.exit("status-render: no YAML frontmatter block")
fm = m.group(1)

def scalar(key):
    r = re.search(rf"^{key}:\s*(.*)$", fm, re.M)
    if not r:
        return None
    v = r.group(1).strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        v = v[1:-1]
    return v

def items(key):
    r = re.search(rf"^{key}:\s*\n((?:[ \t]+-[^\n]*\n?)*)", fm, re.M)
    if not r:
        return []
    out = []
    for line in r.group(1).splitlines():
        v = line.strip()[1:].strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]
        if v:
            out.append(v)
    return out

if scalar("type") != "status":
    sys.exit("status-render: frontmatter type is not 'status'")
track = scalar("active_track")
action = scalar("next_action")
if not track:
    sys.exit("status-render: active_track missing")
if not action:
    sys.exit("status-render: next_action missing or empty")
lines = [f"Today's one action: {action}"]
for b in items("blockers"):
    lines.append(f"Needs you: {b}")
lane = scalar("research_lane")
if lane:
    lines.append(f"Research lane: {lane}")
lines.append(f"Track: {track}. Updated {scalar('updated') or 'unknown'}. Mark done by committing status/current.md.")
print("\n".join(lines))
PY
