#!/usr/bin/env bash
#
# options-page.sh: render factory/options.tsv as the docs' options reference, on stdout.
#
# Plain bash and awk so the factory's own gate can run it without Node: gate 14 asserts the
# page it prints names every option in the registry. scripts/sync-content.mjs writes it to
# src/content/docs/options.md before every build.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REG="$ROOT/factory/options.tsv"
[ -f "$REG" ] || { printf 'options-page: no registry at %s\n' "$REG" >&2; exit 2; }
VERSION="$(cat "$ROOT/VERSION")"
cat <<'HEAD'
---
title: Every option
description: Each factory option, its default, its choices, and how to change it later. Generated from factory/options.tsv.
---

Every option has a default, so a factory that sets nothing runs the default profile. This
page is generated from [`factory/options.tsv`](https://github.com/xodeeq/xal-factory/blob/main/factory/options.tsv),
the same registry the onboarding reads, so it cannot disagree with it.

**Scope** says where an option is set: in each **service** repo's `.xal/factory.conf`, or in
the **ops** repo's, which is also the factory profile every new service starts from. A value
set in a reviewed file, not a settings page, is the point: see
[ADR-0009](/adr/0009-configuration/).

`xal-factory config explain <key>` prints any row below in the terminal.

HEAD
awk -F'\t' -v ver="$VERSION" '
  !/^#/ && NF && $1 != "key" {
    sect = $1; sub(/\..*/, "", sect)
    if (sect != last) { printf "\n## %s\n\n", sect; last = sect }
    d = $2; gsub(/<VERSION>/, ver, d)
    c = $3; if (c == "*") c = "any text"; else if (c == "int") c = "a positive whole number"; else gsub(/\|/, ", ", c)
    printf "### `%s`\n\n%s\n\n", $1, $7
    printf "| Default | Choices | Scope | Onboarding asks |\n|---|---|---|---|\n| `%s` | %s | %s | %s |\n\n", d, c, $4, $6
    l = $8; gsub(/\|/, "\\|", l)
    printf "**Change it later:** `%s`\n\n", l
  }' "$REG"
