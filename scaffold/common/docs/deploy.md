# Deploying <SERVICE>

The contract is `docs/process/deployment-conventions.md`. This file says how this repo
meets it.

**The adapter is configured, not edited in.** `deploy.target` in `.xal/factory.conf` picks
the job in `.github/workflows/deploy.yml`:

| deploy.target | What deploy.yml does |
|---|---|
| `none` (default) | the gate, then a loud refusal: there is nothing to deploy to |
| `fly` | the gate, `flyctl deploy` (whose `release_command` runs `migrate` first), then `scripts/smoke.sh` against `deploy.url` |

**Turning on a target is a person's act**, because it spends and grants access:

1. Provision the host app, the database and the production secrets.
2. For `fly`: copy `deploy/fly.toml.example` to `fly.toml`, set the app name and region.
3. Set the `FLY_API_TOKEN` secret and uncomment its row in `.xal/gate-inputs` with its real
   expiry, so gate 0 watches it.
4. Set `deploy.target` and `deploy.url` in `.xal/factory.conf`, by PR (the file is protected).
5. Dispatch `deploy.yml` once by hand and watch the smoke pass.
6. Only then un-comment the `push: branches: [main]` trigger, so `main` deploys on merge.

`xal-factory config set deploy.target fly` performs steps 3 and 4 and prints the rest.

**Monitoring.** Health, metrics, structured logs and trace propagation are the service
conventions §2 to §5. What to page on, and what to do when paged, is
`docs/runbook-alerts.md`.
