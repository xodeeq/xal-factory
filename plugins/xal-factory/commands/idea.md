---
description: Capture one idea, in one line, into the factory's idea inbox (a pinned issue labelled `ideas` in the ops repo). Nothing is triaged here; the weekly review drains the inbox and replies to every comment with its disposition.
argument-hint: "<the idea, one line>"
allowed-tools: Bash(gh issue list:*), Bash(gh issue comment:*), Bash(gh repo view:*), Bash(sed:*), Bash(awk:*), Bash(test:*)
disable-model-invocation: true
---

# /idea $ARGUMENTS

Append **$ARGUMENTS** as one comment on the open issue labelled `ideas` in the factory's ops
repo, and stop. Do not evaluate the idea, do not create a board item, do not start work.
Capture is the whole job. Triage is the weekly review's (the `idea-triage` agent in the ops
repo, gated on every line being accounted for), and it replies to the comment with the
disposition.

If `$ARGUMENTS` is empty, ask for the one line and stop.

**Which repo is the ops repo**, in this order: `$FACTORY_OPS_REPO` if it is set; else
`factory.ops_repo` in this repo's `.xal/factory.conf`; else this repo itself, if it carries
`status/current.md` (it is the ops repo). If none applies, say so and stop: an idea posted to
a guessed repository is an idea lost.

```bash
ops="${FACTORY_OPS_REPO:-}"
[ -n "$ops" ] || ops="$(test -f .xal/factory.conf && sed 's/#.*//' .xal/factory.conf | awk -F= '$1 ~ /^[ \t]*factory\.ops_repo[ \t]*$/ { gsub(/[ \t]/, "", $2); print $2 }')"
[ -n "$ops" ] || { test -f status/current.md && ops="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"; }
[ -n "$ops" ] || { echo "no ops repo: set FACTORY_OPS_REPO, or factory.ops_repo in .xal/factory.conf"; exit 2; }
n=$(gh issue list -R "$ops" --label ideas --state open --json number --jq '.[0].number // empty')
[ -n "$n" ] || { echo "no open issue labelled 'ideas' in $ops: open one, pin it, and re-run"; exit 2; }
gh issue comment "$n" -R "$ops" --body "$ARGUMENTS"
```

Confirm with the comment URL the command printed. One idea per invocation: three ideas are
three invocations, because the triage gate counts lines.

If the factory has switched the inbox off (`ops.idea_inbox = off` in the ops repo's
configuration), there is no labelled issue and the command says so. Turn it back on with
`xal-factory config set ops.idea_inbox on`, which opens and pins the issue.
