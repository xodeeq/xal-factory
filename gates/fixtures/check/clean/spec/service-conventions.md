# Service conventions

A system built from independently versioned services, possibly in several languages, only
stays operable if every service exposes the **same operational and contract surface**. This
document is that contract.

> **LANGUAGE IS AN IMPLEMENTATION DETAIL BEHIND A STANDARD CONTRACT.**

Each convention is stated language-agnostically. A service in any language mirrors the
*intent*; the *realization* is that service's own, recorded in its own repo. **Conform to
this document whenever you create or modify any service.**

Each convention is tagged:
- **[CI-enforceable]** — a machine can verify it; wire it into the service's gate script
  (see [`gate-discipline.md`](gate-discipline.md)).
- **[review-only]** — judgement required; verify in code review.

---

## 1. The API description is the HTTP source of truth — **[CI-enforceable]**
The HTTP surface is declared in `openapi.yaml` at the service root; routes and handlers
conform to it, not the other way round. Generated clients, contract tests and any service
catalogue read this file.
- *Enforce:* lint the description and assert the running app's routes match it (a
  description-vs-routes diff, or a property-based checker driven by the description) in CI.

## 2. Health: `/health/live` + `/health/ready` — **[CI-enforceable]**
- `GET /health/live` → 200 whenever the process is up (liveness; no dependencies).
- `GET /health/ready` → 200 **only** when hard dependencies (e.g. the database) are
  reachable, else 503. Orchestrators gate traffic on readiness.
- *Enforce:* CI or the smoke test hits both endpoints; readiness must be 503 before the
  database is up and 200 after.

## 3. Telemetry: OpenTelemetry + a Prometheus `/metrics` endpoint — **[CI-enforceable]**
Metrics and traces use **OpenTelemetry** (the cross-language standard); metrics are scraped
in Prometheus exposition format at `GET /metrics`.
- *Enforce:* assert `/metrics` returns Prometheus exposition format in CI.

## 4. Structured JSON logs with required fields — **[CI-enforceable]**
One JSON event per line, every line carrying **`service`**, **`environment`**,
**`traceId`** and **`event`**. **Never** log secrets, tokens or credentials.
- *Enforce:* a log-shape test asserting the required keys; the "no secrets" half is
  **[review-only]**.

## 5. `X-Trace-Id` propagation — **[CI-enforceable]**
Read the inbound `X-Trace-Id`; if absent, generate a UUID. Echo it on the response and
propagate it on outbound calls. One request is followable across service boundaries.
- *Enforce:* an integration test — a supplied header is echoed; an absent header yields a
  generated one on the response.

## 6. The container interface — **[CI-enforceable]** (config/port) · **[review-only]** (SIGTERM)
A service is a well-behaved container:
- **config from the environment** (no `.env` files in the image; secrets via env or a
  secret store);
- **listens on a configurable port**;
- **handles SIGTERM with graceful shutdown** (drain in-flight work, bounded).
- *Enforce:* CI builds the image (the image-build gate). SIGTERM drain behaviour is
  **[review-only]**; it is hard to assert cheaply.

## 7. Async-first interaction and the versioned event envelope — **[CI-enforceable]** (envelope) · **[review-only]** (edge declaration)

**Effects travel as events.** Anything that changes another service's state happens by
emitting a domain event, never by a synchronous call out of the service. A publisher never
holds a list of its consumers.

**Reads may be synchronous, narrowly.** A service may make a synchronous call for a **read
only**, when the request cannot be served with acceptable staleness from its own data, and
**one hop deep**. Token verification against an identity provider is the standing example.

**Every synchronous edge is declared.** Wherever the system records a service's
dependencies, each synchronous dependency is listed as a **runtime dependency**, distinct
from event dependencies, with a **timeout** and a **fallback** (serve stale, deny or
degrade). A service that cannot honour its declared fallback must not advertise the edge
(§9).

**Every event is a versioned envelope.** Events are carried in a standard envelope —
CloudEvents v1.0 in structured content mode is the recommended shape — with a versioned
`type` (`orders.order-placed.v1`). Consumers dispatch on the envelope, never on
transport-native metadata. **The transport behind the envelope is a per-system decision**;
the envelope is the contract.

- *Enforce:* schema-validate emitted envelopes; assert `type` is versioned. Edge
  declaration becomes **[CI-enforceable]** once a catalogue validates entries.

## 8. The purity principle — **[review-only]**
The **domain layer never touches wall-clock time, randomness or I/O** — these are
**injected**. Time enters through an explicit `now` parameter; persistence, hashing, signing
and clocks live behind ports implemented in outer layers. This keeps the core deterministic
and unit-testable without mocks of everything.
- *Verify in review:* no wall-clock reads, no RNG, no I/O in the domain layer. Promotable
  to **[CI-enforceable]** via a banned-API list, an import rule or an architecture test.

## 9. Variation behind an invariant contract — **[review-only]**
A service exposes **variation flags**, but each flag sits **behind an invariant contract**:
the core surface is identical across every flag combination; only the explicitly-allowed
slice may differ. The host **fails fast** at boot if it is configured for a profile it
cannot actually serve — a service must never advertise a capability it cannot honour.
Anything that breaks the invariant core is a **contract version bump, not a flag**.
- *Verify in review:* the invariant surface is byte-identical across flags; the fail-fast
  validator covers every unimplemented profile. The fail-fast boot is partially
  **[CI-enforceable]** via a startup test per profile.

---

## How to use this document
- **New service:** treat §1–§9 as the acceptance checklist for "conforming". Wire every
  **[CI-enforceable]** item into that service's gate script and CI.
- **Modifying any service:** if a change touches one of these surfaces, re-check it here
  first; if it would break an invariant (especially §1, §2, §5, §7, §9), that is a
  contract-version decision recorded as an ADR, not a quiet edit.
- The **deployment** counterpart to this contract is
  [`deployment-conventions.md`](deployment-conventions.md); the **gate** that enforces both
  is described in [`gate-discipline.md`](gate-discipline.md).

**Reference.** One realization pins its formatter and linter (gofmt, golangci-lint) in CI at
fixed versions; another does the same with npm audit. The rule is the pin, not the tool.
