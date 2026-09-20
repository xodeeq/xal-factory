# Deployment conventions

[`service-conventions.md`](service-conventions.md) captures the *contract* surface. This
document captures the *deployment* contract: the language-agnostic operational invariants a
service must satisfy to be deployable and composable. Each was extracted from a real first
production deploy and is stated so that a service in any language, on any host, can mirror
the intent.

---

## The overriding principle: the runtime is reproducible from files

**Convention.** A service's **entire runtime** — the compute shell *and* its observability —
is **reproducible from committed files, applied by CI**. **Nothing a human clicks.** No
dashboard hand-drawn in a UI, no alert created from memory, no app, secret or scale knob set
ad hoc and forgotten. If it is not in the repo and applied by a pipeline, it does not exist.

**Why.** A hand-built runtime is a single point of failure with no source of truth: a lost
account, a second environment or an incident recovery means re-clicking from memory.
Committed, CI-applied definitions make the runtime auditable, reviewable (a diff before it
ships) and rebuildable.

### The interface is two-handed — match the declarative tool to each platform

There is **no single tool** that declares a whole runtime, so do not force one. Use **two
hands**, and treat the split itself as the convention:

| Hand | Pattern |
|---|---|
| **Compute** | A declarative app manifest **+ an idempotent, reconcile-first provisioning script** |
| **Observability + external monitors** | Infrastructure-as-code modules, one provider per managed system |

**Match the declarative interface to each platform.** A platform with a healthy IaC
provider → use the provider. A platform that treats its own manifest as the source of truth
and has deprecated third-party providers → use that manifest plus a scripted API for the
imperative gaps. The anti-pattern is a monolithic tool fighting a platform that has its own
opinion.

**Reference.** The first realization of this split was a container host's own app manifest
plus a reconcile script for compute, and Terraform modules (a dashboards-and-alerts
provider, an uptime-monitor provider) for observability. The names matter less than the
shape.

### Pattern A — compute: declarative manifest + idempotent reconcile-first script

**Convention.** The app config is a **committed declarative manifest**. The surrounding
shell the manifest cannot express — app existence, managed-database attach, region,
scaling and minimum instances, IP allocation, and the **declaration of required secret
*names and shapes*** — is a **single idempotent script** that is **reconcile-first**: every
step is check-then-create, tolerates "already exists", and is **safe to re-run against the
live app** without duplicating or destroying anything. Secret **values** are read from
CI-injected environment and set into the platform secret store **by the script**; they are
never in the manifest, the script or the repo.

*Enforce:* the script has a `--dry-run` that reports without mutating; it runs on PRs
touching `infra/**`; a fresh run against the live app changes nothing.

### Pattern B — observability + external monitors: IaC modules

**Convention.** Dashboards, alert rules, contact points and external uptime monitors are
**infrastructure as code**, structured as **reusable modules** (they generalize across
services). Use the **first-party or official provider** per system, and vet it for
maintenance and resource coverage. Resources that carry **external identity** (a monitor, a
contact point, a data source) are **imported**, not recreated; pure **definitions**
(dashboard JSON, alert rules) are recreated from code. **No** dashboard, alert or monitor
exists outside this — what is live is what is in the modules.

*Enforce:* a fresh apply rebuilds the observability and the monitors from files.

### State and secrets hygiene (both hands)

**Convention.** IaC **state is remote, locked and sensitive** (a backend that encrypts at
rest, with state locking). **No runtime secret** (signing keys, peppers, encryption keys,
database credentials) ever enters IaC, its state, the app manifest or the repo — those live
**only** in the platform secret store, set by the provisioning script from CI environment.
**Provider and API tokens** (the IaC tooling's own credentials) come from **CI environment
only**, never committed, and are least-privilege and distinct from runtime secrets.

### CI applies it (GitOps-lite), separate from app CI/CD

**Convention.** Infra is applied by a **dedicated CI workflow**, separate from app CI and
app CD: `plan` plus the provisioning **dry-run** on **PRs touching `infra/**`**, posted for
review and **never applying**; `apply` plus the provisioning script on **merge to `main`**.
Application changes never run infra; infra changes never rebuild the app.

*Enforce:* the PR path has no apply step; a concurrency group serializes infra applies.

---

## Migrations run as a release-step artifact, never from the runtime container

**Convention.** Schema migrations are applied as a **release step** that runs against the
target database **before** new application instances take traffic — executed from a
**purpose-built migration artifact**, never from the running service container and never
from application startup code.

**Why.** Two forces meet here:

1. **The runtime image is minimal on purpose.** A production image should be a minimal,
   non-root, attack-surface-reduced artifact, which means **no SDK and often no shell**. You
   therefore *cannot* run the framework's "apply migrations" command inside it; every such
   tool needs tooling the image deliberately omits.
2. **Migrations must run exactly once per deploy, before traffic, with a clean failure
   mode.** Applying them from application startup races across replicas and couples "can
   the app boot" to "can the app migrate"; a failed migration should fail the *deploy*,
   loudly, not crash-loop the service.

The answer to both: build a **self-contained migration artifact** at image-build time (the
build stage has the SDK) and invoke it as the platform's release hook. A single image with
two entry points — `serve` and `migrate` — is the simplest shape: the migration that ran and
the code that runs are then the same build.

**Gotchas the first realizations hit, so you do not.** <!-- reference -->
- **Idempotency is mandatory** — the release step re-runs on *every* deploy, so applying
  migrations to an already-migrated database must be a clean no-op, not an error. Validate
  it by running the artifact **twice** against the same database in CI.
- **Pin the migrations-history table to an explicit schema** if your model uses a
  non-default schema. Left unqualified, the history table's location can follow the
  connection's search path and FLIP once your schema is created mid-first-migration,
  producing an empty "shadow" history table on the second run, so every migration re-runs
  and collides. (Seen with EF Core; the failure is not framework-specific.)
- **Verify the artifact runs on the *actual* runtime image** (shell-less, non-root,
  minimal): run it inside the image against a throwaway database as a pre-deploy check, and
  catch globalization and native-dependency surprises before a real deploy does.
- **Mind the image ENTRYPOINT.** Hosts typically run the release step as
  `<image ENTRYPOINT> + release_command`. If your release artifact is a *different
  executable* from the app, an app-shaped ENTRYPOINT corrupts the release command, and many
  minimal base images bake in their own ENTRYPOINT that resurfaces if you only set CMD. Fix:
  **reset `ENTRYPOINT []` and put the app command in `CMD`**, or make the app binary itself
  dispatch on a subcommand.

*Enforce:* CI builds the image (which builds the artifact); a release rehearsal applies the
artifact twice against a throwaway database and asserts the second run is a no-op.

---

## Secrets come from the platform secret store, with fail-fast production validation

**Convention.** Secrets (signing keys, peppers, encryption keys, database credentials) are
injected from the platform's **secret store** as environment variables — **never** in the
deploy manifest, the image or the repo. In **production the service fails fast on boot** if
a required secret is missing: it must refuse to start rather than silently fall back to
throwaway material.

**Why.** A service that boots with a generated-on-the-fly key "works" until the second
replica or the next restart, then mints tokens nobody can verify — a silent, corrupting
failure. Failing the boot turns that into a loud, immediate, un-missable error at deploy
time. A warned ephemeral fallback may remain for local development only.

*Enforce:* a unit test per secret factory that the production guard refuses the fallback; a
startup test per profile that a missing required secret aborts boot.

## Liveness + readiness wired to the platform's health checks

**Convention.** Expose `GET /health/live` (process up) and `GET /health/ready` (200 only when
hard dependencies are reachable, else 503). Wire the orchestrator's health checks to them:
**readiness gates traffic**, **liveness gates restart**, with a startup **grace period** that
covers boot and the release-step migration.

*Enforce:* the smoke gate hits both and expects 200; a service must answer 503 on
`/health/ready` before its database is up.

## Metrics scraped from `/metrics`

**Convention.** Export metrics in Prometheus format at `GET /metrics` via OpenTelemetry; the
platform scrapes it. A RED dashboard (Rate, Errors, Duration) over those metrics is the
baseline, codified as Pattern B above. Keep `/metrics` on the platform's **private** network
or behind a scrape token; do not expose internal telemetry publicly.

## Structured JSON logs to the platform's log stream

**Convention.** One JSON event per line to stdout (the platform collects stdout), every line
carrying `service`, `environment`, `traceId`, `event`; **never** log secrets, tokens or
credentials. The log format is **environment-independent** — no human-pretty console
formatter sneaking into production.

*Enforce:* a log-shape test for the required keys; the "no secrets" half is review-only.

## A non-root, minimal runtime image

**Convention.** The runtime image runs as a **non-root** user and carries the **minimum**
surface (no shell, SDK or package manager beyond what the process needs). This both reduces
attack surface and forces the healthy patterns above — migrations as a release step,
because you *cannot* shell in.

*Enforce:* CI builds the image; a scanner or review confirms non-root and a minimal base.

## A post-deploy smoke gate

**Convention.** After every deploy, a **smoke test** drives the live service through its core
end-to-end flow and **fails the deploy** if anything is wrong — idempotent and safe to rerun,
with a unique throwaway identity per run, and dependency-light (a shell, `curl` and little
else). This is the contract for "the deploy actually works", beyond "the process started".

*Enforce:* the CD workflow runs it against production and fails loudly on any check.

## CD from `main` only, after the gates

**Convention.** Deployment is **continuous from `main` only**, and only **after the full gate
suite passes** — kept in a **separate** workflow from CI so pull-request runs never touch
production. A manual dispatch path exists for controlled redeploys; production deploys are
serialized by a concurrency group.

*Enforce:* the deploy workflow's own gate job plus branch protection on `main`.

---

## Checklist (a service is "deployable" when…)

- [ ] The runtime is **reproducible from committed files, applied by CI** — nothing clicked:
      compute via a **declarative manifest + an idempotent reconcile-first script**;
      observability and external monitors via **IaC modules**.
- [ ] IaC **state is remote, locked and sensitive**; **no runtime secret** is in IaC, state,
      manifest or repo; provider tokens come from CI environment only.
- [ ] A **separate infra workflow** plans (and dry-runs provisioning) on infra PRs and applies
      on merge to main — never applying on a PR, never coupled to app CI/CD.
- [ ] Migrations run as a **release-step artifact** (idempotent; verified twice), not from the
      runtime container or app startup.
- [ ] Secrets come from the **platform secret store**; production **fails fast** on a missing one.
- [ ] `/health/live` + `/health/ready` exist and are **wired to the orchestrator** (readiness
      gates traffic, with a startup grace period).
- [ ] Prometheus metrics at **`/metrics`** (scraped), with a RED dashboard; `/metrics` not public.
- [ ] **Structured JSON logs** to stdout with the required fields; no secrets logged.
- [ ] **Non-root, minimal** runtime image, config from the environment.
- [ ] A **post-deploy smoke gate** fails the deploy on a broken round-trip.
- [ ] **CD from `main` only, after gates**, in a workflow separate from PR CI.
