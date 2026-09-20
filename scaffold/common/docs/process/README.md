# docs/process/ — vendored process spec (read-only)

The files here are **vendored, read-only copies** of the Xal Engineering Process spec,
synced from the process repo by `process-sync.sh`. **Do not edit them here** — edit the spec
in the process repo and re-run the sync. `sync.config` records the process `VERSION` this
repo is pinned to.

```bash
# from this repo's root — update the vendored spec, then review the diff in your PR:
/path/to/xal-engineering-process/sync/process-sync.sh /path/to/xal-engineering-process

# CI gate — fail if this repo is behind the process spec:
/path/to/xal-engineering-process/sync/process-sync.sh /path/to/xal-engineering-process --check
```

After the first sync this directory also contains `process-guide.md`,
`service-conventions.md`, `deployment-conventions.md`, `gate-discipline.md`,
`adr-discipline.md`, `adr-template.md`, `concept-note-structure.md` and
`session-ritual.md`. See the process repo's `sync/SYNC.md` for the full model.
