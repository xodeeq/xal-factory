---
title: Install
description: Install the xal-factory command, the Claude Code plugin, and set up your factory.
---

```bash
curl -fsSL https://factory.getxal.com/install.sh | bash
```

The installer does five things and stops:

1. **Checks your tools** and prints how to install any that are missing: `git`, `gh`, `claude`
   (Claude Code), `jq`, `python3`, `curl`, and optionally [`gum`](https://github.com/charmbracelet/gum)
   for nicer prompts. Bash 3.2, the version macOS ships, is enough.
2. **Puts the factory** at `~/.local/share/xal-factory` (set `XAL_FACTORY_HOME` to change it).
3. **Links `xal-factory`** into `~/.local/bin` (set `XAL_FACTORY_BIN`), and tells you if that
   directory is not on your `PATH`.
4. **Offers the Claude Code plugin**: `/run-session`, `/idea`, `/begin-session`,
   `/wrap-session`, `/explain` and the reader agent.
5. **Offers the onboarding**, `xal-factory init`. See [Onboarding](/onboarding/).

It never uses `sudo` and writes nowhere else.

## Options

| Option | Effect |
|---|---|
| `--ref <tag or branch>` | install a release instead of `main`, for example `--ref v0.2.0` |
| `--yes` | take every default without asking |
| `--no-init` | install only; run `xal-factory init` later |
| `--no-plugin` | do not offer the Claude Code plugin |

To pass options through `curl`: `curl -fsSL https://factory.getxal.com/install.sh | bash -s -- --ref v0.2.0`.

## From a clone

```bash
git clone https://github.com/xodeeq/xal-factory.git
cd xal-factory && ./install.sh
```

Run from a clone, the installer links that clone instead of cloning again.

## Updating and removing

Run the installer again to update. To remove: delete `~/.local/bin/xal-factory` and
`~/.local/share/xal-factory`, and `claude plugin uninstall xal-factory@xal-factory`. Repos
you seeded keep working: they own what they were seeded with.

## Check your setup

```bash
xal-factory doctor
```

It checks your tools and GitHub sign-in, the plugin, and, inside a seeded repo, that its
configuration is valid, that every credential has an expiry, and that its workflows on
GitHub match its configuration.
